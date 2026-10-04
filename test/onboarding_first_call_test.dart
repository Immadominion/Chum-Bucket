// C "Make your first call", A1 "Sign in to lock your call" and R "You're on
// record" (onboarding spec §6, §8), acceptance as tests: a swipeable deck of
// real markets with fresh prices only, no money anywhere, a signed-out pick
// kept on the phone through sign-in, a compact composer that needs a fresh
// tap to lock, the server's own record on R, and no notification dialog
// before the person asks for one.
import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/first_call_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/on_record_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';
import 'session_fakes.dart';

OnboardingFlowController _flow(WidgetTester tester) =>
    Provider.of<OnboardingFlowController>(
      tester.element(find.byType(Scaffold).last),
      listen: false,
    );

/// The scene on the wall clock: the composer checks price freshness against
/// the real time, so the prices are a minute old in real time too.
({OnboardingScene scene, FakeOnboardingRepository repo, DateTime now}) _live() {
  final now = DateTime.now().toUtc();
  final scene = OnboardingScene();
  final repo = scene.repository();
  repo.clock = () => now;
  repo.prices = {
    for (final MapEntry(key: id, value: p) in scene.prices.entries)
      id: priceFor(
        id,
        yes: p.yesPrice!,
        no: p.noPrice!,
        age:
            id == scene.stale.id
                ? const Duration(minutes: 15)
                : const Duration(minutes: 1),
        clock: () => now,
      ),
  };
  // Markets measured from the real now as well.
  repo.catalog = [
    for (final m in scene.catalog)
      pantaMarket(
        m.id,
        question: m.question,
        category: m.category,
        closesIn: Duration(milliseconds: m.closesAt! - kNowMs),
      ).rebasedTo(now),
  ];
  return (scene: scene, repo: repo, now: now);
}

extension on VenueMarket {
  /// The same market, with open/close moved from kNow to [now].
  VenueMarket rebasedTo(DateTime now) {
    final shift = now.millisecondsSinceEpoch - kNowMs;
    return VenueMarket(
      id: id,
      venue: venue,
      venueEventId: venueEventId,
      venueMarketId: venueMarketId,
      question: question,
      rulesText: rulesText,
      category: category,
      outcomes: outcomes,
      status: status,
      rawStatus: rawStatus,
      opensAt: opensAt == null ? null : opensAt! + shift,
      closesAt: closesAt == null ? null : closesAt! + shift,
      resolvesAt: resolvesAt,
      resolutionSource: resolutionSource,
      lastSyncedAt: lastSyncedAt,
      payloadVersion: payloadVersion,
    );
  }
}

Future<OnboardingRig> _atFirstCall(
  WidgetTester tester, {
  FakeOnboardingRepository? repo,
  DateTime? now,
  bool signedIn = false,
  bool pushLive = false,
  OnboardingBff? bff,
}) async {
  final rig = OnboardingRig(
    repo: repo,
    signedIn: signedIn,
    pushLive: pushLive,
    bff: bff,
    lastUsed: SignInMethod.google,
  );
  if (now != null) rig.clockNow = now;
  await tester.runAsync(rig.start);
  addTearDown(rig.dispose);
  await mountAt(
    tester,
    rig.flow(OnboardingRun.newUser),
    around: rig.wrap,
    height: 1000,
  );
  await settle(tester);
  _flow(tester).goTo(OnboardingStep.firstCall);
  await settle(tester, const Duration(milliseconds: 1500));
  expect(find.byType(FirstCallScreen), findsOneWidget);
  return rig;
}

Finder _inComposer(Finder f) =>
    find.descendant(of: find.byType(CallComposerSheet), matching: f);

/// The deck card for [marketId].
Finder _card(String marketId) => find.byKey(ValueKey('first-call-$marketId'));

/// YES or NO on the deck card for [marketId] (the next card peeks in beside
/// it with its own buttons, so the card is named).
Finder _answer(String marketId, Side side) => find.descendant(
  of: _card(marketId),
  matching: find.byKey(ValueKey('deck-${side.wire.toLowerCase()}')),
);

