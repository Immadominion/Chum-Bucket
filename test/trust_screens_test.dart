// The trust screens against a fake repository: no network, no session.
//
//   - Delete account: nothing happens until DELETE is typed; success shows a
//     confirmation and signs out only when the person taps Done.
//   - Report / mute / block from a call.
//   - The funded-trading attestation: all three boxes, then recorded.
//   - Settings → Privacy & data: the analytics switch is off by default.
//   - Settings → History keeps the escrow route.
import 'package:chumbucket/core/analytics/analytics_consent.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:chumbucket/features/trust/presentation/delete_account_screen.dart';
import 'package:chumbucket/features/trust/presentation/funded_trading_attestation_sheet.dart';
import 'package:chumbucket/features/trust/presentation/legacy_history_screen.dart';
import 'package:chumbucket/features/trust/presentation/privacy_data_screen.dart';
import 'package:chumbucket/features/trust/presentation/safety_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'packet_g_fixtures.dart' show usePhoneSurface;
import 'trust_fakes.dart';

Widget host(Widget child, {TrustRepository? repo}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, _) => Provider<TrustRepository?>.value(
        value: repo,
        child: MaterialApp(theme: AppTheme.lightTheme, home: child),
      ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Delete account', () {
    testWidgets('needs DELETE typed, then confirms and signs out on Done', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = FakeTrust();
      var signedOut = 0;
      await tester.pumpWidget(
        host(
          DeleteAccountScreen(
            repository: repo,
            onDeleted: (_) async => signedOut++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This permanently deletes your account'),
        findsOneWidget,
      );
      expect(find.textContaining('Deleted account'), findsOneWidget);

      final button = find.widgetWithText(FilledButton, 'Delete my account');
      await tester.dragUntilVisible(
        button,
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.text('Your account has been deleted'), findsOneWidget);
      expect(signedOut, 0);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });

    testWidgets('a refusal is shown and nothing is signed out', (tester) async {
      usePhoneSurface(tester);
      final repo =
          FakeTrust()
            ..deleteError = const CallsFailure(
              "Your profile has been removed, but we couldn't finish removing your sign-in. Try again in a moment. It's safe to retry.",
            );
      var signedOut = 0;
      await tester.pumpWidget(
        host(
          DeleteAccountScreen(
            repository: repo,
            onDeleted: (_) async => signedOut++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Delete my account');
      await tester.dragUntilVisible(
        button,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining("It's safe to retry"), findsOneWidget);
      expect(signedOut, 0);
    });

    testWidgets('without a session it asks to sign in first', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(host(const DeleteAccountScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(
        find.text("Can't sign in? Request deletion on the web"),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('Report, mute, block', () {
    const target = SafetyTarget(
      personId: 'u-bob',
      handle: 'bob',
      displayName: 'Bob',
      callId: 'call-1',
      hasThesis: true,
    );

    testWidgets('reporting a thesis sends the call and the reason', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = FakeTrust();
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder:
                                (_) => SafetyActionsSheet(
                                  target: target,
                                  repository: repo,
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Report this call'), findsOneWidget);
      expect(find.text('Report the thesis'), findsOneWidget);
      expect(find.text('Report @bob'), findsOneWidget);

      await tester.tap(find.text('Report the thesis'));
      await tester.pumpAndSettle();
      expect(find.text('Report this thesis'), findsOneWidget);
      final send = find.text('Send report');
      await tester.ensureVisible(find.text('Hate'));
      await tester.tap(find.text('Hate'));
      await tester.pump();
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(repo.reports.single, {
        'subject': ReportSubject.thesis,
        'reason': ReportReason.hate,
        'callId': 'call-1',
        'personRef': null,
        'details': '',
      });
      expect(find.textContaining("We'll review this thesis"), findsOneWidget);
    });

    testWidgets('mute is immediate; block asks first', (tester) async {
      usePhoneSurface(tester);
      final repo = FakeTrust();
      Future<void> open(WidgetTester tester) async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder:
                                (_) => SafetyActionsSheet(
                                  target: target,
                                  repository: repo,
                                ),
                          ),
                      child: const Text('open'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await open(tester);
      await tester.tap(find.text('Mute @bob'));
      await tester.pumpAndSettle();
      expect(repo.muted, {'u-bob'});

      await open(tester);
      expect(find.text('Unmute @bob'), findsOneWidget);
      await tester.tap(find.text('Block @bob'));
      await tester.pumpAndSettle();
      expect(find.text('Block @bob?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.blocked, isEmpty);
      await tester.tap(find.text('Block @bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Block'));
      await tester.pumpAndSettle();
      expect(repo.blocked, {'u-bob'});
    });
  });

  group('Funded-trading attestation', () {
    testWidgets('needs all three confirmations, then records them', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = FakeTrust();
      bool? result;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: TextButton(
                      onPressed:
                          () async =>
                              result = await ensureFundedTradingAttestation(
                                context,
                                repository: repo,
                              ),
                      child: const Text('fund'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('fund'));
      await tester.pumpAndSettle();
      expect(find.text('Before your first funded trade'), findsOneWidget);

      final confirm = find.text('Confirm and continue');
      final boxes = find.byType(CheckboxListTile);
      expect(boxes, findsNWidgets(3));
      await tester.tap(boxes.at(0));
      await tester.tap(boxes.at(1));
      await tester.pump();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(repo.accepts, 0);

      await tester.ensureVisible(boxes.at(2));
      await tester.tap(boxes.at(2));
      await tester.pump();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.accepts, 1);
      expect(result, isTrue);

      // On record: the next funded trade goes straight through.
      result = null;
      await tester.tap(find.text('fund'));
      await tester.pumpAndSettle();
      expect(find.text('Before your first funded trade'), findsNothing);
      expect(result, isTrue);
    });
  });

  group('Settings', () {
    testWidgets('Privacy & data: analytics are off until switched on', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final consent = AnalyticsConsent();
      final opened = <Uri>[];
      await tester.pumpWidget(
        host(
          PrivacyDataScreen(
            consent: consent,
            opener: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(consent.granted, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AnalyticsConsent.storageKey,
        ),
        isTrue,
      );

      await tester.tap(find.text('Terms of Service'));
      await tester.pump();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();
      expect(opened, [LegalLinks.terms, LegalLinks.privacy]);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Export my data'), findsOneWidget);
      expect(find.text('Blocked and muted'), findsOneWidget);
    });

    testWidgets('History keeps the escrow route and Arena', (tester) async {
      usePhoneSurface(tester);
      var escrow = 0;
      await tester.pumpWidget(
        host(LegacyHistoryScreen(onOpenEscrowChallenges: () => escrow++)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Arena predictions'), findsOneWidget);
      expect(find.text('Earlier notices'), findsOneWidget);
      await tester.tap(find.text('Escrow challenges'));
      expect(escrow, 1);
    });
  });

  test('legal links and the store listing', () {
    expect(LegalLinks.terms.toString(), 'https://chumbucket.fun/terms');
    expect(LegalLinks.privacy.toString(), 'https://chumbucket.fun/privacy');
    expect(
      LegalLinks.deletion.toString(),
      'https://chumbucket.fun/delete-account',
    );
    expect(
      storeListingCandidates(
        override: '',
        isAndroid: true,
      ).map((u) => u.toString()),
      // The dApp Store listing; the app is not on Google Play.
      ['solanadappstore://details?id=dev.cleva.chumbucket'],
    );
    expect(storeListingCandidates(override: '', isAndroid: false), isEmpty);
    expect(
      storeListingCandidates(
        override: 'https://example.store/chumbucket',
        isAndroid: true,
      ),
      [Uri.parse('https://example.store/chumbucket')],
    );
  });
}
