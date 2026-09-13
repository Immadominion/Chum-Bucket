/// The privacy guard, tested with the payloads somebody would actually write.
///
/// Each case here is a plausible mistake, not a strawman: a wallet address
/// because "it identifies the user", a SOL balance because "it segments
/// whales", the thesis because "we want to read what people say", an access
/// token because it was on the same object. The point of the test is that none
/// of them needs a reviewer to notice — the guard drops them.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chumbucket/core/analytics/analytics.dart';

/// A real-shaped Solana address (base58, 44 chars). Not a live account — it is
/// the well-known all-ones system-program-adjacent shape used in docs — and it
/// is here only so the regex is exercised against the real alphabet/length.
const String kWalletShaped = 'So11111111111111111111111111111111111111112';

/// 88 base58 chars: the shape of an ed25519 transaction signature.
const String kSignatureShaped =
    '5VERv8NsvbLPdfmqWhaEB4LQb9nGFT1ZvCRyDT1hf8rL'
    '7Y7zkVBLqxJQx6r6yWLCxHQe9QxMPxvNKtQEmnR3bT2c';

const String kJwtShaped =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
    '.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXkA';

const String kThesis =
    'ETF inflows have outpaced issuance for six straight weeks and the '
    'options skew flipped on Tuesday, so I think this clears by Friday.';

