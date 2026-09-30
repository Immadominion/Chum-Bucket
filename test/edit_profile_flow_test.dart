import 'dart:async';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _wallet = '11111111111111111111111111111111';

class _Auth extends MwaAuthProvider {
  String? currentWallet = _wallet;
  @override
  bool get isAuthenticated => currentWallet != null;
  @override
  String? get walletAddress => currentWallet;
}

class _Profile extends ChangeNotifier implements ProfileProvider {
  Map<String, dynamic>? data = {
    'id': 'existing-person',
    'full_name': 'Ada Okafor',
    'bio': 'My existing bio.',
  };
  Completer<Map<String, dynamic>?>? pendingLoad;
  Completer<bool>? pendingSave;
  bool saveSucceeds = true;
  bool throwOnLoad = false;
  bool throwOnSave = false;
  final lookups = <String>[];
  final writes = <({String wallet, Map<String, dynamic> updates})>[];

  @override
  String? get errorMessage => 'Could not save. Please retry.';

  @override
  Future<Map<String, dynamic>?> fetchUserProfile(String wallet) async {
    lookups.add(wallet);
    if (throwOnLoad) throw StateError('fixture failure');
    return pendingLoad != null ? await pendingLoad!.future : data;
  }

  @override
  Future<bool> updateUserProfile(
    String wallet,
    Map<String, dynamic> updates,
  ) async {
    writes.add((wallet: wallet, updates: Map.of(updates)));
    if (throwOnSave) throw StateError('fixture failure');
    return pendingSave != null ? await pendingSave!.future : saveSucceeds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openEditor(
  WidgetTester tester,
  _Profile profile, {
  _Auth? auth,
  bool requiredSetup = false,
  ValueChanged<Object?>? onResult,
}) async {
  final session = auth ?? _Auth();
  addTearDown(session.dispose);
  addTearDown(profile.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MwaAuthProvider>.value(value: session),
        ChangeNotifierProvider<ProfileProvider>.value(value: profile),
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
}

ChallengeButton _saveButton(WidgetTester tester) =>
    tester.widget<ChallengeButton>(find.byType(ChallengeButton));

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(ChallengeButton));
  await tester.tap(find.byType(ChallengeButton));
  await tester.pump();
}

void main() {
  testWidgets('existing edit loads data and cancel returns to the same route', (
    tester,
  ) async {
    final profile = _Profile();
    var returned = false;
    Object? result = true;
    await _openEditor(
      tester,
      profile,
      onResult: (value) {
        returned = true;
        result = value;
      },
    );
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Complete Your Profile'), findsNothing);
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(find.text('My existing bio.'), findsOneWidget);
    expect(profile.lookups, [_wallet]);
    await tester.tap(find.byTooltip('Cancel editing'));
    await tester.pumpAndSettle();
    expect(find.text('Original Profile tab'), findsOneWidget);
    expect(returned, isTrue);
    expect(result, isNull);
    expect(profile.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save returns true without onboarding or a second Home shell', (
    tester,
  ) async {
    final profile = _Profile()..pendingSave = Completer<bool>();
    Object? result;
    await _openEditor(tester, profile, onResult: (value) => result = value);
    await tester.enterText(find.byType(TextFormField).first, ' Ada Updated ');
    final callback = _saveButton(tester).createNewChallenge;
    callback();
    callback(); // A second tap before the busy frame must not duplicate writes.
    await tester.pump();
    expect(profile.writes.length, 1);
    expect(profile.writes.single.wallet, _wallet);
    expect(profile.writes.single.updates, {
      'full_name': 'Ada Updated',
      'bio': 'My existing bio.',
    });
    expect(_saveButton(tester).isLoading, isTrue);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    profile.pendingSave!.complete(true);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('Original Profile tab'), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending load cannot overwrite an editable draft', (
    tester,
  ) async {
    final profile =
        _Profile()..pendingLoad = Completer<Map<String, dynamic>?>();
    await _openEditor(tester, profile);
    expect(find.text('Loading your profile…'), findsOneWidget);
    expect(_saveButton(tester).enabled, isFalse);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.enabled, isFalse);
    }
    _saveButton(tester).createNewChallenge();
    expect(profile.writes, isEmpty);
    profile.pendingLoad!.complete(profile.data);
    await tester.pumpAndSettle();
    expect(find.text('Ada Okafor'), findsOneWidget);
    expect(_saveButton(tester).enabled, isTrue);
  });

  for (final throws in [false, true]) {
    testWidgets(
      'failed lookup refuses blank-profile save and can retry (throws=$throws)',
      (tester) async {
        final profile = _Profile()..throwOnLoad = throws;
        final original = profile.data;
        profile.data = null;
        await _openEditor(tester, profile);
        expect(
          find.text(
            'Your profile could not be loaded. Retry before making changes.',
          ),
          findsOneWidget,
        );
        expect(_saveButton(tester).enabled, isFalse);
        _saveButton(tester).createNewChallenge();
        expect(profile.writes, isEmpty);
        profile.data = original;
        profile.throwOnLoad = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Ada Okafor'), findsOneWidget);
        expect(_saveButton(tester).enabled, isTrue);
        expect(profile.lookups, [_wallet, _wallet]);
      },
    );
  }

  for (final throws in [false, true]) {
    testWidgets('failed save retains draft and route (throws=$throws)', (
      tester,
    ) async {
      final profile =
          _Profile()
            ..saveSucceeds = false
            ..throwOnSave = throws;
      await _openEditor(tester, profile);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Keep this draft',
      );
      await _save(tester);
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(_saveButton(tester).enabled, isTrue);
      expect(_saveButton(tester).isLoading, isFalse);
      expect(profile.writes.length, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account switch after load refuses save to the previous wallet', (
    tester,
  ) async {
    final auth = _Auth();
    final profile = _Profile();
    await _openEditor(tester, profile, auth: auth);
    auth.currentWallet = 'different-wallet';
    await _save(tester);
    await tester.pumpAndSettle();
    expect(profile.writes, isEmpty);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.text('Account changed'), findsOneWidget);
  });

  testWidgets('late load after leaving editor does not update disposed state', (
    tester,
  ) async {
    final profile =
        _Profile()..pendingLoad = Completer<Map<String, dynamic>?>();
    await _openEditor(tester, profile);
    await tester.tap(find.byTooltip('Cancel editing'));
    await tester.pumpAndSettle();
    profile.pendingLoad!.complete(profile.data);
    await tester.pumpAndSettle();
    expect(find.text('Original Profile tab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-time setup keeps its title and rejects whitespace names', (
    tester,
  ) async {
    final profile =
        _Profile()..data = {'id': 'new-person', 'full_name': '', 'bio': ''};
    await _openEditor(tester, profile, requiredSetup: true);
    expect(find.text('Complete Your Profile'), findsOneWidget);
    expect(find.byTooltip('Cancel editing'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '   ');
    await _save(tester);
    await tester.pumpAndSettle();
    expect(find.text('Please enter your full name'), findsOneWidget);
    expect(profile.writes, isEmpty);
  });
}
