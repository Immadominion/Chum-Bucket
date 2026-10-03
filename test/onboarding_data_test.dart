// The real-data rules behind each optional step (onboarding spec §4.3–§4.6,
// §6): what counts as open, what is shown, in what order, and that nothing
// the server did not return can reach a screen.
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/username_suggestions.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';

CallFeedEntry _entry(
  TopCall t, {
  CallVisibility visibility = CallVisibility.public,
}) => CallFeedEntry(
  call: Call(
    id: t.call.id,
    userId: t.call.userId,
    marketId: t.call.marketId,
    side: t.call.side,
    confidence: null,
    thesis: null,
    entryProbability: null,
    snapshotId: null,
    visibility: visibility,
    createdAt: t.call.createdAt,
    lockedAt: t.call.lockedAt,
    parentCallId: null,
    fundingState: FundingState.none,
  ),
  author: Person(
    id: t.author.id,
    handle: t.author.handle,
    displayName: t.author.displayName,
  ),
  market: t.market,
);

/// A call on a market that has closed, with the result the server derived
/// ([outcome] null: no result published yet).
CallFeedEntry _settled(
  String id,
  PersonCard author, {
  CallOutcome? outcome = CallOutcome.correct,
  MarketVenue venue = MarketVenue.panta,
  CallVisibility visibility = CallVisibility.public,
}) {
  final market = pantaMarket(
    'closed-$id',
    question: 'Did $id happen?',
    closesIn: const Duration(days: -1),
    status: MarketStatus.resolved,
    venue: venue,
  );
  final e = _entry(topCall(market, author), visibility: visibility);
  return CallFeedEntry(
    call: e.call,
    author: e.author,
    market: market,
    result:
        outcome == null
            ? null
            : CallResult(
              callId: e.call.id,
              outcome: outcome,
              resolution: null,
              resolvedAt: kNowMs - 3600000,
              marketResolutionId: null,
              derivedAt: kNowMs - 3600000,
            ),
  );
}

