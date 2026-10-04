// Opt-in captures of the call screens (answer sheet, composer, call detail,
// feed cards) with the real fonts and seeded demo data, at 390dp and at
// 320dp with 2x text, for design review. Writes nothing unless asked:
//
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_CALLS_UX=/abs/output/dir \
//   test/ui_calls_ux_capture_test.dart
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'onboarding_fakes.dart' show loadBrandFonts;

const _outDir = String.fromEnvironment('CAPTURE_CALLS_UX');
const _viewer = MockCallsRepository.demoViewerUserId;

/// Refuses every answer the way the BFF refuses an answer to your own call.
class _RefusingRepository extends MockCallsRepository {
  _RefusingRepository(this.message);
  final String message;
  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async => throw CallsRejectedException(message);
}

/// A Panta market with a fresh price, as the BFF serves one.
class _PantaRepository extends MockCallsRepository {
  SharePriceSnapshot price(String marketId) => SharePriceSnapshot(
    id: 'price-$marketId',
    marketId: marketId,
    yesPrice: '0.36',
    noPrice: '0.66',
    observedAt: DateTime.now().millisecondsSinceEpoch,
  );

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    final detail = await super.fetchMarketDetail(
      marketId: marketId,
      viewerUserId: viewerUserId,
    );
    return MarketDetail(
      market: detail.market.copyWith(venue: MarketVenue.panta),
      snapshot: null,
      sharePrice: price(marketId),
      servedAt: detail.servedAt,
      viewerCall: detail.viewerCall,
      crowdSplit: detail.crowdSplit,
    );
  }
}

