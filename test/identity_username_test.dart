/// Usernames for everyone: an account without a @username (made before
/// usernames, or a wallet profile carried over to wallet sign-in) is told so
/// by `auth.whoami`, asked once to claim one, and shows the real one after.
/// Plus "Last used": the session remembers how it was last signed in.
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/presentation/widgets/claim_handle_sheet.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

/// A BFF whose whoami reports [handle] (omitted entirely when
/// [handleKnown] is false), and which accepts or refuses a claim.
class UsernameBff {
  UsernameBff({this.handle, this.handleKnown = true, this.refuseWith});
  String? handle;
  bool handleKnown;
  String? refuseWith;
  final Set<String> taken = {'taken_one'};

  late final FakeBffServer server = FakeBffServer((request) {
    switch (request.procedurePath) {
      case 'auth.whoami':
        return okResponse({
          'userId': kCanonicalUserId,
          'authUserId': kAuthUserId,
          if (handleKnown) 'handle': handle,
        });
      case 'auth.usernameStatus':
        final input =
            jsonDecode(request.url.queryParameters['input']!)['json'] as Map;
        final asked = input['handle'] as String;
        return okResponse({
          'handle': asked,
          'status': taken.contains(asked) ? 'taken' : 'available',
        });
      case 'auth.claimUsername':
        final refusal = refuseWith;
        if (refusal != null) {
          return errorResponse(
            code: 'CONFLICT',
            httpStatus: 409,
            message: refusal,
          );
        }
        final input =
            (jsonDecode(request.body) as Map<String, dynamic>)['json'] as Map;
        handle = input['handle'] as String;
        return okResponse({
          'userId': kCanonicalUserId,
          'authUserId': kAuthUserId,
          'handle': handle,
          'outcome': 'claimed',
        });
    }
    return errorResponse(code: 'NOT_FOUND', httpStatus: 404);
  });
}

