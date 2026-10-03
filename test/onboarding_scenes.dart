/// A realistic, synthetic scene for onboarding tests and captures: Panta-
/// shaped markets in four categories, three callers (one with only a
/// placeholder handle), live top calls with fresh prices. Test-only — the
/// app has no way to reach any of it.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';

import 'onboarding_fakes.dart';

class OnboardingScene {
  OnboardingScene() {
    btc = pantaMarket(
      uuid(1),
      question: 'Will Bitcoin close above \$125,000 on 9 October?',
      category: 'crypto',
      closesIn: const Duration(days: 4, hours: 3),
    );
    eth = pantaMarket(
      uuid(2),
      question: 'Will Ethereum trade above \$5,000 before 1 November?',
      category: 'crypto',
      closesIn: const Duration(days: 29),
    );
    album = pantaMarket(
      uuid(3),
      question: 'Will Taylor Swift announce a new album before 1 November?',
      category: 'pop-culture',
      closesIn: const Duration(days: 6),
    );
    lakers = pantaMarket(
      uuid(4),
      question: 'Will the Lakers win their season opener?',
      category: 'sports',
      closesIn: const Duration(days: 3, hours: 5),
    );
    gta = pantaMarket(
      uuid(5),
      question: 'Will GTA VI keep its announced release date?',
      category: 'gaming',
      closesIn: const Duration(days: 12),
    );
    soon = pantaMarket(
      uuid(6),
      question: 'Will SOL close above \$240 today?',
      category: 'crypto',
      closesIn: const Duration(minutes: 20),
    );
    stale = pantaMarket(
      uuid(7),
      question: 'Will gold close above \$4,000 this week?',
      category: 'commodities',
      closesIn: const Duration(days: 5),
    );
    // Labelled OPEN by the venue, but its close has passed (the 30 Sep row).
    closedButOpen = pantaMarket(
      uuid(8),
      question: 'Will ETH be above \$4,500 on 30 September?',
      category: 'finance',
      closesIn: const Duration(days: -2),
    );

    ada = personCard(
      'user-ada',
      name: 'Ada Okafor',
      handle: 'ada',
      rec: record(correct: 8, decided: 10, pending: 1),
    );
    kemi = personCard(
      'user-kemi',
      name: 'Kemi Bello',
      handle: 'user-80d78065',
      rec: record(pending: 2),
    );
    tunde = personCard(
      'user-tunde',
      name: 'Tunde Adeyemi',
      handle: 'tunde',
      rec: record(correct: 2, decided: 3, pending: 1),
    );

    adaBtc = topCall(
      btc,
      ada,
      side: Side.yes,
      responses: 4,
      thesis: 'ETF inflows keep stacking and the funding rate is calm.',
    );
    kemiAlbum = topCall(album, kemi, side: Side.no, responses: 2);
    tundeLakers = topCall(lakers, tunde, side: Side.yes, responses: 1);
  }

  late final VenueMarket btc, eth, album, lakers, gta, soon, stale;
  late final VenueMarket closedButOpen;
  late final PersonCard ada, kemi, tunde;
  late final TopCall adaBtc, kemiAlbum, tundeLakers;

  List<VenueMarket> get catalog => [
    btc,
    eth,
    album,
    lakers,
    gta,
    soon,
    stale,
    closedButOpen,
  ];

  Map<String, SharePriceSnapshot> get prices => {
    btc.id: priceFor(btc.id, yes: '0.38', no: '0.63'),
    eth.id: priceFor(eth.id, yes: '0.21', no: '0.80'),
    album.id: priceFor(album.id, yes: '0.44', no: '0.57'),
    lakers.id: priceFor(lakers.id, yes: '0.55', no: '0.46'),
    gta.id: priceFor(gta.id, yes: '0.71', no: '0.30'),
    soon.id: priceFor(soon.id),
    // Fifteen minutes old: too old to call at.
    stale.id: priceFor(stale.id, age: const Duration(minutes: 15)),
  };

  PeopleSuggestions get suggestions => PeopleSuggestions(
    friends: const [],
    people: [
      suggestion(ada, reason: SuggestionReason.ranked, latest: adaBtc),
      suggestion(kemi, reason: SuggestionReason.topCall, latest: kemiAlbum),
      suggestion(tunde, reason: SuggestionReason.building, latest: tundeLakers),
    ],
    servedAt: kNowMs,
  );

  FakeOnboardingRepository repository({
    bool withTop = true,
    bool withSuggestions = true,
  }) => FakeOnboardingRepository(
    catalog: catalog,
    prices: prices,
    top: withTop ? [adaBtc, kemiAlbum, tundeLakers] : const [],
    suggestions: withSuggestions ? suggestions : null,
  );

  CallFeedEntry feedEntry(TopCall t) => entryFor(t);

  static CallFeedEntry entryFor(TopCall t) => CallFeedEntry(
    call: t.call,
    author: Person(
      id: t.author.id,
      handle: t.author.handle,
      displayName: t.author.displayName,
    ),
    market: t.market,
  );
}