/// What only the full composer shows: reason, visibility, confidence, rules.
void _expectCompact(WidgetTester tester) {
  expect(_inComposer(find.byType(TextField)), findsNothing);
  expect(_inComposer(find.text('Your reason (optional)')), findsNothing);
  expect(_inComposer(find.byType(CallJourneyReason)), findsNothing);
  expect(_inComposer(find.byType(CallJourneyVisibility)), findsNothing);
  expect(_inComposer(find.byType(CallJourneyConfidence)), findsNothing);
  expect(_inComposer(find.text('Read the market rules')), findsNothing);
}

/// Scrolls C to its end, where the deck is. Only the page scrolls: the
/// deck's own pages stay where they are (ensureVisible would slide them).
Future<void> _toDeck(WidgetTester tester) async {
  final page = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(SingleChildScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  page.position.jumpTo(page.position.maxScrollExtent);
  await settle(tester, const Duration(milliseconds: 200));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every market offered has a fresh Panta price and >30 minutes', (
    tester,
  ) async {
    final live = _live();
    final rig = await _atFirstCall(tester, repo: live.repo, now: live.now);
    final flow = _flow(tester);
    expect(flow.firstCallMarkets, isNotEmpty);
    expect(flow.firstCallMarkets.length, lessThanOrEqualTo(kFirstCallMarkets));
    for (final m in flow.firstCallMarkets) {
      expect(m.sharePrice.isUsableAt(live.now), isTrue, reason: m.market.id);
      expect(
        m.market.closesAt! - live.now.millisecondsSinceEpoch,
        greaterThan(const Duration(minutes: 30).inMilliseconds),
      );
    }
    // Fifteen-minute-old gold price and the market closing in 20 minutes are
    // not offered.
    final offered = flow.firstCallMarkets.map((m) => m.market.id);
    expect(offered, isNot(contains(live.scene.stale.id)));
    expect(offered, isNot(contains(live.scene.soon.id)));
    // "Answer a call" first: named people's live calls.
    expect(find.text(OnboardingCopy.callAnswerHeader), findsOneWidget);
    expect(find.text(OnboardingCopy.callAnswerHelper), findsOneWidget);
    // Then the deck, one offered market per card; nothing else to browse.
    await _toDeck(tester);
    expect(_card(flow.firstCallMarkets.first.market.id), findsOneWidget);
    expect(find.byKey(const ValueKey('first-call-see-all')), findsNothing);
    expect(find.text(OnboardingCopy.callSeeAll), findsNothing);
    expect(
      rig.events(AnalyticsEventName.onboardingStepViewed),
      contains(allOf(contains('first_call'), contains('markets'))),
    );
  });

  testWidgets('no wallet, amount, deposit or money prompt anywhere in C', (
    tester,
  ) async {
    final live = _live();
    await _atFirstCall(tester, repo: live.repo, now: live.now);
    for (final word in [
      'wallet',
      'deposit',
      'Add funds',
      'amount',
      'balance',
    ]) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('the deck: one real market per card, swiped sideways', (
    tester,
  ) async {
    final live = _live();
    await _atFirstCall(tester, repo: live.repo, now: live.now);
    final markets = _flow(tester).firstCallMarkets;
    expect(markets.length, greaterThan(1));
    final first = markets[0].market;
    final second = markets[1].market;
    await _toDeck(tester);
    expect(find.text(first.question), findsOneWidget);
    // Panta's price on each answer.
    expect(
      find.descendant(
        of: _answer(first.id, Side.no),
        matching: find.text(
          CallsFormat.displayPrice(markets[0].sharePrice.noPrice!),
        ),
      ),
      findsOneWidget,
    );
    // The first card is centred; a swipe brings the next one to the centre.
    expect(tester.getCenter(_card(first.id)).dx, closeTo(390 / 2, 1));
    await tester.fling(_card(first.id), const Offset(-300, 0), 1000);
    await settle(tester);
    expect(tester.getCenter(_card(second.id)).dx, closeTo(390 / 2, 1));
  });

  testWidgets(
    'signed out: YES or NO keeps the pick on the phone and goes straight to '
    'sign-in (no sheet); after sign-in the compact composer reopens with it '
    'and needs a fresh tap',
    (tester) async {
      final live = _live();
      final rig = await _atFirstCall(tester, repo: live.repo, now: live.now);
      final market = _flow(tester).firstCallMarkets.first.market;

      await _toDeck(tester);
      await tester.tap(_answer(market.id, Side.no));
      await settle(tester);

      // A1 at once, titled for the call, with the draft card. No composer.
      expect(find.byType(CallComposerSheet), findsNothing);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(OnboardingCopy.signInTitleCall), findsOneWidget);
      expect(find.text(market.question), findsOneWidget);
      expect(find.text(OnboardingCopy.signInDraftNote), findsOneWidget);
      expect(rig.repo.created, isEmpty);
      // The pick on a market, then the call kept for after sign-in.
      expect(rig.events(AnalyticsEventName.onboardingFirstCallOpened), [
        allOf(contains('kind: market'), contains(market.id)),
        allOf(contains('kind: call'), contains(market.id)),
      ]);

      // The pick is on the phone, so it survives the OAuth app switch and a
      // process death.
      final saved = await const OnboardingStore().readPendingCall(live.now);
      expect(saved?.kind, PendingCallKind.call);
      expect(saved?.marketId, market.id);
      expect(saved?.side, Side.no);
      expect(saved?.thesis, isNull);

      // Sign in with Google (the "Last used" door, first and filled).
      rig.auth.deliverOnSignIn = snapshot();
      await tester.tap(find.byKey(const ValueKey('front-door-google')));
      await settle(tester, const Duration(milliseconds: 1500));
      expect(rig.session.isReady, isTrue);

      // The compact composer is back with the pick, a note, nothing locked.
      expect(find.byType(CallComposerSheet), findsOneWidget);
      expect(
        tester.widget<CallComposerSheet>(find.byType(CallComposerSheet)),
        isA<CallComposerSheet>().having((c) => c.compact, 'compact', isTrue),
      );
      expect(
        _inComposer(find.text(OnboardingCopy.callSignedInNote('ada'))),
        findsOneWidget,
      );
      expect(_inComposer(find.text(market.question)), findsOneWidget);
      expect(
        _inComposer(find.textContaining('You’re calling NO')),
        findsOneWidget,
      );
      _expectCompact(tester);
      expect(_inComposer(find.text('Lock my NO call')), findsOneWidget);
      expect(rig.repo.created, isEmpty, reason: 'never locked on its own');

      await tester.tap(_inComposer(find.text('Lock my NO call')));
      await settle(tester, const Duration(milliseconds: 2600));

      // R shows the server's own record of the call.
      expect(rig.repo.created, hasLength(1));
      expect(rig.repo.created.single.side, Side.no);
      expect(rig.repo.created.single.thesis, isNull);
      expect(rig.repo.created.single.visibility, CallVisibility.public);
      final own = rig.repo.ownCalls[market.id]!;
      expect(find.byType(OnRecordScreen), findsOneWidget);
      expect(
        find.byKey(ValueKey('record-call-${own.call.id}')),
        findsOneWidget,
      );
      // The server's stamped price for the side called (NO), not the draft.
      expect(
        find.text(OnboardingCopy.recordLockedAt(own.call.entryPrice!.noPrice!)),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('record-price')), findsOneWidget);
      // The draft is gone once locked.
      expect(await const OnboardingStore().readPendingCall(live.now), isNull);
      expect(rig.events(AnalyticsEventName.callCreated), isNotEmpty);
      expect(
        rig.events(AnalyticsEventName.callCreated).single,
        contains('onboarding'),
      );
    },
  );

  testWidgets(
    'the reopened composer put away without locking is one tap from coming '
    'back, pick and all',
    (tester) async {
      final live = _live();
      final rig = await _atFirstCall(tester, repo: live.repo, now: live.now);
      final market = _flow(tester).firstCallMarkets.first.market;
      await _toDeck(tester);
      await tester.tap(_answer(market.id, Side.no));
      await settle(tester);
      rig.auth.deliverOnSignIn = snapshot();
      await tester.tap(find.byKey(const ValueKey('front-door-google')));
      await settle(tester, const Duration(milliseconds: 1500));
      expect(find.byType(CallComposerSheet), findsOneWidget);

      // Swiped away, nothing locked.
      Navigator.of(tester.element(find.byType(CallComposerSheet))).pop();
      await settle(tester);
      expect(find.byType(CallComposerSheet), findsNothing);
      expect(rig.repo.created, isEmpty);
      // The draft's market has its own card; it is not offered again beside
      // it, as a deck card or as someone's call to answer.
      final flow = _flow(tester);
      expect(
        flow.firstCallMarkets.map((m) => m.market.id),
        isNot(contains(market.id)),
      );
      expect(
        flow.answerable.map((t) => t.market.id),
        isNot(contains(market.id)),
      );

      await tester.tap(find.byKey(const ValueKey('draft-review')));
      await settle(tester);
      expect(find.byType(CallComposerSheet), findsOneWidget);
      expect(_inComposer(find.text('Lock my NO call')), findsOneWidget);
      expect(rig.repo.created, isEmpty, reason: 'still a fresh tap to lock');
    },
  );

  testWidgets(
    'signed in: YES on a card opens the compact composer with YES chosen; '
    'one tap locks it',
    (tester) async {
      final live = _live();
      final rig = await _atFirstCall(
        tester,
        repo: live.repo,
        now: live.now,
        signedIn: true,
      );
      final item = _flow(tester).firstCallMarkets.first;
      await _toDeck(tester);
      await tester.tap(_answer(item.market.id, Side.yes));
      await settle(tester);
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byType(CallComposerSheet), findsOneWidget);
      expect(_inComposer(find.text(item.market.question)), findsOneWidget);
      expect(
        _inComposer(
          find.text(
            'You’re calling YES at '
            '${CallsFormat.displayPrice(item.sharePrice.yesPrice!)}. '
            'Free, and it goes on your record.',
          ),
        ),
        findsOneWidget,
      );
      _expectCompact(tester);
      expect(rig.repo.created, isEmpty, reason: 'nothing before Lock');

      await tester.tap(_inComposer(find.text('Lock my YES call')));
      await settle(tester, const Duration(milliseconds: 2600));
      expect(rig.repo.created.single.marketId, item.market.id);
      expect(rig.repo.created.single.side, Side.yes);
      expect(rig.repo.created.single.thesis, isNull);
      expect(rig.repo.created.single.confidence, isNull);
      expect(rig.repo.created.single.visibility, CallVisibility.public);
      expect(find.byType(OnRecordScreen), findsOneWidget);
    },
  );

  testWidgets(
    'the compact composer shows the question, the sides and Lock; the full '
    'one adds reason, visibility, confidence and rules',
    (tester) async {
      final live = _live();
      final rig = OnboardingRig(repo: live.repo, signedIn: true);
      await tester.runAsync(rig.start);
      addTearDown(rig.dispose);
      final market = live.repo.catalog.firstWhere(
        (m) => m.id == live.scene.btc.id,
      );
      for (final compact in [true, false]) {
        await mountAt(
          tester,
          Scaffold(
            body: CallComposerSheet(
              key: ValueKey('composer-$compact'),
              market: market,
              sharePrice: live.repo.prices[market.id],
              initialSide: Side.yes,
              compact: compact,
            ),
          ),
          around: rig.wrap,
          height: 2000,
        );
        await settle(tester, const Duration(milliseconds: 300));
        expect(_inComposer(find.text(market.question)), findsOneWidget);
        expect(_inComposer(find.text('YES')), findsWidgets);
        expect(_inComposer(find.text('NO')), findsWidgets);
        expect(_inComposer(find.text('Lock my YES call')), findsOneWidget);
        if (compact) {
          _expectCompact(tester);
          expect(
            _inComposer(
              find.textContaining('Free, and it goes on your record'),
            ),
            findsOneWidget,
          );
        } else {
          // The full composer keeps them behind one "More options".
          expect(_inComposer(find.byType(CallJourneyReason)), findsNothing);
          await tester.tap(
            _inComposer(find.byKey(const ValueKey('composer-more-options'))),
          );
          await settle(tester, const Duration(milliseconds: 300));
          expect(_inComposer(find.byType(CallJourneyReason)), findsOneWidget);
          expect(
            _inComposer(find.byType(CallJourneyVisibility)),
            findsOneWidget,
          );
          expect(
            _inComposer(find.byType(CallJourneyConfidence)),
            findsOneWidget,
          );
          expect(_inComposer(find.text('Market rules')), findsOneWidget);
        }
      }
    },
  );

  testWidgets('Back and Fade answer the named person\'s call (parentCallId)', (
    tester,
  ) async {
    final live = _live();
    final rig = await _atFirstCall(
      tester,
      repo: live.repo,
      now: live.now,
      signedIn: true,
    );
    final top = live.repo.top.first;
    await tester.tap(find.byKey(ValueKey('answer-fade-${top.call.id}')));
    await settle(tester);
    expect(find.byType(CallResponseSheet), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byType(CallResponseSheet),
            matching: find.textContaining('Lock'),
          )
          .last,
    );
    await settle(tester, const Duration(milliseconds: 2600));
    expect(rig.repo.responded.single.targetCallId, top.call.id);
    expect(rig.repo.responded.single.kind, CallResponseKind.fade);
    final own = rig.repo.ownCalls[top.market.id]!;
    expect(own.call.parentCallId, top.call.id);
    expect(own.call.side, top.call.side.opposite);
    expect(find.byType(OnRecordScreen), findsOneWidget);
  });

  testWidgets(
    'a Fade saved signed out on what turns out to be your own call is dropped',
    (tester) async {
      // Production, 4 Oct: the person signed in again as the account that
      // made the call, and the saved Fade replayed into a sheet whose Lock
      // the server refused ("You can't respond to your own call").
      final live = _live();
      final mine = topCall(
        live.scene.gta,
        personCard(kCanonicalUserId, name: 'Dominion', handle: 'dev'),
        side: Side.no,
        responses: 1,
      );
      live.repo.top = [mine, ...live.repo.top];
      final rig = await _atFirstCall(tester, repo: live.repo, now: live.now);
      // Signed out, nobody knows whose call it is yet: it is on offer.
      expect(
        find.byKey(ValueKey('answer-fade-${mine.call.id}')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('answer-fade-${mine.call.id}')),
      );
      await tester.tap(find.byKey(ValueKey('answer-fade-${mine.call.id}')));
      await settle(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        (await const OnboardingStore().readPendingCall(live.now))?.targetCallId,
        mine.call.id,
      );

      rig.auth.deliverOnSignIn = snapshot();
      await tester.tap(find.byKey(const ValueKey('front-door-google')));
      await settle(tester, const Duration(milliseconds: 1500));
      expect(rig.session.userId, kCanonicalUserId);

      // No sheet, nothing sent, the draft gone, and one friendly line.
      expect(find.byType(CallResponseSheet), findsNothing);
      expect(rig.repo.responded, isEmpty);
      expect(await const OnboardingStore().readPendingCall(live.now), isNull);
      expect(find.text(OnboardingCopy.callOwnDraft), findsOneWidget);
      // Their own call no longer appears among the calls to answer.
      expect(find.byKey(ValueKey('answer-fade-${mine.call.id}')), findsNothing);
      expect(
        _flow(tester).answerable.map((t) => t.author.id),
        isNot(contains(kCanonicalUserId)),
      );
    },
  );

  testWidgets(
    '"I\'ll do this later" signed out goes to A1 titled for going on record',
    (tester) async {
      final live = _live();
      await _atFirstCall(tester, repo: live.repo, now: live.now);
      await tester.tap(find.byKey(const ValueKey('first-call-later')));
      await settle(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(OnboardingCopy.signInTitleDefault), findsOneWidget);
    },
  );

  group('R You\'re on record', () {
    Future<OnboardingRig> lockOne(
      WidgetTester tester, {
      required bool pushLive,
      bool permitted = false,
      bool reduceMotion = false,
    }) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        signedIn: true,
        pushLive: pushLive,
        permission: FakePushPlatform(granted: permitted),
      );
      await tester.runAsync(rig.start);
      addTearDown(rig.dispose);
      await mountAt(
        tester,
        rig.flow(OnboardingRun.newUser),
        around: rig.wrap,
        reduceMotion: reduceMotion,
      );
      await settle(tester);
      final entry = await rig.calls.createCall(
        CreateCallInput(marketId: OnboardingScene().btc.id, side: Side.yes),
      );
      await _flow(tester).locked(entry);
      await settle(tester, const Duration(milliseconds: 2600));
      expect(find.byType(OnRecordScreen), findsOneWidget);
      return rig;
    }

    testWidgets(
      'push not live: no card, no dialog, the receipt is in Activity',
      (tester) async {
        final rig = await lockOne(tester, pushLive: false);
        expect(find.byKey(const ValueKey('record-notify-card')), findsNothing);
        expect(find.text(OnboardingCopy.recordNoPush), findsOneWidget);
        expect(rig.permission.requests, 0);
        expect(find.byKey(const ValueKey('record-done')), findsOneWidget);
        expect(find.byKey(const ValueKey('record-share')), findsOneWidget);
        expect(
          rig.events(AnalyticsEventName.onboardingStepViewed),
          contains(allOf(contains('on_record'), contains('pushLive: false'))),
        );
      },
    );

    testWidgets(
      'push live, not allowed: one card; exactly one dialog on Notify me',
      (tester) async {
        final rig = await lockOne(tester, pushLive: true);
        expect(
          find.byKey(const ValueKey('record-notify-card')),
          findsOneWidget,
        );
        expect(find.text(OnboardingCopy.notifyBody), findsOneWidget);
        expect(rig.permission.requests, 0, reason: 'nothing before the tap');
        await tester.tap(find.byKey(const ValueKey('record-notify')));
        await settle(tester);
        expect(rig.permission.requests, 1);
        expect(rig.permission.registered, isNotEmpty);
        expect(find.byKey(const ValueKey('record-notify-card')), findsNothing);
        expect(find.text(OnboardingCopy.recordPushOn), findsOneWidget);
        expect(
          rig.events(AnalyticsEventName.notificationPermissionResult).single,
          allOf(contains('granted'), contains('system')),
        );
      },
    );

    testWidgets('"Not now" asks nothing and is remembered for two weeks', (
      tester,
    ) async {
      final rig = await lockOne(tester, pushLive: true);
      await tester.tap(find.byKey(const ValueKey('record-not-now')));
      await settle(tester);
      expect(rig.permission.requests, 0);
      expect(find.byKey(const ValueKey('record-done')), findsOneWidget);
    });

    testWidgets('already allowed (Android 12 and older): no card, registered', (
      tester,
    ) async {
      final rig = await lockOne(tester, pushLive: true, permitted: true);
      expect(find.byKey(const ValueKey('record-notify-card')), findsNothing);
      expect(find.text(OnboardingCopy.recordPushOn), findsOneWidget);
      expect(rig.permission.requests, 0);
      expect(rig.permission.registered, isNotEmpty);
    });

    testWidgets('reduced motion: a static check, not the animation', (
      tester,
    ) async {
      await lockOne(tester, pushLive: false, reduceMotion: true);
      expect(
        find.byWidgetPredicate(
          (w) => w is BasilIcon && w.icon == 'check-solid',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Done, or system Back, goes Home; never back to the composer', (
      tester,
    ) async {
      final rig = await lockOne(tester, pushLive: false);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(rig.exits, [FlowExit.home]);
      expect(rig.app.record.status.wire, 'completed');
      expect(
        rig.events(AnalyticsEventName.onboardingCompleted).single,
        contains('madeCall: true'),
      );
    });
  });
}
