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
  double height = 844,
  double scale = 1,
  double keyboard = 0,
  double topInset = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
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
    test('scallop matches the comp: ~50dp arches, broad tops, sharp cusps '
        'at $width', () {
      // The comp's edge, traced column by column: arches ~50dp wide rising
      // 7.3dp, meeting at sharp cusps. Probes come from the clipper's own
      // constants, so retuning it cannot silently flatten or invert it.
      const height = ChumbucketSheetWave.height;
      final path = DetailedWaveClipper().getClip(Size(width, height));
      final arches = DetailedWaveClipper.archesFor(width);
      final span = width / arches;
      const apex = DetailedWaveClipper.topInset;
      const cusp = DetailedWaveClipper.cuspY;

      // Arches are comp-sized: ~50dp, never a ripple, never a single bump.
      expect(span, inInclusiveRange(44, 60));

      // Apex: white reaches up to the top inset and no further.
      expect(path.contains(Offset(span / 2, apex + 1)), isTrue);
      expect(path.contains(Offset(span / 2, apex - .8)), isFalse);

      // Cusp: the pink comes down to a point between two arches.
      expect(path.contains(Offset(span, cusp - 1.5)), isFalse);
      expect(path.contains(Offset(span, cusp + .8)), isTrue);

      // Broad tops: a quarter of the way across, the edge is already 75% of
      // the way up (a sine would be at 50%). This is what makes it a scallop.
      const quarter = cusp - DetailedWaveClipper.archHeight * .75;
      expect(path.contains(Offset(span / 4, quarter + 1)), isTrue);
      expect(path.contains(Offset(span / 4, quarter - 1)), isFalse);

      // Rise: 8.2dp, calibrated so the same pixel test reads this clipper and
      // the comp alike (~7.9dp on both).
      expect(cusp - apex, closeTo(8.2, .01));

      // No wedge at the left edge; one closed outline.
      expect(path.contains(const Offset(.01, 1)), isFalse);
      expect(path.computeMetrics().single.isClosed, isTrue);
    });
  }

  for (final (width, scale, keyboard) in [
    (390.0, 1.0, 0.0),
    (320.0, 2.0, 0.0),
    (320.0, 2.0, 300.0),
  ]) {
    testWidgets(
      'shell fits $width/$scale/keyboard=$keyboard, no close button',
      (tester) async {
        await mountSheetSystem(
          tester,
          ChumbucketWavySheet(
            title: 'A longer sheet heading',
            subtitle: 'Keep the existing account and history',
            body: ListView(
              shrinkWrap: true,
              children: List.generate(20, (i) => Text('Row $i')),
            ),
          ),
          width: width,
          scale: scale,
          keyboard: keyboard,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ChumbucketSheetWave), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
        final title = tester.widget<Text>(find.text('A longer sheet heading'));
        // The header sits on the pink gradient, so its type is WHITE. This
        // previously pinned the ink-coloured `sheetTitle`, which is what made
        // the modularised sheet render dark text on #FF3355. Assert the colour
        // outright so the regression cannot come back through a style rename.
        expect(title.style, AppTextStyles.sheetTitleOnBrand);
        expect(title.style?.color, const Color(0xFFFFFFFF));
        expect(title.textAlign, TextAlign.center);
        expect(title.maxLines, isNull);
        expect(title.overflow, isNull);
        final body = tester.getRect(find.byType(ListView));
        expect(body.height, greaterThan(0));
        expect(body.bottom, lessThanOrEqualTo(844 - keyboard - 14));
        // The handle's touch target (and screen-reader Close) is 48dp+.
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('chumbucket-sheet-close-target')),
              )
              .shortestSide,
          greaterThanOrEqualTo(48),
        );
      },
    );
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

  // The comp has no close button. A sheet closes by dragging its header down,
  // tapping the handle, tapping the backdrop, or system Back — and a busy
  // sheet refuses every one of them.
  for (final busy in [false, true]) {
    testWidgets('no close button; every dismissal path respects busy=$busy', (
      tester,
    ) async {
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
                            body: const SizedBox(
                              height: 240,
                              child: Center(child: Text('Content')),
                            ),
                          ),
                    ),
                child: const Text('Open'),
              ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Modal title'), findsOneWidget);
      }

      void expectOpen(bool open) => expect(
        find.text('Modal title'),
        open ? findsOneWidget : findsNothing,
      );

      await open();
      // No visible close affordance anywhere in the header.
      expect(find.byTooltip('Close'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChumbucketSheetHeader),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      // Tapping content never dismisses.
      await tester.tap(find.text('Content'));
      await tester.pumpAndSettle();
      expectOpen(true);

      // 1. Drag the header down.
      final surface = find.byKey(const ValueKey('chumbucket-sheet-surface'));
      final restingTop = tester.getTopLeft(surface).dy;
      await tester.drag(
        find.byKey(const ValueKey('chumbucket-sheet-drag-region')),
        const Offset(0, 320),
      );
      await tester.pumpAndSettle();
      expectOpen(busy);
      if (busy) {
        // Locked, not broken: it gave a little and settled back.
        expect(tester.getTopLeft(surface).dy, closeTo(restingTop, .5));
      } else {
        await open();
      }

      // 2. Tap the handle.
      await tester.tap(
        find.byKey(const ValueKey('chumbucket-sheet-close-target')),
      );
      await tester.pumpAndSettle();
      expectOpen(busy);
      if (!busy) await open();

      // 3. Tap the backdrop.
      await tester.tapAt(const Offset(195, 30));
      await tester.pumpAndSettle();
      expectOpen(busy);
      if (!busy) await open();

      // 4. System Back.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectOpen(busy);
    });
  }

  testWidgets('a short header drag springs back instead of closing', (
    tester,
  ) async {
    await mountSheetSystem(
      tester,
      ChumbucketWavySheet(
        title: 'Modal title',
        body: const SizedBox(height: 240),
      ),
    );
    final surface = find.byKey(const ValueKey('chumbucket-sheet-surface'));
    final restingTop = tester.getTopLeft(surface).dy;
    await tester.timedDrag(
      find.byKey(const ValueKey('chumbucket-sheet-drag-region')),
      const Offset(0, 30),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Modal title'), findsOneWidget);
    expect(tester.getTopLeft(surface).dy, closeTo(restingTop, .5));
  });

  testWidgets(
    'market rows and call cards set questions in their named roles',
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
      // A catalog row is a list of many questions (the prototype's 16/800); a
      // call card leads with one (18/800).
      expect(questions[0].style, AppTextStyles.marketRowQuestion);
      expect(questions[1].style, AppTextStyles.questionTitle);
    },
  );

  for (final scene in sheetScenes().entries) {
    for (final (width, scale, keyboard) in [
      (390.0, 1.0, 0.0),
      (320.0, 2.0, 0.0),
      (320.0, 2.0, 300.0),
    ]) {
      testWidgets(
        '${scene.key} uses the shared shell at $width/$scale/$keyboard',
        (tester) async {
          await mountSheetSystem(
            tester,
            scene.value(),
            width: width,
            scale: scale,
            keyboard: keyboard,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(ChumbucketWavySheet), findsOneWidget);
          expect(find.byType(ChumbucketSheetWave), findsOneWidget);
          // The comp has no close button; the handle target closes.
          expect(find.byTooltip('Close'), findsNothing);
          expect(
            find.byKey(const ValueKey('chumbucket-sheet-close-target')),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
