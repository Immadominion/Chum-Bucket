import 'dart:async';
import 'package:chumbucket/features/authentication/presentation/widgets/account_session_host.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out_controller.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/settings_bottom_sheet.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_fakes.dart';

class FakeWalletExit extends MwaAuthProvider {
  int forgotten = 0;
  @override
  Future<void> forgetSession() async {
    forgotten++;
  }
}

class DisplayOnlyWallet extends ChangeNotifier implements MwaWalletProvider {
  @override
  String? get walletAddress => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LifetimeProbe extends StatefulWidget {
  const LifetimeProbe({
    super.key,
    required this.created,
    required this.removed,
  });
  final VoidCallback created, removed;
  @override
  State<LifetimeProbe> createState() => _LifetimeProbeState();
}

class _LifetimeProbeState extends State<LifetimeProbe> {
  @override
  void initState() {
    super.initState();
    widget.created();
  }

  @override
  void dispose() {
    widget.removed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Text('private account tree'));
}

void main() {
  test(
    'all cleanup tasks run; failure stays locked and retry creates a fresh generation',
    () async {
      final controller = AppSignOutController();
      addTearDown(controller.dispose);
      var first = 0, second = 0;
      await controller.signOut([
        () async {
          first++;
          if (first == 1) throw StateError('synthetic private detail');
        },
        () async {
          second++;
        },
      ]);
      expect(first, 1);
      expect(second, 1);
      expect(controller.state, AppSignOutState.blocked);
      expect(controller.generation, 0);
      await controller.retry();
      expect(first, 2);
      expect(second, 2);
      expect(controller.state, AppSignOutState.active);
      expect(controller.generation, 1);
    },
  );

  test('double tap runs each cleanup once', () async {
    final controller = AppSignOutController();
    addTearDown(controller.dispose);
    final held = Completer<void>();
    var attempts = 0;
    final first = controller.signOut([
      () {
        attempts++;
        return held.future;
      },
    ]);
    final second = controller.signOut([
      () async {
        attempts++;
      },
    ]);
    expect(identical(first, second), isTrue);
    held.complete();
    await first;
    expect(attempts, 1);
  });

  testWidgets(
    'failed cleanup keeps account UI hidden and the retry button finishes it',
    (tester) async {
      late AppSignOutController controller;
      var attempts = 0;
      await tester.pumpWidget(
        AccountSessionHost(
          builder: (context) {
            controller = context.read<AppSignOutController>();
            return const MaterialApp(home: Text('account tree'));
          },
        ),
      );
      await controller.signOut([
        () async {
          if (++attempts == 1) throw StateError('synthetic private detail');
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('account tree'), findsNothing);
      expect(find.text('Retry sign-out'), findsOneWidget);
      expect(find.textContaining('synthetic'), findsNothing);
      await tester.tap(find.text('Retry sign-out'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('account tree'), findsOneWidget);
    },
  );

  testWidgets(
    'logout unmounts old state before cleanup and creates fresh state after it',
    (tester) async {
      var created = 0, disposed = 0;
      late AppSignOutController controller;
      final held = Completer<void>();
      await tester.pumpWidget(
        AccountSessionHost(
          builder: (context) {
            controller = context.read<AppSignOutController>();
            return LifetimeProbe(
              created: () => created++,
              removed: () => disposed++,
            );
          },
        ),
      );
      final exiting = controller.signOut([() => held.future]);
      await tester.pump();
      expect(find.text('private account tree'), findsNothing);
      expect(find.text('Signing out…'), findsOneWidget);
      expect(disposed, 1);
      held.complete();
      await exiting;
      await tester.pump();
      expect(created, 2);
      expect(find.text('private account tree'), findsOneWidget);
    },
  );

  for (final surface in ['Profile', 'Call sheet', 'Alternate settings']) {
    final profileSettings = surface == 'Profile';
    final alternateSettings = surface == 'Alternate settings';
    testWidgets(
      '$surface sign-out clears both identities and all shared effects',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppSessionPersistence.current = null;
        final auth = FakeSupabaseAuthPort(restored: snapshot());
        final session = ChumbucketSession(
          auth: auth,
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: happyBff().client,
          ),
        );
        final wallet = FakeWalletExit();
        addTearDown(() async {
          session.dispose();
          wallet.dispose();
          await auth.close();
        });
        await session.restore();
        var shared = 0, realtime = 0, notifications = 0;
        await tester.pumpWidget(
          AccountSessionHost(
            builder:
                (_) => MultiProvider(
                  providers: [
                    ChangeNotifierProvider<ChumbucketSession>.value(
                      value: session,
                    ),
                    ChangeNotifierProvider<MwaAuthProvider>.value(
                      value: wallet,
                    ),
                    ChangeNotifierProvider<MwaWalletProvider>(
                      create: (_) => DisplayOnlyWallet(),
                    ),
                    Provider.value(
                      value: AppSignOutEffects(
                        clearSharedState: () {
                          shared++;
                        },
                        detachRealtime: () async {
                          realtime++;
                        },
                        forgetNotifications: () async {
                          notifications++;
                        },
                      ),
                    ),
                  ],
                  child: ScreenUtilInit(
                    designSize: const Size(390, 844),
                    builder:
                        (_, _) => MaterialApp(
                          home: Scaffold(
                            body:
                                profileSettings
                                    ? const ProfileSettingsSheet()
                                    : alternateSettings
                                    ? const SettingsBottomSheet()
                                    : const CallSessionPanel(),
                          ),
                        ),
                  ),
                ),
          ),
        );
        await tester.pump();
        final button = find.text(
          profileSettings
              ? 'Sign Out'
              : alternateSettings
              ? 'Disconnect Wallet'
              : 'Sign out',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(auth.signOutCount, 1);
        expect(wallet.forgotten, 1);
        expect(session.userId, isNull);
        expect(session.accessToken == null, isTrue);
        expect([shared, realtime, notifications], [1, 1, 1]);
      },
    );
  }
}
