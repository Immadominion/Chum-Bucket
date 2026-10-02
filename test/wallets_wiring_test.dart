/// Every money path picks the same wallet: a connected wallet app first, else
/// the account's linked wallet on this phone (Add funds' ownership proof,
/// market publishing and SOL for fees, as `choosePantaSigner` already does
/// for trades).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/deposits/data/device_deposit_wallet_source.dart';
import 'package:chumbucket/features/deposits/domain/deposit_wallet_source.dart';
import 'package:chumbucket/features/deposits/presentation/deposits_dependencies.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_create.dart';
import 'package:chumbucket/features/market_creation/presentation/proposal_detail_screen.dart';
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_dependencies.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:solana/solana.dart' show Ed25519HDPublicKey, verifySignature;

import 'identity_embedded_wallet_test.dart' show kTestPhraseAddress;
import 'identity_fakes.dart' show MemorySecretStore, kTestPhrase;

class _WalletApp extends MwaAuthProvider {
  _WalletApp(this.address);
  final String? address;
  @override
  bool get isAuthenticated => address != null;
  @override
  String? get walletAddress => address;
  @override
  int get authRevision => 1;
}

Future<EmbeddedWalletController> _linkedOnPhone(WidgetTester tester) async {
  final vault = EmbeddedWalletVault(store: MemorySecretStore());
  await vault.save(
    'user-1',
    EmbeddedWalletRecord(
      address: kTestPhraseAddress,
      recoveryPhrase: kTestPhrase,
      linked: true,
      createdAt: DateTime.utc(2026, 10, 2),
    ),
  );
  final controller = EmbeddedWalletController(
    vault: vault,
    bff: SessionBffClient(
      baseUrl: 'https://bff.invalid',
      httpClient: MockClient((_) async => throw StateError('no network')),
    ),
    authToken: () async => 'synthetic-session-token',
  );
  await tester.runAsync(() => controller.bind('user-1'));
  return controller;
}

Future<BuildContext> _context(
  WidgetTester tester, {
  MwaAuthProvider? walletApp,
  EmbeddedWalletController? onPhone,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MwaAuthProvider?>.value(value: walletApp),
        ChangeNotifierProvider<EmbeddedWalletController?>.value(value: onPhone),
      ],
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet'));

  testWidgets('Add funds: the wallet on this phone signs ownership proofs', (
    tester,
  ) async {
    final onPhone = await _linkedOnPhone(tester);
    addTearDown(onPhone.dispose);
    final context = await _context(tester, onPhone: onPhone);
    final source = depositWalletSourceOf(context);
    expect(source, isA<DeviceDepositWalletSource>());
    expect(source!.kind, DepositWalletKind.device);
    expect(source.address, kTestPhraseAddress);
    expect(source.isCurrent, isTrue);
    final message = Uint8List.fromList(utf8.encode('Crossmint proof'));
    final signature = await tester.runAsync(() => source.signMessage(message));
    expect(
      await tester.runAsync(
        () => verifySignature(
          message: message,
          signature: signature!,
          publicKey: Ed25519HDPublicKey.fromBase58(kTestPhraseAddress),
        ),
      ),
      isTrue,
    );
    // Signed out since: nothing is signed.
    await tester.runAsync(() => onPhone.bind(null));
    expect(source.isCurrent, isFalse);
    await expectLater(
      source.signMessage(message),
      throwsA(isA<DepositWalletDeclined>()),
    );
  });

  testWidgets('a connected wallet app still comes first', (tester) async {
    final onPhone = await _linkedOnPhone(tester);
    addTearDown(onPhone.dispose);
    final app = _WalletApp('9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM');
    final context = await _context(tester, walletApp: app, onPhone: onPhone);
    expect(depositWalletSourceOf(context)?.kind, DepositWalletKind.mwa);
    final publish = publishWalletOf(context);
    expect(publish?.address, app.address);
    expect(publish?.port, isNot(isA<PantaEmbeddedCreateWallet>()));
    expect(
      solTopUpSignerFor(
        walletApp: app,
        onPhone: onPhone,
        wallet: app.address!,
      )?.kind,
      TopUpSignerKind.walletApp,
    );
  });

  testWidgets('no wallet app: publishing and SOL for fees use this phone', (
    tester,
  ) async {
    final onPhone = await _linkedOnPhone(tester);
    addTearDown(onPhone.dispose);
    final context = await _context(tester, onPhone: onPhone);
    final publish = publishWalletOf(context);
    expect(publish?.address, kTestPhraseAddress);
    expect(publish?.port, isA<PantaEmbeddedCreateWallet>());
    expect(
      solTopUpSignerFor(
        walletApp: null,
        onPhone: onPhone,
        wallet: kTestPhraseAddress,
      )?.kind,
      TopUpSignerKind.thisPhone,
    );
    // Only for the wallet being topped up.
    expect(
      solTopUpSignerFor(
        walletApp: null,
        onPhone: onPhone,
        wallet: '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM',
      ),
      isNull,
    );
  });

  testWidgets('neither: nothing pretends to sign', (tester) async {
    final context = await _context(tester);
    expect(depositWalletSourceOf(context), isNull);
    expect(publishWalletOf(context), isNull);
  });
}
