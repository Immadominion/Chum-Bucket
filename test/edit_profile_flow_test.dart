// Edit profile reads and writes the signed-in person's OWN account through
// the BFF (`account.me` / `account.updateProfile`), keyed by the session —
// so it works for a wallet sign-in and a Google/X sign-in alike, and never
// writes a profile row by wallet through the anon client (prod readiness
// B1, M9). These tests drive the real ChumbucketSession over fakes; nothing
// touches Supabase or the network.

import 'dart:async';

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_fakes.dart';

class _Account implements AccountApi {
  AccountProfile? profile = const AccountProfile(
    userId: kCanonicalUserId,
    handle: 'ada',
    displayName: 'Ada Okafor',
    bio: 'My existing bio.',
    avatarId: 2,
  );
  Completer<AccountProfile?>? pendingLoad;
  Completer<void>? pendingSave;
  bool saveSucceeds = true;
  bool throwOnLoad = false;
  bool throwOnSave = false;
  int lookups = 0;
  final writes = <({String? displayName, String? bio, int? avatarId})>[];

  @override
  Future<AccountProfile> me() async {
    lookups++;
    if (throwOnLoad) throw const CallsFailure();
    final p = pendingLoad != null ? await pendingLoad!.future : profile;
    if (p == null) throw const CallsFailure();
    return p;
  }

  @override
  Future<AccountProfile> updateProfile({
    String? displayName,
    String? bio,
    int? avatarId,
  }) async {
    writes.add((displayName: displayName, bio: bio, avatarId: avatarId));
    if (throwOnSave) throw StateError('fixture failure');
    if (pendingSave != null) await pendingSave!.future;
    if (!saveSucceeds) {
      throw const CallsRejectedException('Keep your name to 60 characters.');
    }
    return profile = AccountProfile(
      userId: kCanonicalUserId,
      displayName: displayName ?? profile?.displayName,
      bio: bio ?? profile?.bio,
      avatarId: avatarId ?? profile?.avatarId,
    );
  }

  @override
  Future<AddWalletFriendResult> addWalletFriend({
    required String walletAddress,
    String? nickname,
  }) => throw UnimplementedError();

  @override
  Future<bool> registerPushToken({
    required String token,
    required String platform,
  }) => throw UnimplementedError();

  @override
  Future<void> unregisterPushToken(String token) => throw UnimplementedError();

  @override
  Future<bool> pushStatus() async => false;
}

class _Harness {
  _Harness({bool signedIn = true})
    : auth = FakeSupabaseAuthPort(restored: signedIn ? snapshot() : null) {
    session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: happyBff().client,
      ),
    );
  }
  final FakeSupabaseAuthPort auth;
  late final ChumbucketSession session;
}

Future<_Harness> _openEditor(
  WidgetTester tester,
  _Account account, {
  bool signedIn = true,
  bool requiredSetup = false,
  ValueChanged<Object?>? onResult,
}) async {
  final h = _Harness(signedIn: signedIn);
  await tester.runAsync(() => h.session.restore());
  addTearDown(() async {
    h.session.dispose();
    await h.auth.close();
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChumbucketSession>.value(value: h.session),
        Provider<AccountApi>.value(value: account),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: TextButton(
                        onPressed: () async {
                          final result = await Navigator.of(
                            context,
                          ).push<Object?>(
                            MaterialPageRoute(
                              builder:
                                  (_) => EditProfileScreen(
                                    isRequired: requiredSetup,
                                    showCancelIcon: !requiredSetup,
                                  ),
                            ),
                          );
                          onResult?.call(result);
                        },
                        child: const Text('Original Profile tab'),
                      ),
                    ),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Original Profile tab'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return h;
}

ChallengeButton _saveButton(WidgetTester tester) =>
    tester.widget<ChallengeButton>(find.byType(ChallengeButton));

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(ChallengeButton));
  await tester.tap(find.byType(ChallengeButton));
  await tester.pump();
}