Future<(ChumbucketSession, FakeSupabaseAuthPort)> signedIn(
  UsernameBff bff, {
  LastSignInStore? lastSignIn,
}) async {
  final auth = FakeSupabaseAuthPort(restored: snapshot());
  final session = ChumbucketSession(
    auth: auth,
    bff: SessionBffClient(baseUrl: kSessionBase, httpClient: bff.server.client),
    lastSignIn: lastSignIn ?? MemoryLastSignInStore(),
  );
  await session.restore();
  return (session, auth);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('whoami says whether there is a username', () {
    test('null: the account needs one', () async {
      final (session, auth) = await signedIn(UsernameBff());
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      expect(session.isReady, isTrue);
      expect(session.handle, isNull);
      expect(session.needsHandleClaim, isTrue);
    });

    test('a handle: shown as is, no prompt', () async {
      final (session, auth) = await signedIn(UsernameBff(handle: 'dominion'));
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      expect(session.handle, 'dominion');
      expect(session.needsHandleClaim, isFalse);
    });

    test(
      'not said (an older server, or a failed read): never read as "none"',
      () async {
        final (session, auth) = await signedIn(UsernameBff(handleKnown: false));
        addTearDown(() async {
          session.dispose();
          await auth.close();
        });
        expect(session.isReady, isTrue);
        expect(session.needsHandleClaim, isFalse);
      },
    );
  });

  group('claiming', () {
    test(
      'POSTs the handle with the bearer, never in a URL; the session shows it',
      () async {
        final bff = UsernameBff();
        final (session, auth) = await signedIn(bff);
        addTearDown(() async {
          session.dispose();
          await auth.close();
        });
        expect(await session.claimUsername('Ada_1'), isNull);
        expect(session.handle, 'ada_1');
        expect(session.needsHandleClaim, isFalse);
        final request = bff.server.requestFor('auth.claimUsername');
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer $kAccessToken');
        expect(request.url.toString(), isNot(contains(kAccessToken)));
        expect(request.url.query, isEmpty);
        final input =
            (jsonDecode(request.body) as Map<String, dynamic>)['json'] as Map;
        expect(input, {'supabaseAccessToken': kAccessToken, 'handle': 'ada_1'});
      },
    );

    test(
      'a refusal says why and leaves the person signed in, still asked',
      () async {
        for (final (code, says) in [
          ('USERNAME_TAKEN', 'That username is taken'),
          ('HANDLE_ALREADY_SET', 'already has a username'),
        ]) {
          final (session, auth) = await signedIn(UsernameBff(refuseWith: code));
          final error = await session.claimUsername('ada_1');
          expect(error?.code, code);
          expect(error?.message, contains(says));
          expect(session.isReady, isTrue);
          expect(session.status, SessionStatus.ready);
          expect(session.needsHandleClaim, isTrue);
          session.dispose();
          await auth.close();
        }
      },
    );

    test(
      'claimed on another phone: learns the stored one and stops asking',
      () async {
        final bff = UsernameBff(refuseWith: 'HANDLE_ALREADY_SET');
        final (session, auth) = await signedIn(bff);
        expect(session.needsHandleClaim, isTrue);
        // Meanwhile, another phone claimed one.
        bff.handle = 'ada_elsewhere';
        final error = await session.claimUsername('ada_1');
        expect(error?.code, 'HANDLE_ALREADY_SET');
        expect(error?.message, contains('@ada_elsewhere'));
        expect(session.needsHandleClaim, isFalse);
        expect(session.handle, 'ada_elsewhere');
        session.dispose();
        await auth.close();
      },
    );

    test('signed out: nothing is sent', () async {
      final bff = UsernameBff();
      final session = ChumbucketSession(
        auth: FakeSupabaseAuthPort(),
        bff: SessionBffClient(
          baseUrl: kSessionBase,
          httpClient: bff.server.client,
        ),
        lastSignIn: MemoryLastSignInStore(),
      );
      addTearDown(session.dispose);
      expect((await session.claimUsername('ada_1'))?.isRefused, isTrue);
      expect(bff.server.received, isEmpty);
    });
  });

  group('last used', () {
    test(
      'a Google sign-in that reaches an account is remembered; a restore is not',
      () async {
        final memory = MemoryLastSignInStore();
        final (restoredSession, restoredAuth) = await signedIn(
          UsernameBff(handle: 'x'),
          lastSignIn: memory,
        );
        expect(memory.writes, 0, reason: 'a launch is not a sign-in');
        restoredSession.dispose();
        await restoredAuth.close();

        for (final method in [SignInMethod.google, SignInMethod.x]) {
          final auth = FakeSupabaseAuthPort()..deliverOnSignIn = snapshot();
          final session = ChumbucketSession(
            auth: auth,
            bff: SessionBffClient(
              baseUrl: kSessionBase,
              httpClient: UsernameBff(handle: 'ada').server.client,
            ),
            lastSignIn: memory,
          );
          if (method == SignInMethod.google) {
            await session.signInWithGoogle();
          } else {
            await session.signInWithX();
          }
          expect(session.isReady, isTrue);
          expect(memory.value, method);
          expect(session.lastSignInMethod, method);
          session.dispose();
          await auth.close();
        }
      },
    );

    test('a refused sign-in is not remembered', () async {
      final memory = MemoryLastSignInStore(SignInMethod.wallet);
      final auth = FakeSupabaseAuthPort()..launchSucceeds = false;
      final session = ChumbucketSession(
        auth: auth,
        bff: SessionBffClient(
          baseUrl: kSessionBase,
          httpClient: UsernameBff().server.client,
        ),
        lastSignIn: memory,
      );
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      await session.signInWithGoogle();
      expect(session.status, SessionStatus.failed);
      expect(memory.value, SignInMethod.wallet);
      await session.loadLastSignInMethod();
      expect(session.lastSignInMethod, SignInMethod.wallet);
    });

    test('the device store survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      const store = PreferencesLastSignInStore();
      expect(await store.read(), isNull);
      await store.write(SignInMethod.x);
      expect(await const PreferencesLastSignInStore().read(), SignInMethod.x);
    });
  });

  group('the claim sheet and the one-time prompt', () {
    Future<void> mount(
      WidgetTester tester,
      ChumbucketSession session,
      Widget child, {
      double width = 390,
      double scale = 1,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<ChumbucketSession>.value(
          value: session,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => MaterialApp(
                  builder:
                      (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!,
                      ),
                  home: Scaffold(body: child),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
      testWidgets('claims @ada_1 and closes (${width}dp, ${scale}x text)', (
        tester,
      ) async {
        final bff = UsernameBff();
        final (session, auth) =
            await tester.runAsync(() => signedIn(bff))
                as (ChumbucketSession, FakeSupabaseAuthPort);
        addTearDown(() async {
          session.dispose();
          await auth.close();
        });
        await mount(
          tester,
          session,
          Builder(
            builder:
                (context) => TextButton(
                  onPressed: () => showClaimHandleSheet(context),
                  child: const Text('open'),
                ),
          ),
          width: width,
          scale: scale,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(ChumbucketWavySheet), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('claim-handle')),
          'taken_one',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('@taken_one is taken'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('claim-handle')),
          'Ada_1',
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('@ada_1 is yours to claim'), findsOneWidget);
        await tester.ensureVisible(find.text('Claim @ada_1'));
        await tester.tap(find.text('Claim @ada_1'));
        await tester.pumpAndSettle();
        expect(session.handle, 'ada_1');
        expect(find.byType(ChumbucketWavySheet), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a refused claim keeps the sheet up and says why', (
      tester,
    ) async {
      final bff = UsernameBff(refuseWith: 'USERNAME_TAKEN');
      final (session, auth) =
          await tester.runAsync(() => signedIn(bff))
              as (ChumbucketSession, FakeSupabaseAuthPort);
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      await mount(tester, session, const ClaimHandleForm());
      await tester.enterText(find.byKey(const ValueKey('claim-handle')), 'ada');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claim @ada'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('claim-handle-error')), findsOneWidget);
      expect(session.needsHandleClaim, isTrue);
    });

    testWidgets('asked once per account on this device, never again', (
      tester,
    ) async {
      final memory = _MemoryPrompt();
      final bff = UsernameBff();
      final (session, auth) =
          await tester.runAsync(() => signedIn(bff))
              as (ChumbucketSession, FakeSupabaseAuthPort);
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      await mount(
        tester,
        session,
        UsernameClaimPrompt(memory: memory, child: const Text('home')),
      );
      expect(find.text('Claim your username'), findsOneWidget);
      expect(memory.offered, {kCanonicalUserId});
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Claim your username'), findsNothing);

      // A new launch of the shell: already offered, so no sheet.
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        session,
        UsernameClaimPrompt(memory: memory, child: const Text('home again')),
      );
      expect(find.text('home again'), findsOneWidget);
      expect(find.text('Claim your username'), findsNothing);
    });

    testWidgets('an account that has a username is never asked', (
      tester,
    ) async {
      final memory = _MemoryPrompt();
      final (session, auth) =
          await tester.runAsync(() => signedIn(UsernameBff(handle: 'dominion')))
              as (ChumbucketSession, FakeSupabaseAuthPort);
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      await mount(
        tester,
        session,
        UsernameClaimPrompt(memory: memory, child: const Text('home')),
      );
      expect(find.text('Claim your username'), findsNothing);
      expect(memory.offered, isEmpty);
    });
  });
}

class _MemoryPrompt implements HandlePromptMemory {
  final Set<String> offered = {};
  @override
  Future<bool> wasOffered(String userId) async => offered.contains(userId);
  @override
  Future<void> markOffered(String userId) async => offered.add(userId);
}
