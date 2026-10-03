/// Test-only fakes for the onboarding suite. Every value here is synthetic
/// and reachable only from tests: nothing in `lib/` can construct it, and
/// the app never shows it.
library;

import 'dart:async';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_flow.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_repository.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

/// A fixed instant: 2 Oct 2026, 12:00 UTC.
final DateTime kNow = DateTime.utc(2026, 10, 2, 12);
int get kNowMs => kNow.millisecondsSinceEpoch;

int _seq = 0;
String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

VenueMarket pantaMarket(
  String id, {
  String? question,
  String category = 'crypto',
  Duration closesIn = const Duration(days: 2),
  MarketStatus status = MarketStatus.open,
  MarketVenue venue = MarketVenue.panta,
}) => VenueMarket(
  id: id,
  venue: venue,
  venueEventId: 'ev-$id',
  venueMarketId: 'vm-$id',
  question: question ?? 'Will $id happen by Friday?',
  rulesText: 'Resolves YES if it happens.',
  category: category,
  outcomes: const [
    MarketOutcome(side: Side.yes, label: 'Yes'),
    MarketOutcome(side: Side.no, label: 'No'),
  ],
  status: status,
  rawStatus: status.wire.toLowerCase(),
  opensAt: kNowMs - 86400000,
  closesAt: kNow.add(closesIn).millisecondsSinceEpoch,
  resolvesAt: null,
  resolutionSource: null,
  lastSyncedAt: kNowMs,
  payloadVersion: 1,
);

SharePriceSnapshot priceFor(
  String marketId, {
  Duration age = const Duration(minutes: 1),
  String yes = '0.50',
  String no = '0.50',
  DateTime Function()? clock,
}) => SharePriceSnapshot(
  id: uuid(900000 + marketId.hashCode.abs() % 99999),
  marketId: marketId,
  yesPrice: yes,
  noPrice: no,
  observedAt: (clock ?? () => kNow)().subtract(age).millisecondsSinceEpoch,
);

PublicRecord record({int correct = 0, int decided = 0, int pending = 0}) =>
    PublicRecord(
      correct: correct,
      incorrect: decided - correct,
      voided: 0,
      decided: decided,
      pending: pending,
      minimumDecided: 10,
      accuracy: decided >= 10 ? correct / decided : null,
    );

PersonCard personCard(
  String id, {
  String? name,
  String? handle,
  PublicRecord? rec,
  bool following = false,
}) => PersonCard(
  id: id,
  handle: handle ?? id,
  displayName: name ?? id.toUpperCase(),
  record: rec ?? record(pending: 1),
  viewerIsFollowing: following,
);

Call call(
  String id, {
  required String userId,
  required String marketId,
  Side side = Side.yes,
  String? thesis,
  String? parentCallId,
  SharePriceSnapshot? entryPrice,
  int? lockedAt,
}) => Call(
  id: id,
  userId: userId,
  marketId: marketId,
  side: side,
  confidence: null,
  thesis: thesis,
  entryProbability: null,
  snapshotId: null,
  entryPrice: entryPrice,
  visibility: CallVisibility.public,
  createdAt: lockedAt ?? kNowMs - 3600000,
  lockedAt: lockedAt ?? kNowMs - 3600000,
  parentCallId: parentCallId,
  fundingState: FundingState.none,
);

TopCall topCall(
  VenueMarket market,
  PersonCard author, {
  Side side = Side.yes,
  int responses = 0,
  String? thesis,
}) => TopCall(
  call: call(
    'call-${author.id}-${market.id}',
    userId: author.id,
    marketId: market.id,
    side: side,
    thesis: thesis,
  ),
  author: author,
  market: market,
  responses: responses,
);

PersonSuggestion suggestion(
  PersonCard person, {
  SuggestionReason reason = SuggestionReason.recent,
  TopCall? latest,
}) => PersonSuggestion(
  person: person,
  reason: reason,
  latestLiveCall:
      latest == null
          ? null
          : LatestLiveCall(
            callId: latest.call.id,
            side: latest.call.side,
            marketId: latest.market.id,
            question: latest.market.question,
            closesAt: latest.market.closesAt,
          ),
);

