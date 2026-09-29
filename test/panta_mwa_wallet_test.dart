import 'dart:typed_data';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

class _Signing implements MwaSigningSession {
  int closed = 0;
  final payloads = <Uint8List>[];
  void Function()? onSign;
  @override
  Future<SignPayloadsResult> signTransactions({
    required List<Uint8List> transactions,
  }) async {
    payloads.addAll(transactions);
    onSign?.call();
    return SignPayloadsResult(signedPayloads: transactions);
  }

  @override
  Future<void> close() async {
    closed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Broadcast and other wallet APIs are forbidden');
}

class _Auth extends MwaAuthProvider {
  final signing = _Signing();
  String? requestedCluster;
  int revision = 1;
  bool cancel = false;
  @override
  bool get isAuthenticated => true;
  @override
  String get walletAddress => 'synthetic-public-wallet';
  @override
  int get authRevision => revision;
  @override
  Future<MwaSigningSession?> createSigningSession({String? cluster}) async {
    requestedCluster = cluster;
    return cancel ? null : signing;
  }
}

void main() {
  setUp(() => dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet'));
  test(
    'Panta requests mainnet signing without changing the legacy network',
    () async {
      final auth = _Auth();
      final port = PantaMwaWallet(auth);
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await port.signTransaction(bytes), bytes);
      expect(auth.requestedCluster, NetworkConfig.mainnetBeta);
      expect(NetworkConfig.currentNetwork, NetworkConfig.devnet);
      expect(auth.signing.payloads, [bytes]);
      expect(auth.signing.closed, 1);
      auth.dispose();
    },
  );
  test('wallet change refuses before opening a signing session', () async {
    final auth = _Auth();
    final port = PantaMwaWallet(auth);
    auth.revision++;
    await expectLater(
      port.signTransaction(Uint8List(1)),
      throwsA(isA<PantaException>()),
    );
    expect(auth.requestedCluster, isNull);
    expect(auth.signing.payloads, isEmpty);
    auth.dispose();
  });
  test(
    'wallet change during signing discards approval and closes the session',
    () async {
      final auth = _Auth();
      final port = PantaMwaWallet(auth);
      auth.signing.onSign = () => auth.revision++;
      await expectLater(
        port.signTransaction(Uint8List(1)),
        throwsA(isA<PantaException>()),
      );
      expect(auth.signing.closed, 1);
      auth.dispose();
    },
  );
  test('wallet cancellation does not sign or broadcast', () async {
    final auth = _Auth()..cancel = true;
    await expectLater(
      PantaMwaWallet(auth).signTransaction(Uint8List(1)),
      throwsA(isA<PantaWalletCancelled>()),
    );
    expect(auth.signing.payloads, isEmpty);
    auth.dispose();
  });
}
