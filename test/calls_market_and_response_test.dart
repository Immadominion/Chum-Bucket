import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

void usePhoneSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget harness(CallsProvider provider, Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (context, _) => MaterialApp(
        home: ChangeNotifierProvider<CallsProvider>.value(
          value: provider,
          child: child,
        ),
      ),
);

/// Scrolls [target] into view inside the nearest scrollable. Sheets and the
/// market detail are lists, so anything below the fold is not built until it
/// is scrolled to.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(Scrollable).last,
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

CallsProvider providerFor(
  MockCallsRepository repo, {
  String? viewerUserId = viewer,
}) {
  final provider = CallsProvider(repository: repo);
  if (viewerUserId != null) provider.setViewer(viewerUserId);
  return provider;
}

void main() {
  group('market detail', () {
    testWidgets('shows the venue\'s exact rules text, unabridged', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final market = repo.debugMarkets.firstWhere(
        (m) => m.id == 'market_btc_150k',
      );

      await tester.pumpWidget(
        harness(
          providerFor(repo),
          const MarketDetailScreen(marketId: 'market_btc_150k'),
        ),
      );
      await tester.pumpAndSettle();

      final rules = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(rules.data, market.rulesText);
      expect(rules.data, contains('Wicks count.'));
      expect(
        find.text('Resolution source: ${market.resolutionSource}'),
        findsOneWidget,
      );
    });

    testWidgets('shows close time, data age, YES/NO price and venue', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        harness(
          providerFor(MockCallsRepository()),
          const MarketDetailScreen(marketId: 'market_btc_150k'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Closes in'), findsWidgets);
      expect(find.textContaining('Price 2m old'), findsOneWidget);
      expect(find.text('38%'), findsOneWidget); // YES
      expect(find.text('62%'), findsOneWidget); // NO
      expect(find.text('YES'), findsOneWidget);
      expect(find.text('NO'), findsOneWidget);
      expect(find.text('Priced by Jupiter'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('a stale price is flagged as stale', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        harness(
          providerFor(MockCallsRepository()),
          const MarketDetailScreen(marketId: 'market_sol_flip'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stale'), findsOneWidget);
      expect(find.textContaining('Price 5h old'), findsOneWidget);
    });

    testWidgets('a fixture market is labelled DEMO DATA', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        harness(
          providerFor(MockCallsRepository()),
          const MarketDetailScreen(marketId: 'market_sol_flip'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Demo catalog data. This is sample data, not a live market.'),
        findsOneWidget,
      );
      expect(find.text('Demo catalog · not a live market'), findsOneWidget);
    });

    testWidgets('a market with no price says so instead of inventing one', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        harness(
          providerFor(MockCallsRepository()),
          const MarketDetailScreen(marketId: 'market_paused_depeg'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No price published yet'), findsOneWidget);
      expect(find.text('Paused by venue'), findsOneWidget);
      // Paused takes no new calls, so no composer entry point.
      expect(find.text('Make my call'), findsNothing);
    });

    testWidgets('the five market statuses render as five distinct labels', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      for (final market in repo.debugMarkets) {
        final provider = providerFor(repo);
        await tester.pumpWidget(
          harness(
            provider,
            MarketDetailScreen(
              key: ValueKey(market.id),
              marketId: market.id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(market.status.label),
          findsWidgets,
          reason: market.id,
        );
      }
    });

    testWidgets('crowd split is hidden before the viewer locks a call', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        harness(
          providerFor(MockCallsRepository()),
          const MarketDetailScreen(marketId: 'market_btc_150k'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HOW EVERYONE ELSE CALLED IT'), findsNothing);
      expect(find.text('Make my call'), findsOneWidget);
    });

    testWidgets('crowd split appears once the viewer has locked', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final provider = providerFor(MockCallsRepository());
      await provider.createCall(
        const CreateCallInput(marketId: 'market_btc_150k', side: Side.yes),
      );

      await tester.pumpWidget(
        harness(provider, const MarketDetailScreen(marketId: 'market_btc_150k')),
      );
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('HOW EVERYONE ELSE CALLED IT'));

      expect(find.text('HOW EVERYONE ELSE CALLED IT'), findsOneWidget);
      expect(
        find.text('Shown now because your call is already locked.'),
        findsOneWidget,
      );
      // Already on record, so the composer entry point is gone.
      expect(find.text('Make my call'), findsNothing);
    });
  });

  group('composer', () {
    testWidgets('signed out shows the sign-in gate, not the form', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final market = repo.debugMarkets.first;

      await tester.pumpWidget(
        harness(
          providerFor(repo, viewerUserId: null),
          CallComposerSheet(market: market),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CallsSignedOutView), findsOneWidget);
      expect(find.text('Lock my call'), findsNothing);
    });

    testWidgets('signed in shows both sides, no amount field and no crowd data', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final market = repo.debugMarkets.firstWhere(
        (m) => m.id == 'market_btc_150k',
      );
      final detail = await repo.fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: viewer,
      );

      await tester.pumpWidget(
        harness(
          providerFor(repo),
          CallComposerSheet(market: market, snapshot: detail.snapshot),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yes — it prints 150k'), findsOneWidget);
      expect(find.text('No — it never gets there'), findsOneWidget);
      expect(find.text('Lock my call'), findsOneWidget);
      // The venue price IS shown — that is what the call gets stamped with.
      expect(find.textContaining('Venue price: Yes 38%'), findsOneWidget);
      // The crowd's split is not.
      expect(find.textContaining('EVERYONE ELSE'), findsNothing);

      await scrollTo(
        tester,
        find.textContaining('This is a free call. No money, no wallet'),
      );
      expect(
        find.textContaining('This is a free call. No money, no wallet'),
        findsOneWidget,
      );

      // Exactly one free-text field: the thesis. No amount input anywhere.
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.length, 1);
      expect(fields.first.maxLength, kThesisMaxLength);
      expect(fields.first.keyboardType, isNot(TextInputType.number));
    });

    testWidgets('a closed market refuses the composer with a clear reason', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final closed = repo.debugMarkets.firstWhere(
        (m) => m.status == MarketStatus.closedPendingResolution,
      );

      await tester.pumpWidget(
        harness(providerFor(repo), CallComposerSheet(market: closed)),
      );
      await tester.pumpAndSettle();

      expect(find.text(closed.status.label), findsWidgets);
      expect(find.text('Lock my call'), findsNothing);
    });
  });

  group('Back / Fade / Challenge sheet', () {
    Future<CallFeedEntry> target(MockCallsRepository repo) async {
      final detail = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );
      return detail.entry;
    }

    testWidgets('offers all three, and Back is not framed as copy-trading', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final entry = await target(repo);

      await tester.pumpWidget(
        harness(providerFor(repo), CallResponseSheet(entry: entry)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Fade'), findsOneWidget);
      expect(
        find.textContaining('Makes your OWN call on the same side'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not copy their position'),
        findsOneWidget,
      );
      // Back is preselected, and its button never says "copy".
      expect(find.text('Lock my call on the same side'), findsOneWidget);

      // The third option is below the fold on a small phone.
      await scrollTo(tester, find.text('Challenge'));
      expect(find.text('Challenge'), findsOneWidget);
    });

    testWidgets('Fade puts the responder on the opposite side', (tester) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final entry = await target(repo);

      await tester.pumpWidget(
        harness(providerFor(repo), CallResponseSheet(entry: entry)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fade'));
      await tester.pumpAndSettle();

      expect(find.text('Lock my call on the other side'), findsOneWidget);
      await scrollTo(tester, find.textContaining('You will be on record for'));
      expect(find.textContaining('You will be on record for'), findsOneWidget);
      // The target called YES, so a fade is NO.
      expect(entry.call.side, Side.yes);
      expect(find.text('No — it never gets there'), findsWidgets);
    });

    testWidgets('Challenge says explicitly that nothing is escrowed', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final entry = await target(repo);

      await tester.pumpWidget(
        harness(providerFor(repo), CallResponseSheet(entry: entry)),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Challenge'));
      await tester.tap(find.text('Challenge'));
      await tester.pumpAndSettle();

      expect(find.text('Send the challenge'), findsOneWidget);
      await scrollTo(
        tester,
        find.textContaining('No escrow. Nothing is locked up'),
      );
      expect(
        find.textContaining('No escrow. Nothing is locked up'),
        findsOneWidget,
      );
      expect(find.textContaining('no transaction is created'), findsOneWidget);
      // A challenge makes no call for the actor, so no side banner.
      expect(find.textContaining('You will be on record for'), findsNothing);
    });

    testWidgets('signed out shows the sign-in gate', (tester) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final entry = await target(repo);

      await tester.pumpWidget(
        harness(
          providerFor(repo, viewerUserId: null),
          CallResponseSheet(entry: entry),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CallsSignedOutView), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('nothing in the sheet mentions a stake or an amount', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final entry = await target(repo);

      await tester.pumpWidget(
        harness(providerFor(repo), CallResponseSheet(entry: entry)),
      );
      await tester.pumpAndSettle();

      final rendered =
          tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => (t.data ?? '').toLowerCase())
              .join(' | ');
      for (final forbidden in ['stake', 'usdc', 'amount', 'wager', 'deposit']) {
        expect(
          rendered.contains(forbidden),
          isFalse,
          reason: 'response sheet rendered "$forbidden"',
        );
      }
      // One free-text note field, and nothing numeric to type an amount into.
      await scrollTo(tester, find.byType(TextField));
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