void main() {
  final s = OnboardingScene();

  group('display rules (§4.5)', () {
    test('a placeholder handle is never shown', () {
      expect(visibleHandle('user-80d78065'), isNull);
      expect(visibleHandle('@user-80d78065'), isNull);
      expect(visibleHandle('ada'), 'ada');
      expect(visibleHandle('@ada'), 'ada');
      expect(visibleHandle(''), isNull);
      expect(visibleHandle(null), isNull);
      // Only the exact placeholder shape: a real handle that merely starts
      // the same way stays.
      expect(visibleHandle('user-ada'), 'user-ada');
    });

    test('a person with neither a name nor a real handle is left out', () {
      expect(
        isShowablePerson(displayName: '', handle: 'user-80d78065'),
        isFalse,
      );
      // The BFF's own fallback for a name-less, handle-less account
      // (`personFromRow`: displayName = full_name ?? handle): the "name" is
      // the placeholder, which is no name at all.
      expect(
        isShowablePerson(displayName: 'user-80d78065', handle: 'user-80d78065'),
        isFalse,
      );
      expect(visibleDisplayName('user-80d78065'), isNull);
      expect(visibleDisplayName(' Kemi '), 'Kemi');
      expect(shownName(displayName: 'user-80d78065', handle: 'ada'), '@ada');
      expect(
        isShowablePerson(displayName: 'Kemi', handle: 'user-80d78065'),
        isTrue,
      );
      expect(isShowablePerson(displayName: ' ', handle: 'ada'), isTrue);
      expect(shownName(displayName: '', handle: 'ada'), '@ada');
      expect(
        shownName(displayName: 'Kemi Bello', handle: 'user-1'),
        'Kemi Bello',
      );
    });

    test('avatars: their picture or chosen avatar, else initials', () {
      expect(OnbAvatar.initialsOf('Ada Okafor'), 'AO');
      expect(OnbAvatar.initialsOf('kemi'), 'K');
      expect(OnbAvatar.initialsOf('@tunde'), 'T');
      expect(OnbAvatar.initialsOf('  '), '?');
      // A person card carries the avatar the person chose.
      final card = PersonCard.fromJson({
        'id': 'u-1',
        'handle': 'ada',
        'displayName': 'Ada',
        'avatarUrl': null,
        'avatarId': 3,
        'record': {
          'counts': {
            'correct': 0,
            'incorrect': 0,
            'voided': 0,
            'decided': 0,
            'pending': 1,
          },
          'display': {'mode': 'counts', 'minimumDecided': 10},
        },
        'viewerIsFollowing': false,
      });
      expect(card.avatarUrl, 'assets/images/ai_gen/profile_images/3.png');
    });
  });

  group('open and call-ready markets (§4.3)', () {
    test('OPEN after its close time is not open (the 30 Sep ETH row)', () {
      expect(s.closedButOpen.status, MarketStatus.open);
      expect(isLiveOpenMarket(s.closedButOpen, kNow), isFalse);
      expect(isLiveOpenMarket(s.btc, kNow), isTrue);
    });

    test('demo, paused, closed or not-yet-open markets are not open', () {
      expect(
        isLiveOpenMarket(pantaMarket('d', venue: MarketVenue.fixture), kNow),
        isFalse,
      );
      expect(
        isLiveOpenMarket(pantaMarket('p', status: MarketStatus.paused), kNow),
        isFalse,
      );
      expect(
        isLiveOpenMarket(
          pantaMarket('c', status: MarketStatus.closedPendingResolution),
          kNow,
        ),
        isFalse,
      );
    });

    test('a first call needs more than 30 minutes before the close', () {
      expect(isCallReadyMarket(s.soon, kNow), isFalse); // 20 minutes
      expect(
        isCallReadyMarket(
          pantaMarket('m31', closesIn: const Duration(minutes: 31)),
          kNow,
        ),
        isTrue,
      );
    });
  });

  group('Topics (T)', () {
    test('counts are the open markets per category, closed ones excluded', () {
      final topics = topicsFrom(s.catalog, kNow);
      expect(topics, const [
        TopicCount('crypto', 3),
        TopicCount('commodities', 1),
        TopicCount('gaming', 1),
        TopicCount('pop-culture', 1),
        TopicCount('sports', 1),
      ]);
      // The 30 Sep row's category has no open market, so no chip.
      expect(topics.map((t) => t.slug), isNot(contains('finance')));
      final total = topics.fold<int>(0, (n, t) => n + t.openCount);
      expect(total, s.catalog.where((m) => isLiveOpenMarket(m, kNow)).length);
    });

    test('shown only with at least two categories that have open markets', () {
      expect(topicsWorthShowing(topicsFrom([s.btc, s.eth], kNow)), isFalse);
      expect(topicsWorthShowing(topicsFrom([s.btc, s.lakers], kNow)), isTrue);
      expect(topicsWorthShowing(const []), isFalse);
    });

    test('labels and icons are the Markets tab\'s vocabulary (§4.6)', () {
      expect(marketCategoryLabel('pop-culture'), 'Pop culture');
      expect(marketCategoryLabel('crypto'), 'Crypto');
      expect(marketCategoryLabel('some-new_thing'), 'Some new thing');
      expect(MarketGlyph.categoryIcon('crypto'), 'lightning-outline');
      expect(MarketGlyph.categoryIcon('unheard-of'), isNotEmpty);
      expect(
        OnboardingCopy.topicChipA11y('Sports', 1),
        'Sports, 1 open market',
      );
      expect(
        OnboardingCopy.topicChipA11y('Crypto', 3),
        'Crypto, 3 open markets',
      );
    });
  });

  group('First call (C)', () {
    test('chosen topics first, then the soonest to close; >30 min only', () {
      final ranked = firstCallCandidates(
        s.catalog,
        topics: {'sports'},
        now: kNow,
      );
      expect(ranked.first, s.lakers);
      expect(ranked, isNot(contains(s.soon)));
      expect(ranked, isNot(contains(s.closedButOpen)));
      final rest = ranked.skip(1).map((m) => m.closesAt!).toList();
      expect(rest, [...rest]..sort());
      // No topics: soonest first.
      expect(
        firstCallCandidates(s.catalog, topics: const {}, now: kNow).first,
        s.lakers,
      );
    });

    test(
      'answerable calls: others\' live public calls, people chosen first',
      () {
        final followersOnly = TopCall(
          call: call(
            'f',
            userId: 'user-zed',
            marketId: s.gta.id,
          ).copyWithVisibility(CallVisibility.followers),
          author: personCard('user-zed', name: 'Zed'),
          market: s.gta,
          responses: 9,
        );
        final mine = topCall(s.eth, personCard('me', name: 'Me'));
        final nameless = topCall(
          s.album,
          personCard('anon', name: '', handle: 'user-0000abcd'),
        );
        final rows = answerableCalls(
          [s.adaBtc, s.kemiAlbum, s.tundeLakers, followersOnly, mine, nameless],
          viewerUserId: 'me',
          preferredAuthors: {'user-tunde'},
          now: kNow,
        );
        expect(rows.map((t) => t.author.id), ['user-tunde', 'user-ada']);
        expect(rows.length, kAnswerableCalls);
      },
    );
  });

  group('Welcome\'s live strip (W1)', () {
    test('top calls first', () {
      final strip = chooseLiveStrip(
        top: [s.adaBtc, s.kemiAlbum],
        feed: [s.feedEntry(s.tundeLakers)],
        markets: s.catalog,
        now: kNow,
      );
      expect(strip.source, LiveStripSource.top);
      expect(strip.items, hasLength(2));
    });

    test('else the global feed, public calls on open markets only', () {
      final closedCall = topCall(s.closedButOpen, s.ada);
      final strip = chooseLiveStrip(
        top: const [],
        feed: [
          _entry(s.adaBtc),
          _entry(s.kemiAlbum, visibility: CallVisibility.followers),
          _entry(closedCall),
          _entry(s.adaBtc), // the same call twice
        ],
        markets: s.catalog,
        now: kNow,
      );
      expect(strip.source, LiveStripSource.feed);
      expect(strip.items.map((i) => (i as LiveCallItem).entry.call.id), [
        s.adaBtc.call.id,
      ]);
    });

    test('else up to three markets open on Panta, soonest first', () {
      final strip = chooseLiveStrip(
        top: const [],
        feed: const [],
        markets: s.catalog,
        now: kNow,
      );
      expect(strip.source, LiveStripSource.markets);
      expect(strip.items, hasLength(kLiveStripMarkets));
      expect((strip.items.first as LiveMarketItem).market, s.soon);
    });

    test('else nothing at all — never a fixture', () {
      final strip = chooseLiveStrip(
        top: const [],
        feed: const [],
        markets: [pantaMarket('demo', venue: MarketVenue.fixture)],
        now: kNow,
      );
      expect(strip.source, LiveStripSource.none);
      expect(strip.isEmpty, isTrue);
    });

    test('a demo item can never reach the strip from any source', () {
      final demoMarket = pantaMarket('demo', venue: MarketVenue.fixture);
      final demoCall = topCall(demoMarket, s.ada);
      final strip = chooseLiveStrip(
        top: [demoCall],
        feed: [_entry(demoCall)],
        markets: [demoMarket],
        now: kNow,
      );
      expect(strip.isEmpty, isTrue);
    });

    test('a caller known only by a placeholder never reaches the strip', () {
      // What the BFF sends for an account with no name and no handle.
      final nameless = personCard(
        'u-nameless',
        name: 'user-80d78065',
        handle: 'user-80d78065',
      );
      final strip = chooseLiveStrip(
        top: [topCall(s.btc, nameless)],
        feed: const [],
        markets: const [],
        now: kNow,
      );
      expect(strip.isEmpty, isTrue);
    });

    test('a source that has not answered is skipped, not treated as empty', () {
      expect(
        chooseLiveStrip(
          top: null,
          feed: null,
          markets: [s.btc],
          now: kNow,
        ).source,
        LiveStripSource.markets,
      );
    });
  });

  group('Welcome\'s phone (W1)', () {
    List<String> ids(WelcomeFeed feed) => [
      for (final item in feed.items)
        switch (item) {
          LiveCallItem(:final entry) => entry.call.id,
          LiveMarketItem(:final market) => market.id,
        },
    ];

    test('people\'s live calls first, then settled ones with their result', () {
      final won = _settled('won', s.tunde);
      final lost = _settled('lost', s.kemi, outcome: CallOutcome.incorrect);
      final feed = chooseWelcomeFeed(
        top: [s.adaBtc],
        // Settled rows come first from the server; live ones still lead.
        feed: [won, lost, _entry(s.kemiAlbum)],
        markets: const [],
        now: kNow,
      );
      expect(ids(feed), [
        s.adaBtc.call.id,
        s.kemiAlbum.call.id,
        won.call.id,
        lost.call.id,
      ]);
      expect(feed.hasCalls, isTrue);
      expect(feed.source, 'calls');
    });

    test('only public calls, by people with a real name or handle', () {
      // What the BFF sends for an account with no name and no handle.
      final nameless = personCard(
        'u-nameless',
        name: 'user-80d78065',
        handle: 'user-80d78065',
      );
      final feed = chooseWelcomeFeed(
        top: [topCall(s.btc, nameless)],
        feed: [
          _entry(s.tundeLakers, visibility: CallVisibility.followers),
          _settled('hidden', s.ada, visibility: CallVisibility.followers),
          _settled('anon', nameless),
          // Kemi's handle is a placeholder, but her name is real.
          _entry(s.kemiAlbum),
        ],
        markets: const [],
        now: kNow,
      );
      expect(ids(feed), [s.kemiAlbum.call.id]);
    });

    test('a call on a closed market shows only once its result is in', () {
      final feed = chooseWelcomeFeed(
        top: const [],
        feed: [
          _settled('pending', s.ada, outcome: CallOutcome.pending),
          _settled('unresolved', s.tunde, outcome: null),
          // Labelled OPEN by the venue, but its close has passed.
          _entry(topCall(s.closedButOpen, s.kemi)),
        ],
        markets: const [],
        now: kNow,
      );
      expect(feed.isEmpty, isTrue);
    });

    test('markets open on Panta fill the phone to five, soonest first', () {
      final withCalls = chooseWelcomeFeed(
        top: [s.adaBtc, s.kemiAlbum],
        feed: const [],
        markets: s.catalog,
        now: kNow,
      );
      expect(withCalls.items, hasLength(kWelcomeFeedTarget));
      expect(ids(withCalls).take(2), [s.adaBtc.call.id, s.kemiAlbum.call.id]);
      expect(ids(withCalls).skip(2), [s.soon.id, s.lakers.id, s.btc.id]);

      final marketsOnly = chooseWelcomeFeed(
        top: const [],
        feed: const [],
        markets: s.catalog,
        now: kNow,
      );
      // The 30 Sep market the venue still calls OPEN never fills a slot.
      expect(ids(marketsOnly), [
        s.soon.id,
        s.lakers.id,
        s.btc.id,
        s.stale.id,
        s.album.id,
      ]);
      expect(marketsOnly.hasCalls, isFalse);
      expect(marketsOnly.source, 'markets');
    });

    test('the same call from two sources shows once', () {
      final feed = chooseWelcomeFeed(
        top: [s.adaBtc],
        feed: [_entry(s.adaBtc), _entry(s.adaBtc)],
        markets: const [],
        now: kNow,
      );
      expect(ids(feed), [s.adaBtc.call.id]);
    });

    test('nothing anywhere: empty, never a fixture', () {
      for (final feed in [
        chooseWelcomeFeed(
          top: const [],
          feed: const [],
          markets: const [],
          now: kNow,
        ),
        chooseWelcomeFeed(now: kNow),
        chooseWelcomeFeed(
          top: const [],
          feed: const [],
          markets: [pantaMarket('demo', venue: MarketVenue.fixture)],
          now: kNow,
        ),
      ]) {
        expect(feed.isEmpty, isTrue);
        expect(feed.hasCalls, isFalse);
        expect(feed.source, 'none');
      }
    });

    test('a demo row never reaches the phone, live or settled', () {
      final demoMarket = pantaMarket('demo', venue: MarketVenue.fixture);
      final demoCall = topCall(demoMarket, s.ada);
      final feed = chooseWelcomeFeed(
        top: [demoCall],
        feed: [
          _entry(demoCall),
          _settled('demo', s.tunde, venue: MarketVenue.fixture),
        ],
        markets: [demoMarket],
        now: kNow,
      );
      expect(feed.isEmpty, isTrue);
    });

    test('a source that has not answered is skipped, not treated as empty', () {
      final feed = chooseWelcomeFeed(markets: [s.btc], now: kNow);
      expect(feed.source, 'markets');
      expect(ids(feed), [s.btc.id]);
    });
  });

  group('People (P)', () {
    test('the record line says what the record shows, and only that', () {
      String line(PublicRecord r) => recordLine(
        r,
        accuracy: OnboardingCopy.recordAccuracy,
        building: OnboardingCopy.recordBuilding,
        open: OnboardingCopy.recordOpen,
        none: OnboardingCopy.recordNone,
      );
      expect(line(record(correct: 8, decided: 10)), '8 of 10 called right');
      expect(
        line(record(correct: 2, decided: 3)),
        '3 settled · building a record',
      );
      expect(line(record(pending: 1)), '1 open call');
      expect(line(record(pending: 2)), '2 open calls');
      expect(line(record()), 'No calls yet');
    });

    test('shown with two real callers, or one friend', () {
      expect(peopleWorthShowing(suggestions: 1, friends: 0), isFalse);
      expect(peopleWorthShowing(suggestions: 2, friends: 0), isTrue);
      expect(peopleWorthShowing(suggestions: 0, friends: 1), isTrue);
    });

    test(
      'composed suggestions: real callers only, ranked then top then building',
      () {
        final silent = personCard('user-silent', name: 'Quiet', rec: record());
        final followed = personCard('user-f', name: 'F', following: true);
        final board = Leaderboard(
          window: LeaderboardWindow.all,
          ranked: [LeaderboardRow(rank: 1, person: s.ada)],
          building: [
            LeaderboardRow(rank: null, person: s.tunde),
            LeaderboardRow(rank: null, person: silent),
            LeaderboardRow(rank: null, person: followed),
          ],
          minimumDecided: 10,
          rule: 'Ranked by record.',
          servedAt: kNowMs,
        );
        final out = composeSuggestions(
          allTime: board,
          top: [s.kemiAlbum, s.adaBtc],
          viewerUserId: 'me',
          now: kNow,
        );
        expect(out.map((p) => (p.id, p.reason)), [
          ('user-ada', SuggestionReason.ranked),
          ('user-kemi', SuggestionReason.topCall),
          ('user-tunde', SuggestionReason.building),
        ]);
        expect(out.first.latestLiveCall?.callId, s.adaBtc.call.id);
        // The viewer is never suggested to themselves.
        expect(
          composeSuggestions(
            allTime: board,
            viewerUserId: 'user-ada',
            now: kNow,
          ).map((p) => p.id),
          isNot(contains('user-ada')),
        );
      },
    );

    test('an empty server answers an empty list', () {
      expect(composeSuggestions(viewerUserId: null, now: kNow), isEmpty);
    });
  });

  group('username suggestions (A2): from what the person already gave', () {
    test('X first, then the wallet name, then the Google name', () {
      final x = ProfileHints.fromMetadata(
        userMetadata: {'user_name': 'Ada_Calls', 'full_name': 'Ada Okafor'},
        appMetadata: {'provider': 'twitter'},
      );
      expect(usernameCandidates(hints: x, walletDomain: 'dominion.sol'), const [
        UsernameSuggestion('ada_calls', UsernameSuggestionSource.x),
        UsernameSuggestion(
          'dominion',
          UsernameSuggestionSource.domain,
          domain: 'dominion.sol',
        ),
      ]);
      final google = ProfileHints.fromMetadata(
        userMetadata: {
          'full_name': 'Ada Okafor',
          'given_name': 'Ada',
          'family_name': 'Okafor',
        },
        appMetadata: {'provider': 'google'},
      );
      expect(usernameCandidates(hints: google), const [
        UsernameSuggestion('adao', UsernameSuggestionSource.google),
      ]);
      expect(nameSuggestion(google), 'Ada Okafor');
    });

    test('sanitised to 3–20 of a-z, 0-9 and _, or not suggested at all', () {
      expect(sanitizeHandle('@Ada.Okafor-99'), 'ada_okafor_99');
      expect(sanitizeHandle('ab'), isNull);
      expect(sanitizeHandle('ádá'), isNull);
      expect(sanitizeHandle('a' * 30), 'a' * 20);
      expect(domainLabel('ada.skr'), 'ada');
      expect(domainLabel('ada.eth'), isNull);
      expect(domainLabel('sub.ada.sol'), isNull);
      // No hints, no wallet name: nothing is guessed.
      expect(usernameCandidates(), isEmpty);
      expect(nameSuggestion(null), isNull);
    });
  });

  group('Home arrival and Markets "For you"', () {
    test('Following only with follows and a call to show; else Global', () {
      expect(
        homeArrivalMode(followed: 2, followingFeedEntries: 0),
        CallFeedMode.global,
      );
      expect(
        homeArrivalMode(followed: 0, followingFeedEntries: 4),
        CallFeedMode.global,
      );
      expect(
        homeArrivalMode(followed: 1, followingFeedEntries: 1),
        CallFeedMode.following,
      );
    });

    test('chosen topics first, nothing hidden, nothing else reordered', () {
      final rows = [s.btc, s.lakers, s.album, s.eth];
      final split = forYouOrder(rows, {'sports', 'pop-culture'});
      expect(split.chosen, [s.lakers, s.album]);
      expect(split.more, [s.btc, s.eth]);
      expect(
        topCallsForTopics([s.adaBtc, s.kemiAlbum, s.tundeLakers], {'sports'}),
        [s.tundeLakers, s.adaBtc, s.kemiAlbum],
      );
      expect(topCallsForTopics([s.adaBtc, s.kemiAlbum], const {}), [
        s.adaBtc,
        s.kemiAlbum,
      ]);
    });
  });
}

extension on Call {
  Call copyWithVisibility(CallVisibility visibility) => Call(
    id: id,
    userId: userId,
    marketId: marketId,
    side: side,
    confidence: confidence,
    thesis: thesis,
    entryProbability: entryProbability,
    snapshotId: snapshotId,
    visibility: visibility,
    createdAt: createdAt,
    lockedAt: lockedAt,
    parentCallId: parentCallId,
    fundingState: fundingState,
  );
}
