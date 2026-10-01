import 'dart:io';

import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/challenges/presentation/screens/widgets/receipt_modal.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/send_sol_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/settings_bottom_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_challenge_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/widgets/profile_picture_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';

import 'packet_g_fixtures.dart' show testEntry;
import 'ui_people_layout_continuity_test.dart' show ConnectedWallet;

class MissingAddressWallet extends ConnectedWallet {
  @override
  String? get walletAddress => null;
}

Future<void> mountSheetSystem(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
  double keyboard = 0,
  double topInset = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final wallet = ConnectedWallet();
  addTearDown(wallet.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, _) => MaterialApp(
            theme: AppTheme.lightTheme,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: keyboard),
                    viewPadding: EdgeInsets.only(top: topInset),
                    padding: EdgeInsets.only(top: topInset),
                  ),
                  child: child!,
                ),
            home: ChangeNotifierProvider<MwaWalletProvider>.value(
              value: wallet,
              child: Scaffold(resizeToAvoidBottomInset: false, body: child),
            ),
          ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Widget Function()> sheetScenes() => {
  'account': () => const ProfileSettingsSheet(),
  'settings': () => const SettingsBottomSheet(),
  'wallet': () => const WalletModal(),
  'send': () => const SendSolSheet(),
  'export-warning': () => const WalletExportWarningSheet(),
  'wallet-address':
      () => const WalletCopySheet(
        walletAddress: '11111111111111111111111111111111',
      ),
  'export-unavailable': () => const WalletExportNotAvailableSheet(),
  'avatar': () => const ProfilePictureSelectionModal(),
  'friends':
      () => ViewMoreFriendsSheet(
        friends: const [
          {'name': 'Ada', 'address': '11111111111111111111111111111111'},
        ],
        onFriendSelected: (_) {},
      ),
  'resolve':
      () => ResolveChallengeSheet(
        challenge: const {
          'friendName': 'Ada',
          'title': 'A long existing challenge description remains readable',
          'amount': .05,
          'status': 'pending',
          'isCurrentUserWitness': true,
        },
        onMarkCompleted: (_, _) {},
      ),
  'receipt':
      () => ReceiptModal(
        challenge: Challenge(
          id: 'synthetic-challenge',
          creatorId: 'synthetic-person',
          title: 'A recorded challenge',
          description:
              'The full challenge description remains readable at larger text sizes.',
          amount: .05,
          platformFee: 0,
          winnerAmount: .05,
          createdAt: DateTime.utc(2026, 9, 30),
          expiresAt: DateTime.utc(2026, 10, 2),
        ),
        status: ChallengeStatus.pending,
        screenshotController: ScreenshotController(),
      ),
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('every app modal uses the common presentation entry point', () {
    final bypasses =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('/chumbucket_wavy_sheet.dart'))
            .where(
              (f) => RegExp(
                r'\b(showModalBottomSheet|showBottomSheet|DraggableScrollableSheet)\s*[<(]',
              ).hasMatch(f.readAsStringSync()),
            )
            .map((f) => f.path)
            .toList();
    expect(bypasses, isEmpty);
  });

  for (final missingAddress in [false, true]) {
    testWidgets(
      'wallet route preserves originating provider (missing=$missingAddress)',
      (tester) async {
        final wallet =
            missingAddress ? MissingAddressWallet() : ConnectedWallet();
        addTearDown(wallet.dispose);
        await mountSheetSystem(
          tester,
          ChangeNotifierProvider<MwaWalletProvider>.value(
            value: wallet,
            child: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () => showWalletModal(context),
                    child: const Text('Open wallet'),
                  ),
            ),
          ),
        );
        await tester.tap(find.text('Open wallet'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.element(find.byType(WalletModal)).read<MwaWalletProvider>(),
          same(wallet),
        );
        expect(wallet.refreshes, 1);
      },
    );
  }

  for (final width in [296.0, 366.0, 406.0]) {
    test(
      'scallop has visible alternating crests and no left wedge at $width',
      () {
        final path = DetailedWaveClipper().getClip(Size(width, 24));
        final segment = width / (width / 36).round().clamp(6, 16);
        expect(path.contains(Offset(segment / 2, 11)), isTrue);
        expect(path.contains(Offset(segment * 1.5, 20)), isFalse);
        expect(path.contains(Offset(segment * 1.5, 23)), isTrue);
        expect(path.contains(const Offset(.01, 1)), isFalse);
        expect(path.computeMetrics().single.isClosed, isTrue);
      },
    );
  }

  for (final (width, scale, keyboard) in [
    (390.0, 1.0, 0.0),
    (320.0, 2.0, 0.0),
    (320.0, 2.0, 300.0),
  ]) {
    testWidgets('shell fits $width/$scale/keyboard=$keyboard with one close', (
      tester,
    ) async {
      await mountSheetSystem(
        tester,
        ChumbucketWavySheet(
          title: 'A longer sheet heading',
          subtitle: 'Keep the existing account and history',
          body: ListView(children: List.generate(20, (i) => Text('Row $i'))),
        ),
        width: width,
        scale: scale,
        keyboard: keyboard,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ChumbucketSheetWave), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      final title = tester.widget<Text>(find.text('A longer sheet heading'));
      expect(title.style, AppTextStyles.sheetTitle);
      expect(title.maxLines, isNull);
      expect(title.overflow, isNull);
      final body = tester.getRect(find.byType(ListView));
      expect(body.height, greaterThan(0));
      expect(body.bottom, lessThanOrEqualTo(844 - keyboard - 14));
      expect(
        tester.getSize(find.byTooltip('Close')).shortestSide,
        greaterThanOrEqualTo(48),
      );
    });
  }

  testWidgets(
    'modal route preserves status-bar clearance with the keyboard open',
    (tester) async {
      await mountSheetSystem(
        tester,
        Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showChumbucketWavySheet<void>(
                      context: context,
                      builder:
                          (_) => const ChumbucketWavySheet(
                            title: 'Keyboard sheet',
                            body: Text('Form'),
                          ),
                    ),
                child: const Text('Open'),
              ),
        ),
        keyboard: 300,
        topInset: 24,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(ChumbucketSheetHeader)).dy,
        greaterThanOrEqualTo(36),
      );
      expect(
        tester.getBottomLeft(find.text('Form')).dy,
        lessThanOrEqualTo(530),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final busy in [false, true]) {
    testWidgets('shared route dismissal respects busy=$busy', (tester) async {
      await mountSheetSystem(
        tester,
        Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showChumbucketWavySheet<void>(
                      context: context,
                      builder:
                          (_) => ChumbucketWavySheet(
                            title: 'Modal title',
                            canDismiss: !busy,
                            body: const Text('Content'),
                          ),
                    ),
                child: const Text('Open'),
              ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final close = tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Close'),
      );
      expect(close.onPressed == null, busy);
      await tester.tap(find.text('Content'));
      await tester.pumpAndSettle();
      expect(find.text('Modal title'), findsOneWidget);
      if (busy) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Modal title'), findsOneWidget);
        await tester.tapAt(const Offset(195, 30));
        await tester.pumpAndSettle();
        expect(find.text('Modal title'), findsOneWidget);
      } else {
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Modal title'), findsNothing);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(195, 30));
        await tester.pumpAndSettle();
        expect(find.text('Modal title'), findsNothing);
      }
    });
  }

  testWidgets(
    'market and prediction questions share an exact typographic role',
    (tester) async {
      final entry = testEntry(
        id: 'style-fixture',
        outcome: CallOutcome.pending,
      );
      await mountSheetSystem(
        tester,
        ListView(
          children: [
            CallMarketCard(market: entry.market, onTap: () {}),
            CallCard(entry: entry),
          ],
        ),
      );
      final questions =
          tester.widgetList<Text>(find.text(entry.market.question)).toList();
      expect(questions, hasLength(2));
      for (final question in questions) {
        expect(question.style, AppTextStyles.questionTitle);
      }
    },
  );

  for (final scene in sheetScenes().entries) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
      testWidgets('${scene.key} uses the shared shell at $width/$scale', (
        tester,
      ) async {
        await mountSheetSystem(
          tester,
          scene.value(),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ChumbucketWavySheet), findsOneWidget);
        expect(find.byType(ChumbucketSheetWave), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
