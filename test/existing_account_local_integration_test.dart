// Opt-in ONLY through the sibling API's verify-account-link-local.ts runner.
// Real HTTP/Ed25519/SQL; Google and MWA approval are synthetic, not device E2E.
import 'dart:convert';
import 'dart:io';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/existing_account_proof.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:solana/solana.dart';
import 'session_fakes.dart';

class _Wallet implements ExistingAccountWallet {
  _Wallet(this.key, this.person, {this.cancel = false});
  final Ed25519HDKeyPair key;
  final String person;
  final bool cancel;
  int signatures = 0;
  @override
  String get address => key.address;
  @override
  String get network => 'devnet';
  @override
  bool get isCurrent => true;
  @override
  Future<String?> expectedUserId() async => person;
  @override
  Future<String> signClaim(String message) async {
    if (cancel) throw StateError('Synthetic wallet cancellation');
    signatures++;
    return (await key.sign(utf8.encode(message))).toBase58();
  }
}

class _LocalClient extends http.BaseClient {
  _LocalClient(this.base, {this.loseClaimResponse = false});
  final Uri base;
  final http.Client inner = http.Client();
  bool loseClaimResponse;
  final procedures = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != base.origin ||
        request.url.hasQuery ||
        request.url.userInfo.isNotEmpty ||
        request.followRedirects) {
      throw StateError('Refused non-local or credential-unsafe test request');
    }
    procedures.add(request.url.path);
    final response = await inner.send(request);
    if (loseClaimResponse && request.url.path == '/auth.claimExistingAccount') {
      loseClaimResponse = false;
      await response.stream
          .drain<void>(); // Database commit happened; reply lost.
      throw http.ClientException('Synthetic dropped reply');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = Platform.environment['CHUM_LOCAL_ACCOUNT_FIXTURE'];
  final enabled = raw != null;
  final config = enabled ? jsonDecode(raw) as Map<String, dynamic> : null;
  final base = enabled ? Uri.parse(config!['bffBase'] as String) : null;
  if (enabled) {
    if (base!.scheme != 'http' ||
        base.host != '127.0.0.1' ||
        base.port == 80 ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.path.isNotEmpty) {
      throw StateError('Only a runner-owned loopback BFF is allowed');
    }
    // This opt-in file is a separate test isolate. The usual Flutter fake HTTP
    // override must not turn integration requests into canned 400 responses.
    HttpOverrides.global = null;
  }

  for (final name in [
    'success',
    'cancel',
    'unavailable',
    'conflict',
    'retry',
  ]) {
    test('local account continuity: $name', () async {
      final f = (config!['fixtures'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((value) => value['name'] == name);
      final key = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: List<int>.filled(32, f['seedByte'] as int),
      );
      expect(key.address == f['address'], isTrue);
      final wallet = _Wallet(
        key,
        f['userId'] as String,
        cancel: name == 'cancel',
      );
      final candidate = snapshot(
        accessToken: f['token'] as String,
        authUserId: f['authId'] as String,
      );
      final auth = FakeSupabaseAuthPort()..deliverOnSignIn = candidate;
      final client = _LocalClient(base!, loseClaimResponse: name == 'retry');
      final bff = SessionBffClient(
        baseUrl: base.toString(),
        httpClient: client,
      );
      final session = ChumbucketSession(auth: auth, bff: bff);
      addTearDown(() async {
        session.dispose();
        client.close();
        await auth.close();
      });

      final linked = await session.linkExistingAccount(wallet);
      if (name == 'success') {
        expect(linked, isTrue, reason: session.existingLinkError?.code);
      } else {
        expect(linked, isFalse);
        expect(session.userId, isNull);
        expect(session.hasSupabaseSession, isFalse);
        expect(auth.signOutCount, 1);
        if (name == 'cancel') {
          expect(wallet.signatures, 0);
          expect(
            client.procedures,
            isNot(contains('/auth.claimExistingAccount')),
          );
        }
        if (name == 'unavailable') {
          expect(session.existingLinkError?.code, 'ACCOUNT_CLAIM_UNAVAILABLE');
        }
        if (name == 'conflict') {
          expect(session.existingLinkError?.code, 'ACCOUNT_CLAIM_CONFLICT');
        }
        if (name != 'retry') {
          expect(client.procedures, isNot(contains('/auth.completeProfile')));
          return;
        }
        // A lost reply cannot undo the committed server binding. Reopen Settings
        // and prove again; the same person is recovered, never another profile.
        expect((await bff.whoami(candidate.accessToken)).userId, wallet.person);
        expect(
          await session.linkExistingAccount(wallet),
          isTrue,
          reason: session.existingLinkError?.code,
        );
      }
      expect(session.isReady, isTrue);
      expect(session.userId, wallet.person);
      expect(session.userId == session.authUserId, isFalse);
      expect(await session.bffAuthToken() == candidate.accessToken, isTrue);
      expect(client.procedures, isNot(contains('/auth.completeProfile')));

      // Reconstruct the client session over the persisted database binding.
      auth.restored = candidate;
      final restarted = ChumbucketSession(auth: auth, bff: bff);
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.userId, wallet.person);
      await session.signOut();
      expect(await session.bffAuthToken(), isNull);
      expect(session.userId, isNull);
    }, skip: !enabled);
  }
  test('local issuer rejects a structurally valid forged JWT', () async {
    final f = (config!['fixtures'] as List).first as Map<String, dynamic>;
    final client = _LocalClient(base!);
    final bff = SessionBffClient(baseUrl: base.toString(), httpClient: client);
    addTearDown(client.close);
    final segments = (f['token'] as String).split('.')
      ..[2] = 'synthetic-forgery';
    await expectLater(
      bff.whoami(segments.join('.')),
      throwsA(
        isA<SessionException>().having(
          (e) => e.error.code,
          'refusal',
          'AUTH_TOKEN_INVALID',
        ),
      ),
    );
  }, skip: !enabled);
}
