// Opt-in: renders Home's call cards with the content of Codex's layout
// prototype (docs/design/2026-09-30-chumbucket-layout, frame 01 / Home) so the
// two can be compared side by side.
//
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_FEED_REFERENCE=true \
//   test/ui_feed_reference_capture_test.dart
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui_market_layout_discovery_test.dart' show market, mount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_FEED_REFERENCE');

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final (family, paths) in [
      (
        'PPNeueMachina',
        [
          'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
          'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
        ],
      ),
      ('Montserrat_regular', ['assets/fonts/Montserrat/Montserrat-Regular.ttf']),
      ('Montserrat_500', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  CallFeedEntry entry({
    required String id,
    required String name,
    required int avatar,
    required Side side,
    required String question,
    required String thesis,
    required String yes,
    required String no,
    required Duration ago,
  }) {
    final now = DateTime.now();
    final venueMarket = market(
      'market-$id',
      const Duration(hours: 40),
      question: question,
    );
    return CallFeedEntry(
      call: Call(
        id: id,
        userId: 'user-$id',
        marketId: venueMarket.id,
        side: side,
        confidence: null,
        thesis: thesis,
        entryProbability: null,
        snapshotId: null,
        entryPrice: SharePriceSnapshot(
          id: 'price-$id',
          marketId: venueMarket.id,
          yesPrice: yes,
          noPrice: no,
          observedAt: now.subtract(ago).millisecondsSinceEpoch,
        ),
        visibility: CallVisibility.public,
        createdAt: now.subtract(ago).millisecondsSinceEpoch,
        lockedAt: now.subtract(ago).millisecondsSinceEpoch,
        parentCallId: null,
        fundingState: FundingState.none,
      ),
      author: Person(
        id: 'user-$id',
        handle: name.toLowerCase(),
        displayName: name,
        avatarUrl: 'assets/images/ai_gen/profile_images/$avatar.png',
      ),
      market: venueMarket,
    );
  }

  testWidgets('home call cards with the prototype content', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cards = [
      entry(
        id: 'nia',
        name: 'Nia',
        avatar: 2,
        side: Side.yes,
        question: r'Will BTC close above $90,000 on Friday?',
        thesis:
            'Everyone’s watching the breakout. I’m watching whether it holds '
            'into the close.',
        yes: '0.580000000000000001',
        no: '0.43',
        ago: const Duration(minutes: 12),
      ),
      entry(
        id: 'tobi',
        name: 'Tobi',
        avatar: 3,
        side: Side.no,
        question: r'Will ETH close above $3,000 on Sunday?',
        thesis: 'Funding is too hot for this to hold.',
        yes: '0.57',
        no: '0.48',
        ago: const Duration(minutes: 28),
      ),
    ];
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('feed-capture'),
                  child: ColoredBox(
                    color: const Color(0xFFF4F4F4),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final card in cards) ...[
                          CallCard(entry: card, onBack: () {}, onFade: () {}),
                          const SizedBox(height: 13),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 2; i <= 3; i++) {
        await precacheImage(
          AssetImage('assets/images/ai_gen/profile_images/$i.png'),
          tester.element(find.byType(ListView)),
        );
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('feed-capture')),
      matchesGoldenFile(Uri.file('/tmp/chum-feed-400.png')),
    );
  }, skip: !enabled);

  testWidgets('call detail with the prototype content', (tester) async {
    final nia = entry(
      id: 'nia',
      name: 'Nia',
      avatar: 2,
      side: Side.yes,
      question: r'Will BTC close above $90,000 on Friday?',
      thesis:
          'Everyone’s watching the breakout. I’m watching whether it holds '
          'into the close.\n\nA wick through \$90k isn’t enough. My call is on '
          'the closing price.',
      yes: '0.580000000000000001',
      no: '0.43',
      ago: const Duration(minutes: 12),
    );
    final provider = CallsProvider(repository: _OneCall(nia));
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      RepaintBoundary(
        key: const ValueKey('call-capture'),
        child: CallDetailScreen(callId: nia.call.id),
      ),
      width: 400,
    );
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/ai_gen/profile_images/2.png'),
        tester.element(find.byType(CallDetailScreen)),
      );
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('call-capture')),
      matchesGoldenFile(Uri.file('/tmp/chum-call-400.png')),
    );
  }, skip: !enabled);
}

class _OneCall extends MockCallsRepository {
  _OneCall(this.entry);
  final CallFeedEntry entry;

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async => CallDetail(entry: entry);
}
