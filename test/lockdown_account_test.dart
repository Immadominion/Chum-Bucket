// Lockdown, app side (prod readiness B1, M1, M2, M3, M7, M9, B3):
//
// * every profile and avatar write goes to the BFF with the session, never
//   through the anon client keyed by a wallet (adding a friend is a follow,
//   people.follow, tested in add_friend_sheet_test.dart);
// * other people's avatars render from their chosen avatar id;
// * the notification permission is asked in context, once, and the device is
//   registered for the ACCOUNT;
// * nothing in lib/ still writes users rows, fcm_tokens, or pushes to a
//   named wallet.

import 'dart:io';

import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/data/avatar_catalog.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/widgets/profile_picture_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bff_calls_fixtures.dart';

class _RecordingAccount implements AccountApi {
  final calls = <String>[];
  int? savedAvatar;
  bool pushEnabled = true;
  final tokens = <String>[];

  @override
  Future<AccountProfile> me() async {
    calls.add('me');
    return const AccountProfile(userId: 'usr_google_only', avatarId: 1);
  }

  @override
  Future<AccountProfile> updateProfile({
    String? displayName,
    String? bio,
    int? avatarId,
  }) async {
    calls.add('updateProfile');
    savedAvatar = avatarId;
    return AccountProfile(userId: 'usr_google_only', avatarId: avatarId);
  }

  @override
  Future<bool> registerPushToken({
    required String token,
    required String platform,
  }) async {
    tokens.add(token);
    return pushEnabled;
  }

  @override
  Future<void> unregisterPushToken(String token) async {}

  /// Whether this fake server sends pushes (`account.pushStatus`).
  bool serverSendsPushes = true;

  @override
  Future<bool> pushStatus() async => serverSendsPushes;
}

class _FakePush implements PushPlatform {
  @override
  bool get available => true;
  bool permitted = false;
  bool grant = true;
  int prompts = 0;
  final registered = <String>[];
  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<bool> requestPermission() async {
    prompts++;
    permitted = grant;
    return grant;
  }

  @override
  Future<void> register(AccountApi api, {required String accountKey}) async {
    registered.add(accountKey);
  }
}

class _CountingInbox extends NotificationsProvider {
  _CountingInbox() : super(repository: MockNotificationsRepository());
  int refreshes = 0;
  @override
  Future<void> refreshUnreadCount() async => refreshes++;
}

