import 'dart:async';
import 'dart:convert';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'existing_account_link_fakes.dart';
import 'session_fakes.dart';
import 'app_session_persistence_test.dart' show MemorySessionStorage;

/// Mirrors the SDK's save of Session.toJson() at OAuth completion, without any
/// real browser, Supabase instance, credentials, or disk access.
class PersistingGoogleFake extends FakeSupabaseAuthPort {
  PersistingGoogleFake(this.storage) {
    deliverOnSignIn = snapshot();
  }
  final AppSessionPersistence storage;
  @override
  Future<bool> startGoogleSignIn({
    String redirectTo = kChumbucketOAuthRedirect,
  }) async {
    storage.beginInteractiveSignIn();
    await storage.persistSession(
      jsonEncode({
        'access_token': 'synthetic-only',
        'user': {'id': kAuthUserId},
      }),
    );
    return super.startGoogleSignIn(redirectTo: redirectTo);
  }
}

void main() {
  late ClaimRig r;
  setUp(() {
    r = ClaimRig();
  });
  tearDown(() => r.close());

  test(
    'existing person survives; exact server bytes signed and confirmed before viewer adoption',
    () async {
      final seen = <String?>[];
      r.session.addListener(() => seen.add(r.session.userId));
      expect(await r.link(), isTrue);
      expect(r.session.userId, kCanonicalUserId);
      expect(r.session.authUserId, kAuthUserId);
      expect(r.session.status, SessionStatus.ready);
      expect(seen.whereType<String>().toSet(), {kCanonicalUserId});
      expect(r.wallet.signed.single, r.proof['message']);
      expect(r.redirectPolicies, everyElement(isFalse));
      expect(r.requests.map((q) => q.procedurePath), [
        'auth.identityStatus',
        'auth.whoami',
        'auth.requestExistingAccountProof',
        'auth.claimExistingAccount',
        'auth.whoami',
      ]);
      final request = r.requests[3];
      expect(request.input.keys.toSet(), {
        'supabaseAccessToken',
        'address',
        'message',
        'signature',
      });
      expect(request.input['message'], r.wallet.signed.single);
      for (final q in r.requests) {
        expect(q.url.hasQuery, isFalse);
        expect(q.url.toString(), isNot(contains(kAccessToken)));
        if (q.procedurePath == 'auth.identityStatus') {
          expect(q.method, 'GET');
          expect(q.headers['authorization'], isNull);
        } else {
          expect(q.method, 'POST');
          expect(q.headers['authorization'], 'Bearer $kAccessToken');
        }
        expect(q.input.containsKey('userId'), isFalse);
        expect(q.input.containsKey('authUserId'), isFalse);
      }
    },
  );

  for (final gate in ['enabled', 'existingAccountClaimsEnabled']) {
    test(
      '$gate off stops before Google or wallet and preserves wallet',
      () async {
        r.capability[gate] = false;
        expect(await r.link(), isFalse);
        expect(r.session.existingLinkError?.code, 'ACCOUNT_CLAIMS_DISABLED');
        expect(r.auth.startCount, 0);
        expect(r.wallet.signed, isEmpty);
        expect(r.wallet.userId, kCanonicalUserId);
      },
    );
  }
  for (final mismatch in [
    'network',
    'proofVersion',
    'allowedDomains',
    'allowedUris',
  ]) {
    test('$mismatch mismatch fails before OAuth', () async {
      r.capability[mismatch] = switch (mismatch) {
        'network' => 'mainnet-beta',
        'proofVersion' => 2,
        _ => <String>[],
      };
      expect(await r.link(), isFalse);
      expect(r.auth.startCount, 0);
    });
  }
  test('no existing profile never invokes profile creation', () async {
    r.wallet.userId = null;
    expect(await r.link(), isFalse);
    expect(r.auth.startCount, 0);
    expect(r.session.existingLinkError?.code, 'ACCOUNT_CLAIM_UNAVAILABLE');
  });
  test(
    'Google linked to another person is refused before wallet signature',
    () async {
      r.beforeUser = 'another-person';
      expect(await r.link(), isFalse);
      expect(r.session.existingLinkError?.code, 'ACCOUNT_CLAIM_CONFLICT');
      expect(r.wallet.signed, isEmpty);
      expect(r.claimed, isFalse);
      expect(r.session.userId, isNull);
      expect(r.auth.signOutCount, 1);
      r.auth.emit(SupabaseAuthEventKind.signedIn, snapshot());
      await Future<void>.delayed(Duration.zero);
      expect(r.session.hasSupabaseSession, isFalse);
    },
  );
  test('already claimed reply is accepted only for this same person', () async {
    r.beforeUser = kCanonicalUserId;
    r.outcome = 'already_claimed';
    expect(await r.link(), isTrue);
    expect(r.session.userId, kCanonicalUserId);
  });
  for (final wrong in [
    'claimed person',
    'claimed subject',
    'confirmed person',
    'confirmed subject',
    'outcome',
  ]) {
    test('wrong $wrong cannot be adopted', () async {
      switch (wrong) {
        case 'claimed person':
          r.claimedUser = 'other';
        case 'claimed subject':
          r.claimedSubject = 'other';
        case 'confirmed person':
          r.confirmedUser = 'other';
        case 'confirmed subject':
          r.confirmedSubject = 'other';
        case 'outcome':
          r.outcome = 'created';
      }
      expect(await r.link(), isFalse);
      expect(r.session.userId, isNull);
      expect(r.session.hasSupabaseSession, isFalse);
    });
  }
  test(
    'wallet cancellation sanitizes platform error; retry stays on old account',
    () async {
      r.wallet.signingError = StateError(
        'synthetic-sensitive-platform-payload',
      );
      expect(await r.link(), isFalse);
      expect(
        r.session.existingLinkError.toString(),
        isNot(contains('synthetic-sensitive')),
      );
      expect(r.claimed, isFalse);
      expect(r.wallet.userId, kCanonicalUserId);
      r.wallet.signingError = null;
      expect(await r.link(), isTrue);
      expect(r.auth.startCount, 2);
    },
  );
  test('aborted browser clears only Google, not existing wallet', () async {
    r.auth.launchSucceeds = false;
    expect(await r.link(), isFalse);
    expect(r.session.existingLinkError?.code, SessionErrorCode.oauthCancelled);
    expect(r.wallet.signed, isEmpty);
    expect(r.wallet.isCurrent, isTrue);
  });
  test('expired proof is refused before wallet prompt', () async {
    r.proof.addAll(
      claimProof(now: DateTime.now().subtract(const Duration(hours: 1))),
    );
    expect(await r.link(), isFalse);
    expect(r.wallet.signed, isEmpty);
    expect(r.session.existingLinkError?.code, 'NONCE_EXPIRED');
  });
  for (final code in [
    'ACCOUNT_CLAIM_UNAVAILABLE',
    'ACCOUNT_CLAIM_CONFLICT',
    'ACCOUNT_CLAIM_RATE_LIMITED',
    'NONCE_EXPIRED',
    'NONCE_REUSED',
  ]) {
    test('$code is understandable and never creates a replacement', () async {
      r.failures['auth.claimExistingAccount'] = code;
      expect(await r.link(), isFalse);
      expect(r.session.existingLinkError?.code, code);
      expect(r.session.existingLinkError?.message, isNot(code));
      expect(
        r.requests.any((q) => q.procedurePath == 'auth.completeProfile'),
        isFalse,
      );
    });
  }
  test(
    'new profile, general sign-in, restore and retry cannot race a pending claim',
    () async {
      r.wallet.signature = Completer<String>();
      final linking = r.link();
      await r.reachWallet();
      expect(await r.session.bffAuthToken(), isNull);
      await r.session.completeProfile('Duplicate');
      await r.session.signInWithGoogle();
      await r.session.retryIdentity();
      await r.session.restore();
      expect(await r.link(), isFalse);
      expect(r.auth.startCount, 1);
      r.wallet.signature!.complete('synthetic-signature');
      expect(await linking, isTrue);
    },
  );
  for (final action in [
    'wallet change',
    'wallet reconnect',
    'Google change',
    'logout',
    'dismiss',
    'dispose',
  ]) {
    test(
      '$action during signing discards late signature and cannot submit claim',
      () async {
        r.wallet.signature = Completer<String>();
        final linking = r.link();
        await r.reachWallet();
        switch (action) {
          case 'wallet change':
            r.wallet.address = 'other';
          case 'wallet reconnect':
            r.wallet.isCurrent = false;
          case 'Google change':
            r.auth.emit(
              SupabaseAuthEventKind.signedIn,
              snapshot(authUserId: 'other'),
            );
            r.auth.emit(SupabaseAuthEventKind.signedIn, snapshot());
            await Future<void>.delayed(Duration.zero);
          case 'logout':
            await r.session.signOut();
          case 'dismiss':
            r.session.cancelExistingAccountLink();
          case 'dispose':
            r.session.dispose();
            r.disposed = true;
        }
        r.wallet.signature!.complete('synthetic-signature');
        expect(await linking, isFalse);
        expect(r.claimed, isFalse);
        expect(r.session.userId, isNull);
      },
    );
  }
  for (final path in [
    'auth.identityStatus',
    'auth.requestExistingAccountProof',
    'auth.claimExistingAccount',
  ]) {
    test('logout while $path is in flight cannot restore identity', () async {
      final hold = r.holds[path] = Completer<void>();
      final linking = r.link();
      await r.reach(path);
      await r.session.signOut();
      hold.complete();
      expect(await linking, isFalse);
      expect(r.session.userId, isNull);
      expect(r.session.status, SessionStatus.signedOut);
      expect(await r.session.bffAuthToken(), isNull);
    });
  }
  test('unknown server error text never leaks credentials to UI', () async {
    r.failures['auth.claimExistingAccount'] = jsonEncode({
      'token': kAccessToken,
    });
    expect(await r.link(), isFalse);
    expect(
      r.session.existingLinkError.toString(),
      isNot(contains(kAccessToken)),
    );
  });

  test(
    'abandoned Google callback times out and cannot later adopt an account',
    () async {
      final timed = ClaimRig(oauthTimeout: const Duration(milliseconds: 20));
      addTearDown(timed.close);
      timed.auth.deliverOnSignIn = null;
      expect(await timed.link(), isFalse);
      timed.auth.emit(SupabaseAuthEventKind.signedIn, snapshot());
      await Future<void>.delayed(Duration.zero);
      expect(timed.session.hasSupabaseSession, isFalse);
      expect(timed.claimed, isFalse);
      expect(timed.wallet.signed, isEmpty);
    },
  );

  test('disabled capability preserves a previously verified session', () async {
    r.auth.restored = snapshot();
    r.beforeUser = kCanonicalUserId;
    await r.session.restore();
    r.capability['existingAccountClaimsEnabled'] = false;
    expect(await r.link(), isFalse);
    expect(r.session.isReady, isTrue);
    expect(r.session.userId, kCanonicalUserId);
    expect(await r.session.bffAuthToken(), kAccessToken);
    expect(r.auth.signOutCount, 0);
  });

  for (final valid in [true, false]) {
    test(
      'OAuth storage commits only after same-person confirmation ($valid)',
      () async {
        final memory = MemorySessionStorage();
        final storage = AppSessionPersistence(memory);
        AppSessionPersistence.current = storage;
        final auth = PersistingGoogleFake(storage);
        final session = ChumbucketSession(auth: auth, bff: r.bff);
        addTearDown(() async {
          session.dispose();
          await auth.close();
          AppSessionPersistence.current = null;
        });
        if (!valid) r.confirmedUser = 'another-person';
        r.wallet.signature = Completer<String>();
        final linking = session.linkExistingAccount(r.wallet);
        await r.reachWallet();
        expect(memory.value, isNull);
        r.wallet.signature!.complete('synthetic-signature');
        expect(await linking, valid);
        expect(memory.value != null, valid);
        expect(session.userId, valid ? kCanonicalUserId : null);
      },
    );
  }
}