void main() {
  group('rejects a wallet', () {
    test('by key, under any spelling', () {
      for (final key in [
        'wallet',
        'walletAddress',
        'wallet_address',
        'creatorWallet',
        'publicKey',
        'pubkey',
        'ownerAddress',
      ]) {
        final violations = AnalyticsPrivacyGuard.inspect({key: 'user_ada'});
        expect(
          violations.map((v) => v.rule),
          contains(AnalyticsPrivacyRule.deniedKey),
          reason: '"$key" was allowed through',
        );
      }
    });

    test('by value shape, even under an innocent key', () {
      // The classic: identity is `public.users.id` (contract §0.3), somebody
      // passes the wallet instead and the key looks fine.
      final violations = AnalyticsPrivacyGuard.inspect({
        AnalyticsProps.personId: kWalletShaped,
      });
      expect(violations, hasLength(1));
      expect(violations.single.rule, AnalyticsPrivacyRule.secretShapedValue);
      expect(violations.single.key, AnalyticsProps.personId);
    });

    test('a violation report never repeats the offending value', () {
      final violations = AnalyticsPrivacyGuard.inspect({
        AnalyticsProps.personId: kWalletShaped,
      });
      expect('${violations.single}', isNot(contains(kWalletShaped)));
    });
  });

  group('rejects a signature', () {
    test('by key', () {
      for (final key in ['signature', 'txSignature', 'openTxSignature', 'sig']) {
        expect(
          AnalyticsPrivacyGuard.inspect({key: 'abc'}).map((v) => v.rule),
          contains(AnalyticsPrivacyRule.deniedKey),
          reason: '"$key" was allowed through',
        );
      }
    });

    test('by value shape', () {
      final violations = AnalyticsPrivacyGuard.inspect({
        AnalyticsProps.callId: kSignatureShaped,
      });
      expect(violations.single.rule, AnalyticsPrivacyRule.secretShapedValue);
    });
  });

  group('rejects a balance or a stake', () {
    test('by key, including the SOL-denominated ones', () {
      for (final key in [
        'balance',
        'solBalance',
        'amountSol',
        'amount_sol',
        'feeSol',
        'stake',
        'stakeAmount',
        'payout',
        'pnl',
        'lamports',
        'winnerAmountSol',
      ]) {
        expect(
          AnalyticsPrivacyGuard.inspect({key: 1}).map((v) => v.rule),
          contains(AnalyticsPrivacyRule.deniedKey),
          reason: '"$key" was allowed through',
        );
      }
    });

    test('but does not reject `resolution`, which merely contains "sol"', () {
      // Word-splitting rather than substring matching is the whole reason this
      // passes. If the guard is ever "simplified" to a substring check, the
      // FROZEN §3 vocabulary stops being recordable.
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.resolution: 'VOID',
          AnalyticsProps.marketStatus: 'CLOSED_PENDING_RESOLUTION',
          AnalyticsProps.position: 3,
          AnalyticsProps.confidencePresent: true,
        }),
        isEmpty,
      );
    });
  });

  group('rejects a credential', () {
    test('an access token by key', () {
      expect(
        AnalyticsPrivacyGuard.inspect({'accessToken': 'x'}).map((v) => v.rule),
        contains(AnalyticsPrivacyRule.deniedKey),
      );
      expect(
        AnalyticsPrivacyGuard.inspect({'apiKey': 'x'}).map((v) => v.rule),
        contains(AnalyticsPrivacyRule.deniedKey),
      );
      expect(
        AnalyticsPrivacyGuard.inspect({'nonce': 'x'}).map((v) => v.rule),
        contains(AnalyticsPrivacyRule.deniedKey),
      );
    });

    test('a JWT by value shape', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.callId: kJwtShaped,
        }).single.rule,
        AnalyticsPrivacyRule.secretShapedValue,
      );
    });

    test('an email by value shape, under any key', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.personId: 'ada@chumbucket.app',
        }).single.rule,
        AnalyticsPrivacyRule.secretShapedValue,
      );
      expect(
        AnalyticsPrivacyGuard.inspect({'email': 'x'}).map((v) => v.rule),
        contains(AnalyticsPrivacyRule.deniedKey),
      );
    });

    test('a hex key or a base64 blob by value shape', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.callId: 'a3f' * 16,
        }).single.rule,
        AnalyticsPrivacyRule.secretShapedValue,
      );
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.callId: 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZn',
        }).single.rule,
        AnalyticsPrivacyRule.secretShapedValue,
      );
    });
  });

  group('rejects a thesis', () {
    test('by key, in full', () {
      final violations = AnalyticsPrivacyGuard.inspect({'thesis': kThesis});
      expect(
        violations.map((v) => v.rule),
        containsAll([
          AnalyticsPrivacyRule.deniedKey,
          // Prose has spaces and is long. Both catch it independently.
          AnalyticsPrivacyRule.freeTextValue,
        ]),
      );
    });

    test('by value, even relabelled as something innocuous', () {
      // The realistic version of the mistake: the key is renamed to get past a
      // review, the text is unchanged.
      final violations = AnalyticsPrivacyGuard.inspect({'detail': kThesis});
      expect(violations.single.rule, AnalyticsPrivacyRule.freeTextValue);
    });

    test('and rejects a truncated thesis too — a prefix is still the text', () {
      final violations = AnalyticsPrivacyGuard.inspect({
        'detail': kThesis.substring(0, 40),
      });
      expect(violations.single.rule, AnalyticsPrivacyRule.freeTextValue);
    });

    test('but allows its presence and its length bucket', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.thesisPresent: true,
          AnalyticsProps.thesisLengthBucket: ThesisLengthBucket.of(kThesis).wire,
        }),
        isEmpty,
      );
    });
  });

  group('rejects user-authored strings that are not ids', () {
    test('a display name, a handle and a market question', () {
      for (final entry in {
        'displayName': 'Ada Lovelace',
        'handle': 'ada',
        'question': 'Will BTC close above 150k?',
      }.entries) {
        expect(
          AnalyticsPrivacyGuard.inspect({entry.key: entry.value}),
          isNotEmpty,
          reason: '"${entry.key}" was allowed through',
        );
      }
    });

    test('a market question relabelled as a dimension', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          'label': 'Will BTC close above 150k on 31 December?',
        }).single.rule,
        AnalyticsPrivacyRule.freeTextValue,
      );
    });

    test('but allows call, market and person ids', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.callId: 'call_ada_btc',
          AnalyticsProps.marketId: 'market_btc_150k',
          AnalyticsProps.personId: 'user_ada',
          AnalyticsProps.authorId: '550e8400-e29b-41d4-a716-446655440000',
          AnalyticsProps.targetCallId: 'call_you_fed',
        }),
        isEmpty,
      );
    });
  });

  group('rejects structurally malformed payloads', () {
    test('a nested object — the way a whole model gets smuggled in', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          'detail': {'callId': 'call_ada_btc', 'wallet': kWalletShaped},
        }).single.rule,
        AnalyticsPrivacyRule.nonScalarValue,
      );
    });

    test('a list', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          'detail': ['a', 'b'],
        }).single.rule,
        AnalyticsPrivacyRule.nonScalarValue,
      );
    });

    test('a null', () {
      expect(
        AnalyticsPrivacyGuard.inspect({AnalyticsProps.callId: null}).single.rule,
        AnalyticsPrivacyRule.nonScalarValue,
      );
    });

    test('a non-finite number', () {
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.entryProbability: double.nan,
        }).single.rule,
        AnalyticsPrivacyRule.nonFiniteNumber,
      );
      expect(
        AnalyticsPrivacyGuard.inspect({
          AnalyticsProps.entryProbability: double.infinity,
        }).single.rule,
        AnalyticsPrivacyRule.nonFiniteNumber,
      );
    });

    test('an over-wide payload', () {
      final wide = <String, Object?>{
        for (var i = 0; i < AnalyticsPrivacyGuard.maxProps + 1; i++)
          'dimension$i': i,
      };
      expect(
        AnalyticsPrivacyGuard.inspect(wide).map((v) => v.rule),
        contains(AnalyticsPrivacyRule.tooManyProps),
      );
    });
  });

  group('key word splitting', () {
    test('splits camelCase and snake_case the same way', () {
      expect(AnalyticsPrivacyGuard.keyWords('walletAddress'), [
        'wallet',
        'address',
      ]);
      expect(AnalyticsPrivacyGuard.keyWords('wallet_address'), [
        'wallet',
        'address',
      ]);
      expect(AnalyticsPrivacyGuard.keyWords('resolution'), ['resolution']);
      expect(AnalyticsPrivacyGuard.keyWords('venueIsDemo'), [
        'venue',
        'is',
        'demo',
      ]);
    });
  });

  group('enforcement, not documentation', () {
    test('enforce throws on a violating payload', () {
      expect(
        () => AnalyticsPrivacyGuard.enforce({'walletAddress': kWalletShaped}),
        throwsA(isA<AnalyticsPrivacyException>()),
      );
      expect(
        () => AnalyticsPrivacyGuard.enforce({
          AnalyticsProps.callId: 'call_ada_btc',
        }),
        returnsNormally,
      );
    });

    test('the recorder drops a violating event instead of delivering it', () {
      final sink = InMemoryAnalyticsSink();
      final recorder = AnalyticsRecorder(sink: sink);
      recorder.setUnit('user_ada');

      // The only way to construct a violating event through the public API is
      // to put something bad in a value — which is exactly the realistic
      // failure, since the keys are fixed by the typed constructors.
      final smuggled = AnalyticsEvents.callOpened(
        callId: kWalletShaped,
        surface: AnalyticsSurface.feedGlobal,
      );

      expect(recorder.record(smuggled), AnalyticsRecordOutcome.rejected);
      expect(sink.length, 0);
      expect(recorder.rejectedCount, 1);
      expect(
        recorder.rejections.single.violations.single.rule,
        AnalyticsPrivacyRule.secretShapedValue,
      );
      expect('${recorder.rejections.single}', isNot(contains(kWalletShaped)));
    });

    test('a rejected event does not consume its dedupe slot', () {
      final sink = InMemoryAnalyticsSink();
      final recorder = AnalyticsRecorder(sink: sink);

      // Same dedupe key both times: first with a bad market id, then clean.
      // If the rejected one had been remembered, the clean one would be lost.
      expect(
        recorder.record(
          AnalyticsEvents.feedCallImpression(
            callId: 'call_ada_btc',
            marketId: 'Will BTC close above 150k?',
            authorId: 'user_ada',
            surface: AnalyticsSurface.feedGlobal,
            position: 0,
          ),
        ),
        AnalyticsRecordOutcome.rejected,
      );
      expect(
        recorder.record(
          AnalyticsEvents.feedCallImpression(
            callId: 'call_ada_btc',
            marketId: 'market_btc_150k',
            authorId: 'user_ada',
            surface: AnalyticsSurface.feedGlobal,
            position: 0,
          ),
        ),
        AnalyticsRecordOutcome.delivered,
      );
      expect(sink.length, 1);
    });
  });
}
