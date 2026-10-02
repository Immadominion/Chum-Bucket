import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_stats_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'packet_g_fixtures.dart';

Future<void> mountPeople(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double scale = 2,
  Widget Function(Widget)? wrap,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = ScreenUtilInit(
    designSize: const Size(390, 844),
    builder:
        (_, __) => MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
          home: child,
        ),
  );
  await tester.pumpWidget(wrap?.call(app) ?? app);
  await tester.pumpAndSettle();
}

Future<void> revealPeopleText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.dragFrom(const Offset(20, 700), const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
  await tester.pumpAndSettle();
}

CallFeedEntry peopleEntry(
  String id,
  CallOutcome outcome, {
  CallVisibility visibility = CallVisibility.public,
  FundingState funding = FundingState.none,
  bool demo = false,
}) {
  final entry = testEntry(id: id, outcome: outcome, funding: funding);
  return CallFeedEntry(
    call: Call.fromJson({
      ...entry.call.toJson(),
      'visibility': visibility.wire,
    }),
    author: entry.author,
    market: entry.market.copyWith(
      venue: demo ? MarketVenue.fixture : MarketVenue.panta,
    ),
    result: entry.result,
  );
}

class PeopleRepository extends MockCallsRepository {
  PeopleRepository(this.entries) : super(latency: Duration.zero);
  final List<CallFeedEntry> entries;
  final List<String> requestedPeople = [];
  bool reject = false;
  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) async {
    requestedPeople.add(personRef);
    if (reject) throw const CallsRejectedException('This profile is private.');
    return PersonDetail(person: testPerson, calls: entries, servedAt: 0);
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final width in [320.0, 430.0]) {
    testWidgets('identity and private wallet row wrap at ${width}dp and 2x', (
      tester,
    ) async {
      var edited = false;
      await mountPeople(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                children: [
                  ProfileHeader(
                    username: 'A familiar long display name',
                    handle: 'my_existing_account',
                    bio: 'My existing bio stays with my original profile.',
                    profileImagePath:
                        'assets/images/ai_gen/profile_images/1.png',
                    onEditProfile: () => edited = true,
                    footer: const ProfileWalletCard(),
                  ),
                  const ProfileStatsCard(),
                ],
              ),
            ),
          ),
        ),
        width: width,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('My wallet'), findsOneWidget);
      expect(find.textContaining(' SOL'), findsNothing);
      expect(find.text('Public call record unavailable'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Edit profile')).shortestSide,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byTooltip('Edit profile'));
      expect(edited, isTrue);
      final header = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ProfileHeader),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((header.decoration as BoxDecoration).color, AppColors.surface);
    });
  }

  testWidgets(
    'record counts visible public free calls, losses and voids honestly',
    (tester) async {
      await mountPeople(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: ProfileStatsCard(
              entries: [
                peopleEntry('correct', CallOutcome.correct),
                peopleEntry('incorrect', CallOutcome.incorrect),
                peopleEntry('void', CallOutcome.voided),
                peopleEntry('waiting', CallOutcome.pending),
                peopleEntry(
                  'private',
                  CallOutcome.correct,
                  visibility: CallVisibility.followers,
                ),
                peopleEntry(
                  'funded',
                  CallOutcome.correct,
                  funding: FundingState.filled,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('1 / 2'), findsOneWidget);
      expect(
        find.text('1 incorrect · 2 decided. Void excluded.'),
        findsOneWidget,
      );
      expect(find.text('void · not scored'), findsOneWidget);
      expect(
        find.textContaining('31'),
        findsNothing,
      ); // unscoped person aggregate
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'own profile resolves canonical identity and separates history from positions',
    (tester) async {
      final repository = PeopleRepository([]);
      final provider = CallsProvider(repository: repository)
        ..setViewer('user_ada');
      addTearDown(provider.dispose);
      var openedChallenges = false;
      await mountPeople(
        tester,
        ChangeNotifierProvider.value(
          value: provider,
          child: ProfileScreen(
            embedded: true,
            onOpenChallenges: () => openedChallenges = true,
          ),
        ),
      );
      expect(repository.requestedPeople, everyElement('user_ada'));
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(find.text('Create my profile'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await revealPeopleText(tester, 'Positions');
      await tester.tap(find.text('Positions'));
      await tester.pumpAndSettle();
      // Positions are real and account-scoped now: without a canonical
      // session the tab asks for sign-in instead of showing any figure.
      expect(find.text('Sign in to see your positions'), findsOneWidget);
      expect(find.textContaining('USDC'), findsNothing);
      // Escrow challenges and Arena predictions are no longer profile tabs;
      // they live in Settings → History, which keeps the escrow opener
      // (covered in call_home_screen_test.dart).
      expect(find.text('Challenges'), findsNothing);
      expect(find.text('Prediction history'), findsNothing);
      expect(openedChallenges, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'public profile is the same person, without private amounts or unscoped totals',
    (tester) async {
      final repository = PeopleRepository([
        peopleEntry('hit', CallOutcome.correct, demo: true),
        peopleEntry('miss', CallOutcome.incorrect),
      ]);
      final provider = CallsProvider(repository: repository);
      addTearDown(provider.dispose);
      await mountPeople(
        tester,
        ChangeNotifierProvider.value(
          value: provider,
          child: const CallPersonScreen(personRef: 'user_ada'),
        ),
      );
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('DEMO DATA · sample call record'), findsOneWidget);
      expect(find.text('My wallet'), findsNothing);
      expect(find.textContaining('PnL'), findsNothing);
      expect(find.text('19 correct'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await revealPeopleText(tester, 'Record');
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      expect(find.text('1 incorrect'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('private or blocked person errors are explicit and retryable', (
    tester,
  ) async {
    final repository = PeopleRepository([])..reject = true;
    final provider = CallsProvider(repository: repository);
    addTearDown(provider.dispose);
    await mountPeople(
      tester,
      ChangeNotifierProvider.value(
        value: provider,
        child: const CallPersonScreen(personRef: 'private_person'),
      ),
    );
    expect(find.text('This profile is private.'), findsOneWidget);
    expect(find.byType(ProfileHeader), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
