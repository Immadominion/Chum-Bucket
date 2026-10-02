import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/arena_notifications_screen.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/presentation/screens/activity_screen.dart';
import 'package:chumbucket/features/notifications/presentation/widgets/notification_row.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'existing_account_link_fakes.dart' show ClaimRig;
import 'packet_g_fixtures.dart' show usePhoneSurface;

/// The earlier challenge system's wallet notices, without a network.
class _LegacyArena extends ArenaProvider {
  _LegacyArena(this.notices);
  final List<ArenaNotification> notices;
  int loads = 0;

  @override
  List<ArenaNotification> get notifications => notices;
  @override
  int get unreadNotificationCount => notices.where((n) => n.isUnread).length;
  @override
  bool get isLoadingNotifications => false;
  @override
  String? get notificationsError => null;
  @override
  Future<void> loadNotifications({required String walletAddress}) async {
    loads++;
  }
}

class _Wallet extends MwaAuthProvider {
  @override
  String get walletAddress => 'wallet-under-test';
  @override
  bool get isAuthenticated => true;
}

ArenaNotification _claim() => ArenaNotification(
  id: 'legacy-1',
  type: 'CLAIM_AVAILABLE',
  title: 'Your winnings are ready to claim',
  body: 'Open My Pots to claim.',
  data: const {},
  readAt: null,
  createdAt: DateTime.utc(2026, 9, 20),
);

Widget _host({
  required NotificationsProvider inbox,
  ArenaProvider? arena,
  MwaAuthProvider? wallet,
  ChumbucketSession? session,
  required Widget child,
}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationsProvider>.value(value: inbox),
          if (arena != null)
            ChangeNotifierProvider<ArenaProvider>.value(value: arena),
          if (wallet != null)
            ChangeNotifierProvider<MwaAuthProvider>.value(value: wallet),
          if (session != null)
            ChangeNotifierProvider<ChumbucketSession>.value(value: session),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: child),
      ),
);

NotificationsProvider _signedIn() =>
    NotificationsProvider(repository: MockNotificationsRepository())
      ..setViewer(MockCallsRepository.demoViewerUserId);

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet'));

  testWidgets('calls activity lists the inbox and opens what was tapped', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final inbox = _signedIn();
    final opened = <CallNotificationTarget>[];
    await tester.pumpWidget(
      _host(
        inbox: inbox,
        child: ActivityScreen(
          openTarget: (_, target) async => opened.add(target),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your calls'), findsOneWidget);
    expect(find.byType(NotificationRow), findsWidgets);
    // No wallet: the earlier-challenges section is not shown at all.
    expect(find.text('Earlier challenges'), findsNothing);

    final first = inbox.notifications.first;
    await tester.tap(find.byType(NotificationRow).first);
    await tester.pumpAndSettle();
    expect(opened, [first.target]);
    expect(
      inbox.notifications.firstWhere((n) => n.id == first.id).isUnread,
      isFalse,
    );
  });

  testWidgets('no session: one Sign in row, and the screen stays usable', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final inbox = NotificationsProvider(
      repository: MockNotificationsRepository(),
    )..setViewer(null);
    await tester.pumpWidget(
      _host(
        inbox: inbox,
        arena: _LegacyArena([_claim()]),
        wallet: _Wallet(),
        child: const ActivityScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(NotificationRow), findsNothing);
    // The earlier wallet notices moved to Settings → History (read-only);
    // Activity is the calls inbox only, even with a wallet connected.
    expect(find.text('Earlier challenges'), findsNothing);
    expect(find.byType(ArenaNotificationRow), findsNothing);
  });

  testWidgets('the bell counts calls activity only and opens Activity', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final inbox = _signedIn();
    final arena = _LegacyArena([_claim()]);
    await tester.pumpWidget(
      _host(
        inbox: inbox,
        arena: arena,
        wallet: _Wallet(),
        child: const Scaffold(
          body: ChumbucketAppHeader(title: 'Home', showAccountActions: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final calls = inbox.unreadCount;
    expect(calls, greaterThan(0));
    // The Arena notices are not fetched for, or counted on, the bell.
    expect(arena.loads, 0);
    expect(find.byTooltip('$calls unread'), findsOneWidget);

    await tester.tap(find.byTooltip('$calls unread'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('Sign in opens the one sign-in sheet, wallet first', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final rig = ClaimRig();
    addTearDown(rig.close);
    final inbox = NotificationsProvider(
      repository: MockNotificationsRepository(),
    )..setViewer(null);
    await tester.pumpWidget(
      _host(
        inbox: inbox,
        wallet: _Wallet(),
        session: rig.session,
        child: const ActivityScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(ChumbucketSignInSheet), findsOneWidget);
    expect(find.text('Continue with wallet'), findsOneWidget);
    // Nothing is signed or claimed by opening it.
    expect(rig.auth.startCount, 0);
    expect(rig.requests, isEmpty);
  });
}
