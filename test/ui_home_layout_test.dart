import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/chumbucket_bottom_navigation.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final font =
        FontLoader('PPNeueMachina')
          ..addFont(
            rootBundle.load(
              'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
            ),
          )
          ..addFont(
            rootBundle.load(
              'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
            ),
          );
    await font.load();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
    double width = 390,
    CallsProvider? calls,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              theme: AppTheme.lightTheme,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child:
                        calls == null
                            ? child!
                            : ChangeNotifierProvider<CallsProvider>.value(
                              value: calls,
                              child: child!,
                            ),
                  ),
              home: child,
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<CallFeedEntry> openEntry() async {
    final page = await MockCallsRepository().fetchFeed(
      mode: CallFeedMode.global,
      viewerUserId: MockCallsRepository.demoViewerUserId,
    );
    return page.entries.firstWhere(
      (entry) => entry.market.status.acceptsNewCalls,
    );
  }

  testWidgets('call card exposes separate Back and Fade, not crowd metrics', (
    tester,
  ) async {
    var backed = 0;
    var faded = 0;
    final entry = await openEntry();
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CallCard(
            entry: entry,
            onBack: () => backed++,
            onFade: () => faded++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Back'));
    await tester.tap(find.text('Fade'));
    expect(backed, 1);
    expect(faded, 1);
    final copy = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .join(' ');
    expect(copy, isNot(contains('people answered')));
    expect(copy, isNot(contains('accurate')));
    expect(copy, contains('Free call'));
    expect(copy, contains('DEMO DATA'));
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Back')).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('card remains readable at 320px and double text size', (
    tester,
  ) async {
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: CallCard(
            entry: await openEntry(),
            onBack: () {},
            onFade: () {},
          ),
        ),
      ),
      width: 320,
      scale: 2,
    );
    await tester.ensureVisible(find.text('Fade'));
    expect(find.text('Fade').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'four visible nav labels survive large text and preserve selection',
    (tester) async {
      var selected = 0;
      await mount(
        tester,
        Scaffold(
          bottomNavigationBar: ChumbucketBottomNavigation(
            selectedIndex: 0,
            onSelected: (value) => selected = value,
          ),
        ),
        width: 320,
        scale: 2,
      );
      for (final label in ['Home', 'Markets', 'Friends', 'Profile']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.bySemanticsLabel('Markets'));
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('header keeps identity and wallet actions off the feed', (
    tester,
  ) async {
    var opened = false;
    await mount(
      tester,
      Scaffold(
        body: ChumbucketAppHeader(
          title: 'Home',
          showAccountActions: false,
          onActivityTap: () => opened = true,
        ),
      ),
    );
    expect(find.byTooltip('Copy wallet address'), findsNothing);
    await tester.tap(find.byTooltip('Activity'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home visual checkpoint uses the real widgets and bundled fonts',
    (tester) async {
      final provider = CallsProvider(repository: _VisualCallsRepository());
      // Signed out: no invented personal receipt or unread activity indicator.
      addTearDown(provider.dispose);
      await mount(
        tester,
        ChangeNotifierProvider<CallsProvider>.value(
          value: provider,
          child: RepaintBoundary(
            key: const Key('ui-home-preview'),
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Stack(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ChumbucketAppHeader(
                          title: 'Home',
                          showAccountActions: false,
                          onActivityTap: () {},
                        ),
                      ),
                      const Expanded(child: CallFeedScreen(showHeader: false)),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ChumbucketBottomNavigation(
                      selectedIndex: 0,
                      onSelected: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(
          find.byKey(const Key('ui-home-preview')),
        );
        for (final number in [1, 2]) {
          await precacheImage(
            AssetImage('assets/images/ai_gen/profile_images/$number.png'),
            context,
          );
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('ui-home-preview')),
        matchesGoldenFile('goldens/ui_home.png'),
      );
    },
  );

  testWidgets(
    'Home Fade reviews the opposite side and opens the resulting own call',
    (tester) async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(MockCallsRepository.demoViewerUserId);
      addTearDown(provider.dispose);
      await mount(
        tester,
        const CallFeedScreen(showHeader: false),
        calls: provider,
      );
      final parent = provider.feed.first;
      await tester.ensureVisible(find.text('Fade').first);
      await tester.tap(find.text('Fade').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CallResponseSheet>(find.byType(CallResponseSheet))
            .initialKind,
        CallResponseKind.fade,
      );
      final side = parent.call.side == Side.yes ? Side.no : Side.yes;
      await tester.tap(find.text('Lock my ${side.wire} call'));
      await tester.pumpAndSettle();
      expect(find.byType(CallDetailScreen), findsOneWidget);
      final screen = tester.widget<CallDetailScreen>(
        find.byType(CallDetailScreen),
      );
      final created = provider.callDetail(screen.callId)!.entry.call;
      expect(created.side, side);
      expect(created.userId, MockCallsRepository.demoViewerUserId);
      expect(created.parentCallId, parent.call.id);
      expect(created.fundingState, FundingState.none);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty Home at 320px and double text keeps recovery reachable', (
    tester,
  ) async {
    final provider = CallsProvider(
      repository: MockCallsRepository()..debugClearCalls(),
    );
    addTearDown(provider.dispose);
    var opened = false;
    await mount(
      tester,
      ChangeNotifierProvider<CallsProvider>.value(
        value: provider,
        child: CallFeedScreen(
          showHeader: false,
          onBrowseMarkets: () => opened = true,
        ),
      ),
      width: 320,
      scale: 2,
    );
    await tester.ensureVisible(find.text('Explore markets'));
    await tester.tap(find.text('Explore markets'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}

/// Explicitly demo-only visual data, with relative timestamps so the golden
/// never changes at a calendar boundary. Production repositories are untouched.
class _VisualCallsRepository extends MockCallsRepository {
  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    final page = await super.fetchFeed(mode: mode, viewerUserId: viewerUserId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries =
        page.entries.take(2).indexed.map((pair) {
          final (index, entry) = pair;
          return CallFeedEntry(
            author: Person(
              id: entry.author.id,
              handle: index == 0 ? 'ada' : 'kemi',
              displayName: index == 0 ? 'Ada Okafor' : 'Kemi Balogun',
              avatarUrl: 'assets/images/ai_gen/profile_images/${index + 1}.png',
            ),
            call: Call.fromJson({
              ...entry.call.toJson(),
              'side': index == 0 ? 'YES' : 'NO',
              'createdAt': now - 30 * 60000,
              'lockedAt': now - 30 * 60000,
              'thesis':
                  index == 0
                      ? 'Holding my view through the close. The final print matters, not the intraday move.'
                      : 'I see it differently. Calling the other side before the deadline.',
            }),
            market: VenueMarket.fromJson({
              ...entry.market.toJson(),
              'question': 'Will SOL close above \$200 tomorrow?',
              'closesAt': now + const Duration(hours: 20).inMilliseconds,
              'venue': 'fixture',
            }),
          );
        }).toList();
    return CallFeedPage(entries: entries, servedAt: now);
  }
}
