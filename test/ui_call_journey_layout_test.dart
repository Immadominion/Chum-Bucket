import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

const viewer = MockCallsRepository.demoViewerUserId;
const captureWidgets = bool.fromEnvironment('UI_CALL_JOURNEY_CAPTURE');
Directory? captures;
final captureKey = GlobalKey();

void surface(WidgetTester tester, {double width = 390}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget host(CallsProvider provider, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => RepaintBoundary(
              key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: 'Montserrat',
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: AppColors.primary,
                  ),
                  scaffoldBackgroundColor: AppColors.background,
                ),
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: Scaffold(body: child),
              ),
            ),
      ),
    );

CallsProvider providerFor(MockCallsRepository repo) {
  final provider = CallsProvider(repository: repo)..setViewer(viewer);
  addTearDown(provider.dispose);
  return provider;
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

// Optional review artifacts, written only to a temporary test directory.
// flutter test --no-pub --dart-define=UI_CALL_JOURNEY_CAPTURE=true test/ui_call_journey_layout_test.dart
Future<void> capture(WidgetTester tester, String name) async {
  if (!captureWidgets) return;
  await tester.runAsync(() async {
    captures ??= await Directory.systemTemp.createTemp('ui_call_journey_');
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${captures!.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    // Printed paths make the artifacts reviewable without adding golden files.
    debugPrint('UI_CALL_JOURNEY_CAPTURE ${captures!.path}/$name.png');
  });
}

class PausedResponseRepository extends MockCallsRepository {
  final release = Completer<void>();
  int writes = 0;
  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async {
    writes++;
    await release.future;
    return super.respondToCall(input: input, viewerUserId: viewerUserId);
  }
}

void main() {
  setUpAll(() async {
    await GoogleFonts.pendingFonts([callJourneyBody()]);
    await (FontLoader('PPNeueMachina')..addFont(
      rootBundle.load('assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf'),
    )).load();
    await (FontLoader('Montserrat')..addFont(
      rootBundle.load('assets/fonts/Montserrat/Montserrat-Regular.ttf'),
    )).load();
  });

  for (final size in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('detail, review and receipt fit ${size.$1}dp at ${size.$2}x', (
      tester,
    ) async {
      surface(tester, width: size.$1);
      final repo = MockCallsRepository();
      final provider = providerFor(repo);
      final entry =
          (await repo.fetchCall(
            callId: 'call_ada_btc',
            viewerUserId: viewer,
          )).entry;
      final receiptEntry =
          (await repo.fetchCall(
            callId: 'call_you_fed',
            viewerUserId: viewer,
          )).entry;
      final receipt = CallReceipt.fromEntry(
        receiptEntry,
        shareUrl: repo.shareLinkForCall(receiptEntry.call.id),
      );
      final screens = <String, Widget>{
        'detail': const CallDetailScreen(callId: 'call_ada_btc'),
        'composer': CallComposerSheet(
          market: entry.market,
          initialSide: Side.yes,
        ),
        'response': CallResponseSheet(
          entry: entry,
          initialKind: CallResponseKind.fade,
        ),
        'receipt': CallReceiptSheet(receipt: receipt, entry: receiptEntry),
      };
      for (final screen in screens.entries) {
        await tester.pumpWidget(host(provider, screen.value, scale: size.$2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: screen.key);
        await capture(
          tester,
          '${screen.key}_${size.$1.toInt()}_${size.$2.toInt()}x',
        );
        for (final button in tester.widgetList<TextButton>(
          find.byType(TextButton),
        )) {
          final minSize = button.style?.minimumSize?.resolve({});
          if (minSize != null) expect(minSize.height, greaterThanOrEqualTo(48));
        }
        if (screen.key == 'composer' || screen.key == 'response') {
          await reveal(tester, find.byType(CallJourneyReason));
          await tester.tap(find.byType(TextField));
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.key} keyboard',
          );
          tester.view.resetViewInsets();
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
    'Fade preselects NO without writing; switching YES updates relationship',
    (tester) async {
      surface(tester);
      final repo = MockCallsRepository();
      final provider = providerFor(repo);
      final entry =
          (await repo.fetchCall(
            callId: 'call_ada_btc',
            viewerUserId: viewer,
          )).entry;
      final before = repo.debugCalls.length;
      await tester.pumpWidget(
        host(
          provider,
          CallResponseSheet(entry: entry, initialKind: CallResponseKind.fade),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.debugCalls.length, before);
      expect(find.text('Lock my NO call'), findsOneWidget);
      expect(find.text('Fading @ada · You’re calling NO.'), findsOneWidget);
      await reveal(tester, find.text('YES'));
      await tester.tap(find.text('YES'));
      await tester.pumpAndSettle();
      expect(find.text('Backing @ada · You’re calling YES.'), findsOneWidget);
      expect(find.text('Lock my YES call'), findsOneWidget);
      expect(repo.debugCalls.length, before);
    },
  );

  testWidgets(
    'response returns own immutable call, preserves visibility and prevents duplicate submit',
    (tester) async {
      surface(tester);
      final repo = PausedResponseRepository();
      final provider = providerFor(repo);
      final entry =
          (await repo.fetchCall(
            callId: 'call_ada_btc',
            viewerUserId: viewer,
          )).entry;
      CallResponseResult? result;
      await tester.pumpWidget(
        host(
          provider,
          Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    result = await showCallResponseSheet(
                      context: context,
                      entry: entry,
                      initialKind: CallResponseKind.fade,
                    );
                  },
                  child: const Text('Open review'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'My independent reason');
      await reveal(tester, find.text('Followers only'));
      await tester.tap(find.text('Followers only'));
      await tester.tap(find.text('Lock my NO call'));
      await tester.pump();
      expect(repo.writes, 1);
      expect(result, isNull);
      await tester.tap(find.text('Please wait…'));
      await tester.pump();
      expect(repo.writes, 1);
      repo.release.complete();
      await tester.pumpAndSettle();
      expect(result!.resultingCall!.call.side, Side.no);
      expect(result!.resultingCall!.call.userId, viewer);
      expect(result!.resultingCall!.call.parentCallId, entry.call.id);
      expect(result!.resultingCall!.call.thesis, 'My independent reason');
      expect(result!.resultingCall!.call.visibility, CallVisibility.followers);
      expect(result!.resultingCall!.call.fundingState, FundingState.none);
    },
  );

  testWidgets('recoverable errors and auth refresh retain response draft', (
    tester,
  ) async {
    surface(tester);
    final repo = MockCallsRepository();
    final provider = providerFor(repo);
    final entry =
        (await repo.fetchCall(
          callId: 'call_ada_btc',
          viewerUserId: viewer,
        )).entry;
    await tester.pumpWidget(host(provider, CallResponseSheet(entry: entry)));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Keep my reason');
    repo.simulateOffline = true;
    await tester.tap(find.text('Lock my YES call'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my reason',
    );
    provider.setViewer(null);
    await tester.pumpAndSettle();
    expect(find.byType(CallsSignedOutView), findsOneWidget);
    provider.setViewer(viewer);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my reason',
    );
  });

  testWidgets(
    'composer retains reason when Panta price is missing and never creates a call',
    (tester) async {
      surface(tester, width: 320);
      final repo = MockCallsRepository();
      final provider = providerFor(repo);
      final market = repo.debugMarkets
          .firstWhere((m) => m.status.acceptsNewCalls)
          .copyWith(venue: MarketVenue.panta);
      final before = repo.debugCalls.length;
      await tester.pumpWidget(
        host(
          provider,
          CallComposerSheet(market: market, initialSide: Side.yes),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.text('Lock my YES call'));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.text(
          'Panta prices are missing or stale. Refresh this market before calling.',
        ),
      );
      expect(repo.debugCalls.length, before);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this draft',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closed and already-called markets explain eligibility without writing',
    (tester) async {
      surface(tester);
      final repo = MockCallsRepository();
      final provider = providerFor(repo);
      final entry =
          (await repo.fetchCall(
            callId: 'call_ada_btc',
            viewerUserId: viewer,
          )).entry;
      await tester.pumpWidget(
        host(
          provider,
          CallResponseSheet(entry: entry.copyWith(viewerHasCalled: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You’re already on record for this market.'),
        findsOneWidget,
      );
      final lock = tester.widget<CallJourneyButton>(
        find.widgetWithText(CallJourneyButton, 'Lock my YES call'),
      );
      expect(lock.onPressed, isNull);
      final closed = repo.debugMarkets.firstWhere(
        (m) => !m.status.acceptsNewCalls,
      );
      await tester.pumpWidget(
        host(provider, CallComposerSheet(market: closed)),
      );
      await tester.pumpAndSettle();
      expect(find.text(closed.status.label), findsOneWidget);
      expect(find.text('Lock my call'), findsNothing);
    },
  );

  testWidgets('challenge returns invitation only', (tester) async {
    surface(tester);
    final repo = MockCallsRepository();
    final provider = providerFor(repo);
    final entry =
        (await repo.fetchCall(
          callId: 'call_ada_btc',
          viewerUserId: viewer,
        )).entry;
    CallResponseResult? result;
    final before = repo.debugCalls.length;
    await tester.pumpWidget(
      host(
        provider,
        Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  result = await showCallResponseSheet(
                    context: context,
                    entry: entry,
                    initialKind: CallResponseKind.challenge,
                  );
                },
                child: const Text('Open invitation'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Open invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send the dare'));
    await tester.pumpAndSettle();
    expect(result!.invitation, isNotNull);
    expect(result!.resultingCall, isNull);
    expect(repo.debugCalls.length, before);
  });

  testWidgets(
    'detail signed-out action keeps the original auth callback and destination',
    (tester) async {
      surface(tester);
      final repo = MockCallsRepository();
      final provider = providerFor(repo)..setViewer(null);
      var requested = 0;
      await tester.pumpWidget(
        host(
          provider,
          CallDetailScreen(
            callId: 'call_ada_btc',
            onSignInRequested: () => requested++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fade · NO'));
      await tester.pumpAndSettle();
      expect(requested, 1);
      expect(find.byType(CallDetailScreen), findsOneWidget);
      expect(find.text('Responses'), findsNothing);
    },
  );

  testWidgets(
    'followers link omits content; image requires an explicit disclosure decision',
    (tester) async {
      surface(tester);
      final repo = MockCallsRepository();
      final provider = providerFor(repo);
      final source =
          (await repo.fetchCall(
            callId: 'call_you_fed',
            viewerUserId: viewer,
          )).entry;
      final entry = CallFeedEntry(
        author: source.author,
        market: source.market,
        result: source.result,
        call: Call.fromJson({
          ...source.call.toJson(),
          'visibility': 'followers',
        }),
      );
      final receipt = CallReceipt.fromEntry(
        entry,
        shareUrl: repo.shareLinkForCall(entry.call.id),
      );
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      String? shared;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            shared = (call.arguments as Map)['text'] as String?;
            return 'dev.fluttercommunity.plus/share/success';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        host(provider, CallReceiptSheet(receipt: receipt, entry: entry)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share link'));
      await tester.pumpAndSettle();
      expect(shared, contains(receipt.shareUrl));
      expect(shared, contains('DEMO DATA'));
      expect(shared, isNot(contains(receipt.marketQuestion)));
      expect(shared, isNot(contains('@${receipt.personHandle}')));
      await tester.tap(find.text('Share image'));
      await tester.pumpAndSettle();
      expect(find.text('Share outside your followers?'), findsOneWidget);
      await tester.tap(find.text('Keep it private'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('all outcomes retain evidence, thesis and demo markings at 2x', (
    tester,
  ) async {
    surface(tester, width: 320);
    final repo = MockCallsRepository();
    final provider = providerFor(repo);
    for (final id in [
      'call_you_fed',
      'call_zed_fed',
      'call_kemi_listing',
      'call_ada_btc',
    ]) {
      final entry =
          (await repo.fetchCall(callId: id, viewerUserId: viewer)).entry;
      final receipt = CallReceipt.fromEntry(
        entry,
        shareUrl: repo.shareLinkForCall(id),
      );
      await tester.pumpWidget(
        host(
          provider,
          SingleChildScrollView(
            child: CallReceiptCard(receipt: receipt, entry: entry),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(receipt.lockedAt.toUtc().toIso8601String()),
        findsOneWidget,
      );
      expect(find.text(receipt.marketQuestion), findsOneWidget);
      expect(
        find.text('DEMO DATA — sample catalog, not a live market result.'),
        findsOneWidget,
      );
      if (entry.call.thesis?.isNotEmpty == true) {
        expect(find.text(entry.call.thesis!), findsOneWidget);
      }
      if (receipt.marketResolutionId != null) {
        expect(find.text(receipt.marketResolutionId!), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
}
