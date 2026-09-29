import 'dart:convert';
import 'dart:typed_data';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/existing_account_proof.dart';
import 'package:chumbucket/features/authentication/session/mwa_existing_account_wallet.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'existing_account_link_fakes.dart';
import 'session_fakes.dart';

class SigningFake implements MwaSigningSession {
  int closes = 0;
  Object? failure;
  void Function()? onSign;
  final messages = <Uint8List>[];
  @override
  Future<SignMessagesResult> signMessages({
    required List<Uint8List> messages,
    required List<Uint8List> addresses,
  }) async {
    this.messages.addAll(messages);
    onSign?.call();
    if (failure case final error?) throw error;
    return SignMessagesResult(
      signedMessages: [
        SignedMessage(
          message: messages.single,
          addresses: addresses,
          signatures: [Uint8List(64)],
        ),
      ],
    );
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No transaction API is allowed');
}

class WalletProviderFake extends MwaAuthProvider {
  final signing = SigningFake();
  int revision = 1;
  @override
  bool get isAuthenticated => true;
  @override
  int get authRevision => revision;
  @override
  String get walletAddress => claimAddress;
  @override
  Uint8List get publicKeyBytes => Uint8List(32);
  @override
  Future<Map<String, dynamic>?> getUserProfile() async => {
    'id': kCanonicalUserId,
  };
  @override
  Future<MwaSigningSession?> createSigningSession({String? cluster}) async =>
      signing;
}

void main() {
  final now = DateTime.utc(2026, 9, 28, 20);
  ExistingAccountProof parse(
    Map<String, dynamic> data, {
    String network = 'devnet',
  }) => ExistingAccountProof.parse(
    data,
    address: claimAddress,
    network: network,
    now: now,
  );
  test(
    'server proof v1 round trip preserves every byte and redacts debug output',
    () {
      final data = claimProof(now: now);
      final proof = parse(data);
      expect(proof.message, data['message']);
      expect(proof.toString(), isNot(contains('Nonce')));
      expect(
        () => proof.checkFresh(now: now.add(const Duration(minutes: 5))),
        throwsA(isA<SessionException>()),
      );
    },
  );
  for (var line = 0; line < 13; line++) {
    test('modified SIWS line $line is rejected before signing', () {
      final data = claimProof(now: now);
      final lines = (data['message'] as String).split('\n');
      lines[line] = '${lines[line]} injected';
      data['message'] = lines.join('\n');
      expect(() => parse(data), throwsA(isA<SessionException>()));
    });
  }
  for (final field in [
    'domain',
    'uri',
    'network',
    'purpose',
    'proofVersion',
    'issuedAt',
    'expiresAt',
  ]) {
    test(
      'untrusted $field metadata cannot select the signed purpose/identity',
      () {
        final data = claimProof(now: now)..[field] = 'injected';
        expect(() => parse(data), throwsA(isA<SessionException>()));
      },
    );
  }
  for (final message in [
    '',
    'x' * 4097,
    '${claimProof(now: now)['message']}\n',
    '${claimProof(now: now)['message']}\n- transfer:all',
  ]) {
    test(
      'malformed or extra-resource payload is refused (${message.length})',
      () {
        expect(
          () => parse(claimProof(now: now)..['message'] = message),
          throwsA(isA<SessionException>()),
        );
      },
    );
  }
  test('cluster mismatch is refused even for an otherwise valid proof', () {
    expect(
      () => parse(claimProof(now: now), network: 'mainnet-beta'),
      throwsA(isA<SessionException>()),
    );
  });
  test('future issuance and expired proofs cannot open wallet', () {
    expect(
      () => parse(claimProof(now: now.add(const Duration(minutes: 2)))),
      throwsA(isA<SessionException>()),
    );
    expect(
      () => parse(claimProof(now: now.subtract(const Duration(minutes: 6)))),
      throwsA(isA<SessionException>()),
    );
  });

  group('existing MWA signing adapter', () {
    late WalletProviderFake auth;
    setUp(() {
      dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet');
      auth = WalletProviderFake();
    });
    tearDown(() => auth.dispose());
    test(
      'signs exactly one message, closes session, preserves profile',
      () async {
        final wallet = MwaExistingAccountWallet(auth);
        expect(await wallet.expectedUserId(), kCanonicalUserId);
        final message = claimProof()['message'] as String;
        expect(await wallet.signClaim(message), base58encode(Uint8List(64)));
        expect(utf8.decode(auth.signing.messages.single), message);
        expect(auth.signing.closes, 1);
      },
    );
    test('same-wallet reconnect invalidates captured account', () async {
      final wallet = MwaExistingAccountWallet(auth);
      auth.revision++;
      expect(wallet.isCurrent, isFalse);
      await expectLater(
        wallet.signClaim('message'),
        throwsA(isA<SessionException>()),
      );
      expect(auth.signing.messages, isEmpty);
    });
    test(
      'logout during wallet response closes and refuses stale signature',
      () async {
        final wallet = MwaExistingAccountWallet(auth);
        auth.signing.onSign = () => auth.revision++;
        await expectLater(
          wallet.signClaim('message'),
          throwsA(isA<SessionException>()),
        );
        expect(auth.signing.closes, 1);
      },
    );
    test(
      'platform failure is sanitized and still closes signing session',
      () async {
        final wallet = MwaExistingAccountWallet(auth);
        auth.signing.failure = StateError('synthetic-secret');
        await expectLater(
          wallet.signClaim('message'),
          throwsA(
            isA<SessionException>().having(
              (e) => e.toString(),
              'safe error',
              isNot(contains('synthetic-secret')),
            ),
          ),
        );
        expect(auth.signing.closes, 1);
      },
    );
  });

  for (final field in [
    'message',
    'address',
    'signature length',
    'extra message',
    'extra address',
    'extra signature',
  ]) {
    test('MWA response with wrong $field is refused', () {
      final payload = Uint8List.fromList([1, 2, 3]);
      final address = Uint8List(32);
      final signed = SignedMessage(
        message: field == 'message' ? Uint8List(1) : payload,
        addresses:
            field == 'extra address'
                ? [address, address]
                : [
                  field == 'address'
                      ? Uint8List.fromList(List.filled(32, 1))
                      : address,
                ],
        signatures:
            field == 'extra signature'
                ? [Uint8List(64), Uint8List(64)]
                : [Uint8List(field == 'signature length' ? 63 : 64)],
      );
      final result = SignMessagesResult(
        signedMessages: field == 'extra message' ? [signed, signed] : [signed],
      );
      expect(
        () => claimSignature(result, message: payload, address: address),
        throwsA(isA<SessionException>()),
      );
    });
  }
}
