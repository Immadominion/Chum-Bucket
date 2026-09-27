import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FROZEN vocabulary wire values', () {
    test('every enum uses the contract\'s exact wire strings', () {
      expect(Side.values.map((e) => e.wire), ['YES', 'NO']);
      expect(Resolution.values.map((e) => e.wire), ['YES', 'NO', 'VOID']);
      expect(MarketStatus.values.map((e) => e.wire), [
        'OPEN',
        'CLOSED_PENDING_RESOLUTION',
        'RESOLVED',
        'CANCELLED',
        'PAUSED',
      ]);
      expect(CallOutcome.values.map((e) => e.wire), [
        'PENDING',
        'CORRECT',
        'INCORRECT',
        'VOID',
      ]);
      expect(FundingState.values.map((e) => e.wire), [
        'NONE',
        'QUOTED',
        'SUBMITTED',
        'FILLED',
        'PARTIAL',
        'FAILED',
        'CLOSED',
        'CLAIMABLE',
        'CLAIMED',
      ]);
    });

    test('an unknown wire value fails loudly instead of being coerced', () {
      expect(() => Side.fromWire('MAYBE'), throwsA(isA<CallVocabularyException>()));
      expect(
        () => MarketStatus.fromWire('CLOSED'),
        throwsA(isA<CallVocabularyException>()),
      );
      expect(
        () => MarketVenue.fromWire('unknown-venue'),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('FILLED is the only funding state whose label reads "Funded"', () {
      final funded =
          FundingState.values
              .where((s) => s.label.toLowerCase().contains('funded'))
              .toList();
      // SUBMITTED reads "not funded yet", which is the whole point, so the
      // check is on the state that claims money IS in.
      expect(funded, contains(FundingState.filled));
      expect(FundingState.filled.label, 'Funded');
      expect(FundingState.submitted.isFunded, isFalse);
      expect(FundingState.claimed.isFunded, isFalse);
      expect(
        FundingState.values.where((s) => s.isFunded).toList(),
        [FundingState.filled],
      );
    });

    test('free/funded/pending/resolved/void labels are all distinct', () {
      final labels = <String>{
        FundingState.none.label,
        FundingState.filled.label,
        CallOutcome.pending.label,
        MarketStatus.resolved.label,
        CallOutcome.voided.label,
      };
      expect(labels.length, 5);
    });

    test('the five market statuses never collapse into one another', () {
      final labels = MarketStatus.values.map((s) => s.label).toSet();
      expect(labels.length, MarketStatus.values.length);
      expect(MarketStatus.cancelled.isVoid, isTrue);
      expect(MarketStatus.resolved.isVoid, isFalse);
      expect(MarketStatus.closedPendingResolution.isVoid, isFalse);
      expect(
        MarketStatus.values.where((s) => s.acceptsNewCalls).toList(),
        [MarketStatus.open],
      );
    });
  });

  group('deriveCallOutcome — the only permitted rule', () {
    test('no resolution yet is PENDING for both sides', () {
      expect(
        deriveCallOutcome(side: Side.yes, resolution: null),
        CallOutcome.pending,
      );
      expect(
        deriveCallOutcome(side: Side.no, resolution: null),
        CallOutcome.pending,
      );
    });

    test('VOID is VOID for both sides — never a win, never a loss', () {
      expect(
        deriveCallOutcome(side: Side.yes, resolution: Resolution.voided),
        CallOutcome.voided,
      );
      expect(
        deriveCallOutcome(side: Side.no, resolution: Resolution.voided),
        CallOutcome.voided,
      );
    });

    test('matching side is CORRECT, the other side is INCORRECT', () {
      expect(
        deriveCallOutcome(side: Side.yes, resolution: Resolution.yes),
        CallOutcome.correct,
      );
      expect(
        deriveCallOutcome(side: Side.no, resolution: Resolution.no),
        CallOutcome.correct,
      );
      expect(
        deriveCallOutcome(side: Side.yes, resolution: Resolution.no),
        CallOutcome.incorrect,
      );
      expect(
        deriveCallOutcome(side: Side.no, resolution: Resolution.yes),
        CallOutcome.incorrect,
      );
    });

    test('the rule has exactly four branches and no fifth', () {
      final produced = <CallOutcome>{};
      for (final side in Side.values) {
        for (final resolution in [null, ...Resolution.values]) {
          produced.add(deriveCallOutcome(side: side, resolution: resolution));
        }
      }
      expect(produced, CallOutcome.values.toSet());
    });
  });

  group('JSON round trips keep the contract field names', () {
    final marketJson = <String, dynamic>{
      'id': 'market_1',
      'venue': 'jupiter',
      'venueEventId': 'evt_1',
      'venueMarketId': 'jup:raw-id-preserved',
      'question': 'Will it?',
      'rulesText': 'Resolves YES if it does.',
      'category': 'crypto',
      'outcomes': [
        {'side': 'YES', 'label': 'Yes'},
        {'side': 'NO', 'label': 'No'},
      ],
      'status': 'OPEN',
      'rawStatus': 'active',
      'opensAt': 1757000000000,
      'closesAt': 1757600000000,
      'resolvesAt': null,
      'resolutionSource': 'A feed',
      'lastSyncedAt': 1757100000000,
      'payloadVersion': 3,
    };

    test('VenueMarket round trips and preserves venueMarketId verbatim', () {
      final market = VenueMarket.fromJson(marketJson);
      expect(market.venueMarketId, 'jup:raw-id-preserved');
      expect(market.payloadVersion, 3);
      expect(market.resolvesAt, isNull);
      expect(market.toJson(), marketJson);
    });

    test('Call round trips with every optional field null', () {
      final json = <String, dynamic>{
        'id': 'call_1',
        'userId': 'user_1',
        'marketId': 'market_1',
        'side': 'NO',
        'confidence': null,
        'thesis': null,
        'entryProbability': null,
        'snapshotId': null,
        'visibility': 'public',
        'createdAt': 1757100000000,
        'lockedAt': 1757100000000,
        'parentCallId': null,
        'fundingState': 'NONE',
      };
      final call = Call.fromJson(json);
      expect(call.side, Side.no);
      expect(call.fundingState.isFree, isTrue);
      expect(call.toJson(), json);
    });

    test('CallResponse and CallResult round trip', () {
      final responseJson = <String, dynamic>{
        'id': 'response_1',
        'actorUserId': 'user_2',
        'targetCallId': 'call_1',
        'kind': 'fade',
        'resultingCallId': 'call_2',
        'createdAt': 1757100000000,
      };
      expect(CallResponse.fromJson(responseJson).toJson(), responseJson);

      final resultJson = <String, dynamic>{
        'callId': 'call_1',
        'outcome': 'VOID',
        'resolution': 'VOID',
        'resolvedAt': 1757200000000,
        'marketResolutionId': 'res_1',
        'derivedAt': 1757200001000,
      };
      expect(CallResult.fromJson(resultJson).toJson(), resultJson);
    });

    test('timestamps must be unix milliseconds, not ISO strings', () {
      expect(
        () => MarketSnapshot.fromJson({
          'marketId': 'market_1',
          'yesProbability': 0.5,
          'observedAt': '2026-09-13T00:00:00.000Z',
          'source': 'venue',
        }),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('probabilities outside [0,1] are rejected, not clamped', () {
      for (final bad in [1.5, -0.1]) {
        expect(
          () => MarketSnapshot.fromJson({
            'marketId': 'market_1',
            'yesProbability': bad,
            'observedAt': 1757100000000,
            'source': 'venue',
          }),
          throwsA(isA<CallVocabularyException>()),
          reason: '$bad must be refused',
        );
      }
    });

    test('a thesis over 280 chars is rejected', () {
      expect(
        () => Call.fromJson({
          'id': 'call_1',
          'userId': 'user_1',
          'marketId': 'market_1',
          'side': 'YES',
          'confidence': null,
          'thesis': 'x' * (kThesisMaxLength + 1),
          'entryProbability': null,
          'snapshotId': null,
          'visibility': 'public',
          'createdAt': 1757100000000,
          'lockedAt': 1757100000000,
          'parentCallId': null,
          'fundingState': 'NONE',
        }),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('no model in the vocabulary carries a money field', () {
      // Money is an integer base-unit STRING on the wire and never a double.
      // The MVP's free call carries no amount at all, so the guarantee we can
      // actually assert is that nothing money-shaped exists to leak.
      final call = Call.fromJson({
        'id': 'call_1',
        'userId': 'user_1',
        'marketId': 'market_1',
        'side': 'YES',
        'confidence': 0.5,
        'thesis': null,
        'entryProbability': 0.4,
        'snapshotId': null,
        'visibility': 'public',
        'createdAt': 1757100000000,
        'lockedAt': 1757100000000,
        'parentCallId': null,
        'fundingState': 'NONE',
      });
      final keys = call.toJson().keys.map((k) => k.toLowerCase());
      for (final forbidden in ['amount', 'stake', 'size', 'lamports', 'usdc']) {
        expect(
          keys.any((k) => k.contains(forbidden)),
          isFalse,
          reason: 'Call must not carry a "$forbidden" field',
        );
      }
    });
  });

  group('MarketSnapshot helpers', () {
    test('noProbability complements yesProbability', () {
      final snapshot = MarketSnapshot.fromJson({
        'marketId': 'market_1',
        'yesProbability': 0.38,
        'observedAt': 1757100000000,
        'source': 'venue',
      });
      expect(snapshot.probabilityFor(Side.yes), closeTo(0.38, 1e-9));
      expect(snapshot.probabilityFor(Side.no), closeTo(0.62, 1e-9));
    });

    test('age is never negative for a future observation', () {
      final now = DateTime.utc(2026, 9, 13, 12);
      final snapshot = MarketSnapshot(
        marketId: 'market_1',
        yesProbability: 0.5,
        observedAt: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        source: SnapshotSource.venue,
      );
      expect(snapshot.ageAt(now), Duration.zero);
    });
  });

  group('ArenaBucketIndex YES/NO generalisation', () {
    test('YES and NO map onto the two low bucket indices', () {
      expect(ArenaBucketIndex.fromLabel('YES'), 0);
      expect(ArenaBucketIndex.fromLabel('NO'), 1);
      expect(ArenaBucketIndex.fromLabel('yes'), 0);
      expect(ArenaBucketIndex.fromLabel('no'), 1);
      expect(ArenaBucketIndex.yes, ArenaBucketIndex.over);
      expect(ArenaBucketIndex.no, ArenaBucketIndex.under);
    });

    test('existing labels are untouched', () {
      expect(ArenaBucketIndex.fromLabel('HOME'), 0);
      expect(ArenaBucketIndex.fromLabel('DRAW'), 1);
      expect(ArenaBucketIndex.fromLabel('AWAY'), 2);
      expect(ArenaBucketIndex.fromLabel('OVER'), 0);
      expect(ArenaBucketIndex.fromLabel('UNDER'), 1);
      expect(ArenaBucketIndex.toLabel(0), 'HOME');
      expect(ArenaBucketIndex.toLabel(1), 'DRAW');
      expect(ArenaBucketIndex.toLabel(2), 'AWAY');
    });

    test('unknown labels still throw', () {
      expect(
        () => ArenaBucketIndex.fromLabel('MAYBE'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toBinaryLabel reverses YES/NO without lying about HOME/OVER', () {
      expect(ArenaBucketIndex.toBinaryLabel(0), 'YES');
      expect(ArenaBucketIndex.toBinaryLabel(1), 'NO');
      expect(
        () => ArenaBucketIndex.toBinaryLabel(2),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a Side round trips through the arena bucket index', () {
      for (final side in Side.values) {
        expect(
          ArenaBucketIndex.toBinaryLabel(
            ArenaBucketIndex.fromLabel(side.wire),
          ),
          side.wire,
        );
      }
    });
  });
}