void main() {
  testWidgets('loads your own account and cancel returns to the same route', (
    tester,
  ) async {
    final account = _Account();
    var returned = false;
    Object? result = true;
    await _openEditor(
      tester,
      account,
      onResult: (value) {
        returned = true;
        result = value;
      },
    );
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(find.text('My existing bio.'), findsOneWidget);
    expect(account.lookups, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Original Profile tab'), findsOneWidget);
    expect(returned, isTrue);
    expect(result, isNull);
    expect(account.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save writes name and bio once and returns true', (
    tester,
  ) async {
    final account = _Account()..pendingSave = Completer<void>();
    Object? result;
    await _openEditor(tester, account, onResult: (value) => result = value);
    await tester.enterText(find.byType(TextFormField).first, ' Ada Updated ');
    final callback = _saveButton(tester).createNewChallenge;
    callback();
    callback(); // A second tap before the busy frame must not duplicate writes.
    await tester.pump();
    expect(account.writes, [
      (displayName: 'Ada Updated', bio: 'My existing bio.', avatarId: null),
    ]);
    expect(_saveButton(tester).isLoading, isTrue);
    account.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a Chumbucket account it offers sign-in, not a save', (
    tester,
  ) async {
    final account = _Account();
    await _openEditor(tester, account, signedIn: false);
    expect(
      find.textContaining('Sign in to edit your profile'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
    expect(_saveButton(tester).enabled, isFalse);
    _saveButton(tester).createNewChallenge();
    expect(account.writes, isEmpty);
    expect(account.lookups, 0);
  });

  testWidgets('a pending load cannot overwrite an editable draft', (
    tester,
  ) async {
    final account = _Account()..pendingLoad = Completer<AccountProfile?>();
    await _openEditor(tester, account);
    expect(find.text('Loading your profile…'), findsOneWidget);
    expect(_saveButton(tester).enabled, isFalse);
    _saveButton(tester).createNewChallenge();
    expect(account.writes, isEmpty);
    account.pendingLoad!.complete(account.profile);
    await tester.pumpAndSettle();
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(_saveButton(tester).enabled, isTrue);
  });

  testWidgets('a failed load refuses a blank-profile save and can retry', (
    tester,
  ) async {
    final account = _Account()..throwOnLoad = true;
    await _openEditor(tester, account);
    expect(
      find.text(
        'Your profile could not be loaded. Retry before making changes.',
      ),
      findsOneWidget,
    );
    expect(_saveButton(tester).enabled, isFalse);
    account.throwOnLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(_saveButton(tester).enabled, isTrue);
    expect(account.lookups, 2);
  });

  for (final throws in [false, true]) {
    testWidgets('a refused save keeps the draft and route (throws=$throws)', (
      tester,
    ) async {
      final account =
          _Account()
            ..saveSucceeds = false
            ..throwOnSave = throws;
      await _openEditor(tester, account);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Keep this draft',
      );
      await _save(tester);
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(_saveButton(tester).isLoading, isFalse);
      expect(account.writes.length, 1);
      if (!throws) {
        // The server's refusal is shown in its own words.
        expect(find.text('Keep your name to 60 characters.'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'the content policy answers at once and sends nothing; the server has the last word',
    (tester) async {
      final account = _Account();
      await _openEditor(tester, account);
      // The app's copy of the rule (trust): a link in a public name never
      // leaves the phone, and the draft stays.
      await tester.enterText(
        find.byType(TextFormField).first,
        'Ada at pump.fun',
      );
      await _save(tester);
      await tester.pumpAndSettle();
      expect(account.writes, isEmpty);
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Ada at pump.fun'), findsOneWidget);
      // Whatever the server refuses (account.updateProfile runs the same
      // policy) comes back in its own words through the same save.
      account.saveSucceeds = false;
      await tester.enterText(find.byType(TextFormField).first, 'Ada');
      await _save(tester);
      await tester.pumpAndSettle();
      expect(account.writes.length, 1);
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signing out after load refuses the save', (tester) async {
    final account = _Account();
    final h = await _openEditor(tester, account);
    h.auth.emit(SupabaseAuthEventKind.signedOut);
    await tester.pump();
    await _save(tester);
    await tester.pumpAndSettle();
    expect(account.writes, isEmpty);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('Account changed'), findsOneWidget);
  });

  testWidgets('a late load after leaving the editor touches nothing', (
    tester,
  ) async {
    final account = _Account()..pendingLoad = Completer<AccountProfile?>();
    await _openEditor(tester, account);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    account.pendingLoad!.complete(account.profile);
    await tester.pumpAndSettle();
    expect(find.text('Original Profile tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-time setup keeps its title and rejects blank names', (
    tester,
  ) async {
    final account =
        _Account()..profile = const AccountProfile(userId: kCanonicalUserId);
    await _openEditor(tester, account, requiredSetup: true);
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '   ');
    await _save(tester);
    await tester.pumpAndSettle();
    expect(find.text('Please enter your full name'), findsOneWidget);
    expect(account.writes, isEmpty);
  });
}