/// A calls/people/suggestions backend in memory. Writes are recorded so a
/// test can assert exactly what the app asked the server to do.
class FakeOnboardingRepository
    implements
        CallsRepository,
        CallsCatalogRepository,
        PeopleRepository,
        PeopleSuggestionsRepository {
  FakeOnboardingRepository({
    List<VenueMarket>? catalog,
    Map<String, SharePriceSnapshot>? prices,
    this.top = const [],
    this.feed = const [],
    this.followingFeed = const [],
    this.suggestions,
    this.clock,
  }) : catalog = catalog ?? [],
       prices = prices ?? {};

  List<VenueMarket> catalog;
  Map<String, SharePriceSnapshot> prices;
  List<TopCall> top;
  List<CallFeedEntry> feed;
  List<CallFeedEntry> followingFeed;

  /// Null: the server has no `people.suggested` yet.
  PeopleSuggestions? suggestions;
  DateTime Function()? clock;

  bool offline = false;
  final List<String> followed = [];
  final List<CreateCallInput> created = [];
  final List<RespondToCallInput> responded = [];
  final Map<String, CallFeedEntry> ownCalls = {};
  final Set<String> failFollowIds = {};
  int suggestionReads = 0;
  int catalogReads = 0;
  Completer<void>? holdCatalog;

  DateTime get now => (clock ?? () => kNow)();

  void _online() {
    if (offline) throw const CallsOfflineException();
  }

  Person _person(String id) =>
      Person(id: id, handle: id, displayName: id.toUpperCase());

  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    _online();
    return CallFeedPage(
      entries: mode == CallFeedMode.following ? followingFeed : feed,
      servedAt: now.millisecondsSinceEpoch,
    );
  }

  @override
  Future<List<VenueMarket>> fetchMarketCatalog() async {
    catalogReads++;
    final hold = holdCatalog;
    if (hold != null) await hold.future;
    _online();
    return catalog;
  }

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) =>
      fetchMarketCatalog();

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    _online();
    final market = catalog.firstWhere((m) => m.id == marketId);
    return MarketDetail(
      market: market,
      sharePrice: prices[marketId],
      snapshot: null,
      servedAt: now.millisecondsSinceEpoch,
      viewerCall: viewerUserId == null ? null : ownCalls[marketId],
    );
  }

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async {
    _online();
    for (final t in top) {
      if (t.call.id == callId) {
        return CallDetail(
          entry: CallFeedEntry(
            call: t.call,
            author: _person(t.author.id),
            market: t.market,
          ),
        );
      }
    }
    for (final e in [...feed, ...ownCalls.values]) {
      if (e.call.id == callId) return CallDetail(entry: e);
    }
    throw const CallsRejectedException('No such call.');
  }

  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) async => PersonDetail(
    person: _person(personRef),
    calls: const [],
    servedAt: now.millisecondsSinceEpoch,
  );

  @override
  Future<bool> setFollowing({
    required String personId,
    required bool following,
    required String? viewerUserId,
  }) async {
    if (viewerUserId == null) throw const CallsSignedOutException();
    if (failFollowIds.contains(personId)) throw const CallsFailure('boom');
    followed.add(personId);
    return following;
  }

  CallFeedEntry _lock(
    String marketId,
    Side side,
    String viewer, {
    String? parentCallId,
    String? thesis,
  }) {
    if (ownCalls.containsKey(marketId)) {
      throw const CallsRejectedException(
        'you already have a live call on this market',
      );
    }
    final market = catalog.firstWhere((m) => m.id == marketId);
    final price = prices[marketId];
    final entry = CallFeedEntry(
      call: call(
        'locked-${++_seq}',
        userId: viewer,
        marketId: marketId,
        side: side,
        thesis: thesis,
        parentCallId: parentCallId,
        entryPrice: price,
        lockedAt: now.millisecondsSinceEpoch,
      ),
      author: _person(viewer),
      market: market,
    );
    ownCalls[marketId] = entry;
    return entry;
  }

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) async {
    if (viewerUserId == null) throw const CallsSignedOutException();
    created.add(input);
    return _lock(
      input.marketId,
      input.side,
      viewerUserId,
      thesis: input.thesis,
      parentCallId: input.parentCallId,
    );
  }

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async {
    if (viewerUserId == null) throw const CallsSignedOutException();
    responded.add(input);
    final target = top.firstWhere((t) => t.call.id == input.targetCallId);
    final side =
        input.kind == CallResponseKind.fade
            ? target.call.side.opposite
            : target.call.side;
    final own = _lock(
      target.market.id,
      side,
      viewerUserId,
      parentCallId: target.call.id,
      thesis: input.thesis,
    );
    return CallResponseResult(
      response: CallResponse(
        id: 'response-${++_seq}',
        actorUserId: viewerUserId,
        targetCallId: target.call.id,
        kind: input.kind,
        resultingCallId: own.call.id,
        createdAt: now.millisecondsSinceEpoch,
      ),
      resultingCall: own,
    );
  }

  @override
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  }) async => const [];

  @override
  String shareLinkForCall(String callId) => 'https://chumbucket.fun/c/$callId';

  @override
  String shareLinkForPerson(String handleOrId) =>
      'https://chumbucket.fun/u/$handleOrId';

  @override
  Future<Leaderboard> fetchLeaderboard({
    required LeaderboardWindow window,
    int limit = 50,
  }) async => Leaderboard(
    window: window,
    ranked: const [],
    building: const [],
    minimumDecided: 10,
    rule: 'Ranked by record.',
    servedAt: now.millisecondsSinceEpoch,
  );

  @override
  Future<List<PersonCard>> searchPeople(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<List<PersonCard>> fetchFollowing() async => const [];

  @override
  Future<List<TopCall>> fetchTopCalls({int limit = 10}) async {
    _online();
    return top;
  }

  @override
  Future<ThesisUpdate> appendThesisUpdate({
    required String callId,
    required String body,
  }) => throw UnimplementedError();

  @override
  Future<PeopleSuggestions> fetchSuggestedPeople({int limit = 10}) async {
    suggestionReads++;
    _online();
    final s = suggestions;
    if (s == null) throw const PeopleSuggestionsUnavailable();
    return s;
  }
}