/// Your own call on a live Panta market (the detail shows its trade card).
class _PantaCallRepository extends _PantaRepository {
  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async {
    final detail = await super.fetchCall(
      callId: callId,
      viewerUserId: viewerUserId,
    );
    final entry = detail.entry;
    return CallDetail(
      entry: CallFeedEntry(
        call: entry.call,
        author: entry.author,
        market: entry.market.copyWith(
          venue: MarketVenue.panta,
          status: MarketStatus.open,
        ),
      ),
      parent: detail.parent,
      responses: detail.responses,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_outDir.isEmpty) return;
    await loadBrandFonts();
  });

  Future<void> mountScene(
    WidgetTester tester,
    CallsProvider provider,
    Widget child, {
    required double width,
    required double scale,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: Scaffold(
                  backgroundColor: const Color(0xFFF4F0EC),
                  body: RepaintBoundary(
                    key: const ValueKey('calls-ux-capture'),
                    child: child,
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: name);
    await expectLater(
      find.byKey(const ValueKey('calls-ux-capture')),
      matchesGoldenFile(Uri.file('$_outDir/calls-ux-$name.png')),
    );
  }

  Future<(CallsProvider, MockCallsRepository)> rig({
    MockCallsRepository? repository,
  }) async {
    final repo = repository ?? MockCallsRepository(latency: Duration.zero);
    final provider = CallsProvider(repository: repo)..setViewer(_viewer);
    addTearDown(provider.dispose);
    return (provider, repo);
  }

  Future<CallFeedEntry> entryOf(MockCallsRepository repo, String id) async =>
      (await repo.fetchCall(callId: id, viewerUserId: _viewer)).entry;

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    final size = '${width.toInt()}-${scale.toInt()}x';

    for (final kind in CallResponseKind.values) {
      testWidgets('answer ${kind.wire} $size', (tester) async {
        final (provider, repo) = await rig();
        final entry = await entryOf(repo, 'call_ada_btc');
        await mountScene(
          tester,
          provider,
          CallResponseSheet(entry: entry, initialKind: kind),
          width: width,
          scale: scale,
        );
        await shot(tester, 'answer-${kind.wire}-$size');
      }, skip: _outDir.isEmpty);
    }

    testWidgets('answer with a reason $size', (tester) async {
      final (provider, repo) = await rig();
      final entry = await entryOf(repo, 'call_ada_btc');
      await mountScene(
        tester,
        provider,
        CallResponseSheet(entry: entry, initialKind: CallResponseKind.fade),
        width: width,
        scale: scale,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('response-add-reason')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('response-add-reason')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Funding is too hot.');
      await tester.pumpAndSettle();
      await shot(tester, 'answer-reason-$size');
    }, skip: _outDir.isEmpty);

    testWidgets('answer refused $size', (tester) async {
      final (provider, repo) = await rig(
        repository: _RefusingRepository(
          'Panta prices are missing or stale. Refresh before locking your call.',
        ),
      );
      final entry = await entryOf(repo, 'call_ada_btc');
      await mountScene(
        tester,
        provider,
        CallResponseSheet(entry: entry, initialKind: CallResponseKind.fade),
        width: width,
        scale: scale,
      );
      await tester.tap(find.byKey(const ValueKey('response-lock')));
      await tester.pumpAndSettle();
      await shot(tester, 'answer-refused-$size');
    }, skip: _outDir.isEmpty);

    testWidgets('answer your own call $size', (tester) async {
      final (provider, repo) = await rig();
      final entry = await entryOf(repo, 'call_you_fed');
      await mountScene(
        tester,
        provider,
        CallResponseSheet(entry: entry, initialKind: CallResponseKind.back),
        width: width,
        scale: scale,
      );
      await shot(tester, 'answer-own-$size');
    }, skip: _outDir.isEmpty);

    testWidgets('answer on Panta $size', (tester) async {
      final (provider, repo) = await rig(repository: _PantaRepository());
      final entry = await entryOf(repo, 'call_ada_btc');
      await mountScene(
        tester,
        provider,
        CallResponseSheet(
          entry: CallFeedEntry(
            call: entry.call,
            author: entry.author,
            market: entry.market.copyWith(venue: MarketVenue.panta),
          ),
          initialKind: CallResponseKind.fade,
        ),
        width: width,
        scale: scale,
      );
      await shot(tester, 'answer-panta-$size');
    }, skip: _outDir.isEmpty);

    for (final compact in [false, true]) {
      testWidgets('composer on Panta${compact ? ' compact' : ''} $size', (
        tester,
      ) async {
        final panta = _PantaRepository();
        final (provider, repo) = await rig(repository: panta);
        final entry = await entryOf(repo, 'call_ada_btc');
        await mountScene(
          tester,
          provider,
          CallComposerSheet(
            market: entry.market.copyWith(venue: MarketVenue.panta),
            sharePrice: panta.price(entry.market.id),
            initialSide: Side.no,
            compact: compact,
          ),
          width: width,
          scale: scale,
        );
        await shot(tester, 'composer-panta${compact ? '-compact' : ''}-$size');
      }, skip: _outDir.isEmpty);
    }

    testWidgets('composer $size', (tester) async {
      final (provider, repo) = await rig();
      final entry = await entryOf(repo, 'call_ada_btc');
      await mountScene(
        tester,
        provider,
        CallComposerSheet(market: entry.market, initialSide: Side.yes),
        width: width,
        scale: scale,
      );
      await shot(tester, 'composer-$size');
      await tester.tap(find.byKey(const ValueKey('composer-more-options')));
      await tester.pumpAndSettle();
      await shot(tester, 'composer-more-$size');
    }, skip: _outDir.isEmpty);

    for (final id in ['call_ada_btc', 'call_you_fed']) {
      testWidgets('detail $id $size', (tester) async {
        final (provider, _) = await rig();
        await mountScene(
          tester,
          provider,
          CallDetailScreen(callId: id),
          width: width,
          scale: scale,
        );
        await shot(tester, 'detail-$id-$size');
      }, skip: _outDir.isEmpty);
    }

    testWidgets('detail own Panta call $size', (tester) async {
      final (provider, _) = await rig(repository: _PantaCallRepository());
      await mountScene(
        tester,
        provider,
        const CallDetailScreen(callId: 'call_you_fed'),
        width: width,
        scale: scale,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      await shot(tester, 'detail-own-panta-$size');
    }, skip: _outDir.isEmpty);

    testWidgets('feed cards $size', (tester) async {
      final (provider, repo) = await rig();
      final entries = [
        await entryOf(repo, 'call_ada_btc'),
        await entryOf(repo, 'call_you_fed'),
        await entryOf(repo, 'call_kemi_btc_fade'),
      ];
      await mountScene(
        tester,
        provider,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in entries) ...[
              CallCard(
                entry: entry,
                onOpenCall: () {},
                onBack: entry.author.id == _viewer ? null : () {},
                onFade: entry.author.id == _viewer ? null : () {},
                onShareReceipt: () {},
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
        width: width,
        scale: scale,
      );
      await shot(tester, 'feed-$size');
    }, skip: _outDir.isEmpty);
  }
}