class _Profiles extends ChangeNotifier implements ProfileProvider {
  final remembered = <String>[];
  @override
  Future<bool> setUserPfp(String key, String pfpPath) async {
    remembered.add('$key=$pfpPath');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, {required AccountApi account, ProfileProvider? p}) =>
    MultiProvider(
      providers: [
        Provider<AccountApi>.value(value: account),
        if (p != null) ChangeNotifierProvider<ProfileProvider>.value(value: p),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
      ),
    );

void main() {
  group('the account API speaks session-keyed account.* and nothing else', () {
    test('updateProfile posts only the fields given, with the bearer', () async {
      final server = FakeBffServer.routes({
        'account.updateProfile': {
          'profile': {
            'userId': 'usr_1',
            'displayName': 'Ada',
            'bio': null,
            'avatarId': 3,
            'walletAddress': null,
          },
        },
      });
      final api = BffAccountApi(
        transport: CallsBffTransport(
          baseUrl: 'https://bff.test',
          httpClient: server.client,
          authToken: () => 'session-token',
          verbose: false,
        ),
      );
      final saved = await api.updateProfile(avatarId: 3);
      expect(saved.avatarId, 3);
      expect(saved.avatarAsset, kAvatarAssets[2]);
      final sent = server.requestFor('account.updateProfile');
      expect(sent.method, 'POST');
      expect(sent.input, {'avatarId': 3});
      expect(sent.headers['authorization'], 'Bearer session-token');
      // Nothing that names an identity ever leaves the client.
      expect(sent.body, isNot(contains('wallet')));
      expect(sent.body, isNot(contains('userId')));
    });

    test('a refusal arrives as the server wrote it', () async {
      final server = FakeBffServer.failing(
        code: 'BAD_REQUEST',
        httpStatus: 400,
        message: 'Pick one of the five pictures.',
      );
      final api = BffAccountApi(
        transport: CallsBffTransport(
          baseUrl: 'https://bff.test',
          httpClient: server.client,
          verbose: false,
        ),
      );
      await expectLater(
        api.updateProfile(avatarId: 9),
        throwsA(
          isA<CallsRejectedException>().having(
            (e) => e.message,
            'message',
            'Pick one of the five pictures.',
          ),
        ),
      );
    });
  });

  group('other people\'s avatars render (M9)', () {
    test('a person with an avatar id gets that picture; a URL wins', () {
      Map<String, dynamic> person(Map<String, dynamic> extra) => {
        'id': 'u1',
        'handle': 'u1',
        'displayName': 'U One',
        'walletAddress': null,
        'settledCalls': 0,
        'correctCalls': 0,
        ...extra,
      };
      expect(
        personFromJson(person({'avatarUrl': null, 'avatarId': 4})).avatarUrl,
        'assets/images/ai_gen/profile_images/4.png',
      );
      expect(
        personFromJson(
          person({'avatarUrl': 'https://cdn.test/a.png', 'avatarId': 4}),
        ).avatarUrl,
        'https://cdn.test/a.png',
      );
      expect(
        personFromJson(person({'avatarUrl': null, 'avatarId': 9})).avatarUrl,
        isNull,
      );
      expect(
        NotificationActor.fromJson({
          'id': 'u2',
          'handle': 'u2',
          'displayName': 'U Two',
          'avatarUrl': null,
          'avatarId': 2,
        }).avatarUrl,
        kAvatarAssets[1],
      );
    });
  });

  testWidgets(
    'the avatar picker saves to the account, with no wallet at all (M9)',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final account = _RecordingAccount();
      final profiles = _Profiles();
      await tester.pumpWidget(
        _app(
          Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => ProfilePictureSelectionModal.show(
                        context,
                        currentProfilePicture: kAvatarAssets[0],
                      ),
                  child: const Text('open'),
                ),
          ),
          account: account,
          p: profiles,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final fourth = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == kAvatarAssets[3],
      );
      await tester.ensureVisible(fourth);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == kAvatarAssets[3],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Save Profile Picture'));
      await tester.pumpAndSettle();
      expect(account.calls, ['updateProfile']);
      expect(account.savedAvatar, 4);
      // Remembered on the device under the account id, since there is no wallet.
      expect(profiles.remembered, ['usr_google_only=${kAvatarAssets[3]}']);
      expect(find.byType(ProfilePictureSelectionModal), findsNothing);
    },
  );

  group('notification permission is asked in context (M7)', () {
    late _FakePush push;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      push = _FakePush();
      PushRegistration.platform = push;
    });
    tearDown(() => PushRegistration.platform = const FcmPushPlatform());

    Future<BuildContext> mount(
      WidgetTester tester, {
      _RecordingAccount? account,
    }) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
          account: account ?? _RecordingAccount(),
        ),
      );
      return ctx;
    }

    testWidgets('a server that sends no pushes is never asked for one', (
      tester,
    ) async {
      final ctx = await mount(
        tester,
        account: _RecordingAccount()..serverSendsPushes = false,
      );
      await PushRegistration.afterSocialAction(ctx);
      await tester.pumpAndSettle();
      expect(find.text('Know when it lands'), findsNothing);
      expect(push.prompts, 0);
    });

    testWidgets('three asks, or two refusals, and it never asks again', (
      tester,
    ) async {
      final ctx = await mount(tester);
      var at = DateTime.utc(2026, 10, 3);
      PushRegistration.clock = () => at;
      addTearDown(() => PushRegistration.clock = DateTime.now);
      push.grant = false;
      for (var i = 0; i < 2; i++) {
        final done = PushRegistration.afterSocialAction(ctx);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Turn on notifications'));
        await tester.pumpAndSettle();
        await done;
        at = at.add(const Duration(days: 15));
      }
      expect(push.prompts, 2);
      expect(
        (await PushRegistration.readRecord()).permanentlyDenied,
        isTrue,
      );
      await PushRegistration.afterSocialAction(ctx);
      await tester.pumpAndSettle();
      expect(find.text('Know when it lands'), findsNothing);
      expect(push.prompts, 2);
    });

    testWidgets('explains first; "Not now" never shows the OS prompt', (
      tester,
    ) async {
      final ctx = await mount(tester);
      final done = PushRegistration.afterSocialAction(ctx);
      await tester.pumpAndSettle();
      expect(find.text('Know when it lands'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await done;
      expect(push.prompts, 0);
      expect(push.registered, isEmpty);
      // And it does not nag: the next action within two weeks asks nothing.
      await PushRegistration.afterSocialAction(ctx);
      await tester.pumpAndSettle();
      expect(find.text('Know when it lands'), findsNothing);
    });

    testWidgets('yes -> OS prompt -> this device is registered', (
      tester,
    ) async {
      final ctx = await mount(tester);
      final done = PushRegistration.afterSocialAction(ctx);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();
      await done;
      expect(push.prompts, 1);
      expect(push.registered, ['local']);
    });

    testWidgets('already allowed: registers quietly, no sheet', (
      tester,
    ) async {
      push.permitted = true;
      final ctx = await mount(tester);
      await PushRegistration.afterSocialAction(ctx);
      await tester.pumpAndSettle();
      expect(find.text('Know when it lands'), findsNothing);
      expect(push.registered, ['local']);
      await PushRegistration.syncIfPermitted(ctx);
      expect(push.registered, ['local', 'local']);
    });
  });

  group('the unread badge is refreshed, not only on first build (M3)', () {
    setUp(() => PushRegistration.platform = _FakePush()..permitted = false);
    tearDown(() {
      PushRegistration.platform = const FcmPushPlatform();
      FcmTokenService.onCallNotification = null;
    });

    testWidgets('on app resume and on a call push while open', (tester) async {
      final inbox = _CountingInbox();
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: inbox,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => MaterialApp(
                  home: Scaffold(
                    body: ChumbucketAppHeader(
                      showAccountActions: false,
                      onActivityTap: () {},
                    ),
                  ),
                ),
          ),
        ),
      );
      await tester.pump();
      final before = inbox.refreshes;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(inbox.refreshes, before + 1);

      FcmTokenService.onCallNotification?.call();
      await tester.pump();
      expect(inbox.refreshes, before + 2);

      // Gone with the header: a later push touches nothing.
      await tester.pumpWidget(const SizedBox());
      expect(FcmTokenService.onCallNotification, isNull);
    });
  });

  test('no client code writes identity rows, push tokens or pushes', () {
    final offenders = <String>[];
    final forbidden = <RegExp>[
      RegExp(r"""\.from\(\s*'users'\s*\)\s*\.(update|insert|upsert|delete)"""),
      RegExp(r"""\.from\(\s*'fcm_tokens'\s*\)"""),
      RegExp(r"""\.from\(\s*'linked_wallets'\s*\)"""),
      RegExp(r"""rpc\(\s*'update_user_profile"""),
      RegExp(r"""invoke\(\s*'send-challenge-notification'"""),
    ];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      // Collapse whitespace so a call split across lines is still seen.
      final source = file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      for (final rule in forbidden) {
        if (rule.hasMatch(source)) offenders.add('${file.path}: ${rule.pattern}');
      }
    }
    expect(offenders, isEmpty);
  });
}