/// The OS side of notifications, counting every dialog it would show.
class FakePushPlatform implements PushPlatform {
  FakePushPlatform({this.granted = false, this.answer = true});
  bool granted;
  bool answer;
  int requests = 0;
  final List<String> registered = [];

  @override
  bool get available => true;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    granted = answer;
    return answer;
  }

  @override
  Future<void> register(AccountApi api, {required String accountKey}) async =>
      registered.add(accountKey);
}

/// The signed-in account's own API, as far as notifications need it: does
/// this server send pushes (`account.pushStatus`)?
class FakeAccountApi implements AccountApi {
  FakeAccountApi({this.pushLive = false});
  bool pushLive;
  int statusReads = 0;

  @override
  Future<bool> pushStatus() async {
    statusReads++;
    return pushLive;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A BFF for the session: whoami (with a handle or not), username checks and
/// claims, identity status.
class OnboardingBff {
  OnboardingBff({
    this.handle,
    this.handleKnown = true,
    this.unlinked = false,
    this.taken = const {},
    this.walletProfileCarry = true,
  });

  String? handle;
  bool handleKnown;
  bool unlinked;
  Set<String> taken;
  bool walletProfileCarry;
  final List<String> statusChecks = [];
  final List<String> claims = [];
  final List<Map<String, dynamic>> profiles = [];

  late final FakeBffServer server = FakeBffServer((request) {
    switch (request.procedurePath) {
      case 'auth.whoami':
        if (unlinked) {
          return errorResponse(
            code: 'PRECONDITION_FAILED',
            httpStatus: 412,
            message: 'AUTH_USER_UNLINKED',
            path: 'auth.whoami',
          );
        }
        return okResponse({
          'userId': kCanonicalUserId,
          'authUserId': kAuthUserId,
          if (handleKnown) 'handle': handle,
        });
      case 'auth.usernameStatus':
        final asked = request.input['handle'] as String;
        statusChecks.add(asked);
        return okResponse({
          'handle': asked,
          'status': taken.contains(asked) ? 'taken' : 'available',
        });
      case 'auth.claimUsername':
        final asked = request.input['handle'] as String;
        claims.add(asked);
        handle = asked;
        return okResponse({
          'userId': kCanonicalUserId,
          'authUserId': kAuthUserId,
          'handle': asked,
          'outcome': 'claimed',
        });
      case 'auth.completeProfile':
        final name = request.input['displayName'] as String;
        final asked = request.input['handle'] as String?;
        profiles.add({'displayName': name, 'handle': asked});
        unlinked = false;
        handle = asked;
        return okResponse({
          'userId': kCanonicalUserId,
          'authUserId': kAuthUserId,
          'handle': asked,
        });
      case 'auth.identityStatus':
        return okResponse({
          'enabled': true,
          'network': 'mainnet-beta',
          'proofVersion': 1,
          'walletSignIn': true,
          'walletProfileCarry': walletProfileCarry,
        });
    }
    return errorResponse(code: 'NOT_FOUND', httpStatus: 404);
  });
}

/// Everything an onboarding run needs, wired the way main.dart wires it.
class OnboardingRig {
  OnboardingRig({
    FakeOnboardingRepository? repo,
    OnboardingBff? bff,
    this.signedIn = false,
    SignInMethod? lastUsed,
    Set<String> providers = const {'google'},
    bool pushLive = false,
    FakePushPlatform? permission,
  }) : repo = repo ?? FakeOnboardingRepository(),
       bff = bff ?? OnboardingBff(handle: 'ada'),
       lastSignIn = MemoryLastSignInStore(lastUsed),
       account = FakeAccountApi(pushLive: pushLive),
       permission = permission ?? FakePushPlatform() {
    auth = FakeSupabaseAuthPort(restored: signedIn ? snapshot() : null)
      ..providers = providers;
    session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: this.bff.server.client,
      ),
      lastSignIn: lastSignIn,
    );
    analytics = AnalyticsRecorder(sink: sink);
    calls = CallsProvider(
      repository: this.repo,
      analytics: analytics,
      clock: () => clockNow,
    );
    app = OnboardingController(clock: () => clockNow, analytics: analytics);
  }

