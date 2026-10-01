import 'dart:async';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:chumbucket/shared/services/friend_connection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = '11111111111111111111111111111111';
const friend = 'So11111111111111111111111111111111111111112';

class FakeFriends implements FriendConnectionService {
  @override
  String? currentWallet = owner;
  final writes = <String>[];
  final handles = <String>[];
  bool succeed = true;
  Future<String?> Function(String)? resolve;
  Future<ArenaCreatePendingTargetResult> Function(String)? handle;
  @override
  Future<String?> resolveDomain(String domain) async =>
      resolve == null ? friend : resolve!(domain);
  @override
  Future<ArenaCreatePendingTargetResult> addHandle(String value) async {
    handles.add(value);
    return handle == null
        ? const ArenaCreatePendingTargetResult(
          id: 'pending',
          resolvedWalletAddress: null,
          alreadyResolved: false,
        )
        : handle!(value);
  }

  @override
  Future<bool> addWallet({
    required String owner,
    required String name,
    required String address,
  }) async {
    writes.add('$owner/$name/$address');
    return succeed;
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeFriends service, {
  double width = 390,
  double scale = 1,
  double keyboard = 0,
  VoidCallback? onAdded,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder:
                  (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      viewInsets: EdgeInsets.only(bottom: keyboard),
                    ),
                    child: Scaffold(
                      resizeToAvoidBottomInset: false,
                      body: AddFriendSheet(
                        service: service,
                        onFriendAdded: onAdded ?? () {},
                      ),
                    ),
                  ),
            ),
          ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String value) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('friend-identifier')),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(find.byKey(const Key('friend-identifier')), value);
  await tester.pump();
}

Future<void> submit(WidgetTester tester, [String label = 'Add friend']) async {
  final button = find.widgetWithText(TextButton, label);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    button,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'one identifier; optional name; original wallet graph and callback',
    (tester) async {
      final service = FakeFriends();
      var added = 0;
      await mount(tester, service, onAdded: () => added++);
      expect(find.text('Wallet'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
      await enter(tester, friend);
      await submit(tester);
      expect(service.writes.single, '$owner/So11…1112/$friend');
      expect(added, 1);
      expect(find.textContaining('added to your friends'), findsOneWidget);
    },
  );
  testWidgets('X remains pending honestly, without adding an unproven wallet', (
    tester,
  ) async {
    final service = FakeFriends();
    await mount(tester, service);
    await enter(tester, 'https://x.com/Alice');
    await submit(tester, 'Continue with @alice');
    expect(service.handles, ['alice']);
    expect(service.writes, isEmpty);
    expect(
      find.textContaining('no notification has been sent'),
      findsOneWidget,
    );
  });
  testWidgets('verified linked X wallet uses original friend service', (
    tester,
  ) async {
    final service =
        FakeFriends()
          ..handle =
              (_) async => const ArenaCreatePendingTargetResult(
                id: 'linked',
                resolvedWalletAddress: friend,
                alreadyResolved: true,
              );
    await mount(tester, service);
    await enter(tester, '@Alice');
    await submit(tester, 'Continue with @alice');
    expect(service.writes.single, '$owner/@alice/$friend');
  });
  testWidgets('self and signed-out requests never write', (tester) async {
    final service = FakeFriends();
    await mount(tester, service);
    await enter(tester, owner);
    await submit(tester);
    expect(find.text('That’s your own account.'), findsOneWidget);
    service.currentWallet = null;
    await enter(tester, friend);
    await submit(tester);
    expect(service.writes, isEmpty);
  });
  testWidgets('failed save can retry without retyping', (tester) async {
    final service = FakeFriends()..succeed = false;
    await mount(tester, service);
    await enter(tester, friend);
    await submit(tester);
    service.succeed = true;
    await submit(tester);
    expect(service.writes, hasLength(2));
    expect(find.textContaining('added to your friends'), findsOneWidget);
  });
  testWidgets('late domain response cannot overwrite a new wallet input', (
    tester,
  ) async {
    final result = Completer<String?>();
    final service = FakeFriends()..resolve = (_) => result.future;
    await mount(tester, service);
    await enter(tester, 'someone.skr');
    await tester.pump(const Duration(milliseconds: 500));
    await enter(tester, friend);
    result.complete(owner);
    await tester.pump();
    await submit(tester);
    expect(service.writes.single, endsWith('/$friend'));
  });
  testWidgets('account change during X proof stops friend write', (
    tester,
  ) async {
    final service = FakeFriends();
    service.handle = (_) async {
      service.currentWallet = friend;
      return const ArenaCreatePendingTargetResult(
        id: 'linked',
        resolvedWalletAddress: friend,
        alreadyResolved: true,
      );
    };
    await mount(tester, service);
    await enter(tester, '@alice');
    await submit(tester, 'Continue with @alice');
    expect(service.writes, isEmpty);
    expect(find.textContaining('Your account changed'), findsOneWidget);
  });
  testWidgets('320dp, 2x text and keyboard keep action scrollable', (
    tester,
  ) async {
    final service = FakeFriends();
    await mount(tester, service, width: 320, scale: 2, keyboard: 300);
    await enter(tester, friend);
    await submit(tester);
    expect(tester.takeException(), isNull);
    expect(service.writes, hasLength(1));
  });
}
