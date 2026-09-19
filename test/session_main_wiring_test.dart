/// The `main.dart` patch, executed.
///
/// `lib/main.dart` is integration-owned (contracts §6), so this packet files a
/// diff rather than applying one — and a filed diff that nobody has run is a
/// guess. This test builds the **exact provider graph that patch produces**,
/// with the same ordering and the same two callbacks, against injected fakes.
/// If the patch would not compile, or would wire `authUserId` where `userId`
/// belongs, or would leave the viewer unset, it fails here.
///
/// The patch itself is in
/// `docs/contracts/integration-requests/packet-session.md` §1.
///
/// The tree mirrors main.dart's `ScreenUtilInit(designSize: Size(390, 844))`
/// wrapper, which `flutter_screenutil` requires before anything reads `.sp` or
/// `.w`.
library;

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/calls/data/calls_repository_factory.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_fakes.dart';

/// The provider graph exactly as the filed patch writes it.
Widget mainDartGraph(ChumbucketSession session, {required Widget child}) =>
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder:
          (context, _) => MaterialApp(
            home: MultiProvider(
              providers: [
                // `.value` only because the test owns the session's lifetime;
                // main.dart uses `create: (_) => ChumbucketSession()..restore()`.
                ChangeNotifierProvider<ChumbucketSession>.value(value: session),
                ChangeNotifierProxyProvider<ChumbucketSession, CallsProvider>(
                  create:
                      (context) => CallsProvider(
                        repository: buildCallsRepository(
                          // The mock, so this test measures the WIRING and not
                          // the BFF. main.dart passes no `backend`, which
                          // resolves to the deployed one.
                          backend: CallsBackend.mock,
                          mockLatency: Duration.zero,
                          authToken:
                              context.read<ChumbucketSession>().bffAuthToken,
                        ),
                      ),
                  update: (_, session, calls) => calls!..setViewer(session.userId),
                ),
              ],
              child: child,
            ),
          ),
    );

void main() {
  testWidgets('signing in sets the viewer to the canonical public.users.id', (
    tester,
  ) async {
    final server = happyBff();
    final auth = FakeSupabaseAuthPort()..deliverOnSignIn = snapshot();
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    late CallsProvider calls;
    await tester.pumpWidget(
      mainDartGraph(
        session,
        child: Builder(
          builder: (context) {
            calls = context.watch<CallsProvider>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // Signed out: a person can still read, and the viewer is unset.
    expect(calls.viewerUserId, isNull);
    expect(calls.isSignedIn, isFalse);

    await session.signInWithGoogle();
    await tester.pump();

    expect(session.status, SessionStatus.ready);
    expect(calls.viewerUserId, kCanonicalUserId);
    expect(calls.isSignedIn, isTrue);
    // The canonical id, NOT auth.uid() (contracts §0 invariant 3).
    expect(calls.viewerUserId, isNot(kAuthUserId));
  });

  testWidgets('signing out clears the viewer again', (tester) async {
    final server = happyBff();
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    late CallsProvider calls;
    await tester.pumpWidget(
      mainDartGraph(
        session,
        child: Builder(
          builder: (context) {
            calls = context.watch<CallsProvider>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await session.restore();
    await tester.pump();
    expect(calls.viewerUserId, kCanonicalUserId);

    await session.signOut();
    await tester.pump();

    expect(calls.viewerUserId, isNull);
    expect(calls.isSignedIn, isFalse);
  });

  testWidgets('a session that cannot resolve leaves the viewer unset rather '
      'than guessing', (tester) async {
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: methodNotSupportedBff().client,
      ),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    late CallsProvider calls;
    await tester.pumpWidget(
      mainDartGraph(
        session,
        child: Builder(
          builder: (context) {
            calls = context.watch<CallsProvider>();
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await session.restore();
    await tester.pump();

    expect(session.status, SessionStatus.failed);
    expect(session.error!.code, SessionErrorCode.whoamiMethodNotSupported);
    // A held token is NOT an identity. Nothing was guessed into setViewer.
    expect(session.accessToken, isNotNull);
    expect(calls.viewerUserId, isNull);
  });
}