  final FakeOnboardingRepository repo;
  final OnboardingBff bff;
  final bool signedIn;
  final MemoryLastSignInStore lastSignIn;
  final FakeAccountApi account;
  final FakePushPlatform permission;
  final sink = InMemoryAnalyticsSink();
  late final FakeSupabaseAuthPort auth;
  late final ChumbucketSession session;
  late final AnalyticsRecorder analytics;
  late final CallsProvider calls;
  late final OnboardingController app;
  DateTime clockNow = kNow;
  final List<FlowExit> exits = [];

  List<String> events(AnalyticsEventName name) => [
    for (final e in sink.named(name)) '${e.props}',
  ];

  Future<void> start() async {
    PushRegistration.platform = permission;
    PushRegistration.clock = () => clockNow;
    await session.restore();
    calls.setViewer(session.userId);
    session.addListener(() => calls.setViewer(session.userId));
    await app.load();
  }

  Future<void> dispose() async {
    PushRegistration.platform = const FcmPushPlatform();
    PushRegistration.clock = DateTime.now;
    session.dispose();
    calls.dispose();
    app.dispose();
    await auth.close();
  }

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => MwaAuthProvider()),
      ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
      ChangeNotifierProvider<ChumbucketSession>.value(value: session),
      ChangeNotifierProvider<CallsProvider>.value(value: calls),
      ChangeNotifierProvider<OnboardingController>.value(value: app),
      Provider<AccountApi>.value(value: account),
    ],
    child: child,
  );

  Widget flow(
    OnboardingRun run, {
    OnboardingStep? resumeAt,
    bool sessionEnded = false,
    Widget? Function(OnboardingStep step)? stepBuilder,
  }) => OnboardingFlow(
    run: run,
    resumeAt: resumeAt,
    sessionEnded: sessionEnded,
    clock: () => clockNow,
    stepBuilder: stepBuilder,
    onExit: (_, exit) => exits.add(exit),
  );
}

/// Mounts [child] at a phone size and text scale, with the app's theme.
/// [around] wraps the whole app, the way main.dart puts providers above
/// MaterialApp so routes pushed later can read them (`rig.wrap`).
Future<void> mountAt(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 844,
  double scale = 1,
  bool reduceMotion = false,
  Widget Function(Widget app)? around,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final wrap = around ?? (Widget app) => app;
  await tester.pumpWidget(
    wrap(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        builder:
            (_, __) => MaterialApp(
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              builder:
                  (context, appChild) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: reduceMotion,
                    ),
                    child: appChild!,
                  ),
              home: child,
            ),
      ),
    ),
  );
}

/// Pumps frames for [duration] in steps (no pumpAndSettle: Lottie and
/// skeletons may hold the tree "busy").
Future<void> settle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 800),
]) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < duration; t += step) {
    await tester.pump(step);
  }
}

/// The real fonts, for captures and goldens.
Future<void> loadBrandFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  for (final (family, paths) in [
    (
      'PPNeueMachina',
      [
        'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
        'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
      ],
    ),
    (
      'Montserrat',
      [
        'assets/fonts/Montserrat/Montserrat-Regular.ttf',
        'assets/fonts/Montserrat/Montserrat-Medium.ttf',
      ],
    ),
    ('Montserrat_regular', ['assets/fonts/Montserrat/Montserrat-Regular.ttf']),
    ('Montserrat_500', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
    ('Montserrat_medium', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
    ('Inter_regular', ['assets/fonts/Inter/Inter-Regular.ttf']),
    ('Inter_500', ['assets/fonts/Inter/Inter-Medium.ttf']),
    ('Inter_600', ['assets/fonts/Inter/Inter-SemiBold.ttf']),
    ('Inter_700', ['assets/fonts/Inter/Inter-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}
