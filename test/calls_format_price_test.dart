import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a share price reads as odds, rounded half-up on the decimal string', () {
    for (final (raw, shown) in [
      ('0.62', '62%'),
      ('0.500096044', '50%'),
      ('0.502247129', '50%'),
      ('0.499903956', '50%'),
      ('0.620000000000000001', '62%'),
      ('0.625', '63%'),
      ('0.624999999999999999', '62%'),
      ('0.5', '50%'),
      ('0.05', '5%'),
      ('0.005', '1%'),
      ('0.99', '99%'),
    ]) {
      expect(CallsFormat.odds(raw), shown, reason: raw);
    }
  });

  test('the ends never round into a certainty', () {
    // A live price just above zero or just short of a whole share is never
    // shown as 0% or 100%; only the exact ends are.
    expect(CallsFormat.odds('0.004'), '<1%');
    expect(CallsFormat.odds('0.000000001'), '<1%');
    expect(CallsFormat.odds('0.995'), '>99%');
    expect(CallsFormat.odds('0.999999999'), '>99%');
    expect(CallsFormat.odds('0'), '0%');
    expect(CallsFormat.odds('0.000'), '0%');
    expect(CallsFormat.odds('1'), '100%');
    expect(CallsFormat.odds('1.000000000'), '100%');
  });

  test('nothing honest to show reads null (the UI draws "—"), never a guess', () {
    for (final raw in [null, '', '-0.5', '1e-3', 'abc', '.5', '1.25', '2']) {
      expect(CallsFormat.odds(raw), isNull, reason: '$raw');
    }
  });

  test('odds never carry a unit, a cent sign or a per-share figure', () {
    for (final raw in ['0.67', '0.52', '0.004', '0.995']) {
      final shown = CallsFormat.odds(raw)!;
      expect(shown, endsWith('%'));
      expect(shown, isNot(matches(RegExp(r'USDC|SOL|share|¢|\$'))));
    }
  });

  test('independent prices read as odds that add up: YES = yes/(yes+no)', () {
    for (final (yes, no, shownYes, shownNo) in [
      ('0.62', '0.43', '59%', '41%'),
      ('1.25', '0.35', '78%', '22%'),
      ('0.625', '0.375', '63%', '37%'),
      ('0.620000000000000001', '0.430000000000000001', '59%', '41%'),
      // A SOL market's complementary pair reads as its own figures.
      ('0.671739755', '0.328260245', '67%', '33%'),
      ('0.5', '0.5', '50%', '50%'),
      ('1', '0', '100%', '0%'),
      ('0', '0.7', '0%', '100%'),
      // Never rounded into a certainty either side.
      ('0.004', '0.996', '<1%', '>99%'),
      ('0.996', '0.004', '>99%', '<1%'),
    ]) {
      final pair = CallsFormat.pairOdds(yes, no);
      expect((pair.yes, pair.no), (shownYes, shownNo), reason: '$yes/$no');
    }
  });

  test('one side missing reads that side alone; none, or zero, reads null', () {
    expect(CallsFormat.pairOdds('0.62', null), (yes: '62%', no: null));
    expect(CallsFormat.pairOdds(null, '0.43'), (yes: null, no: '43%'));
    // Alone, a price above a whole share has no honest percent.
    expect(CallsFormat.pairOdds('1.25', null), (yes: null, no: null));
    expect(CallsFormat.pairOdds(null, null), (yes: null, no: null));
    expect(CallsFormat.pairOdds('0', '0'), (yes: null, no: null));
    expect(CallsFormat.pairOdds('abc', '0.4'), (yes: null, no: '40%'));
  });

  test('both sides read as odds, a missing side as "—"', () {
    SharePriceSnapshot snap(String? yes, String? no, ShareCurrency c) =>
        SharePriceSnapshot(
          id: '00000000-0000-4000-8000-000000000001',
          marketId: '00000000-0000-4000-8000-000000000002',
          yesPrice: yes,
          noPrice: no,
          observedAt: 1,
          currency: c,
        );
    expect(
      CallsFormat.sidesOdds(snap('0.62', '0.38', ShareCurrency.usdc)),
      'YES 62% · NO 38%',
    );
    // A SOL-quoted market's price is on the same 0..1 scale: the same odds.
    expect(
      CallsFormat.sidesOdds(snap('0.67', '0.33', ShareCurrency.sol)),
      'YES 67% · NO 33%',
    );
    expect(
      CallsFormat.sidesOdds(snap('0.62', null, ShareCurrency.usdc)),
      'YES 62% · NO —',
    );
    expect(
      CallsFormat.sidesOdds(snap('1.25', '0.35', ShareCurrency.usdc)),
      'YES 78% · NO 22%',
    );
    expect(
      CallsFormat.sideOdds(snap('0.62', '0.43', ShareCurrency.usdc), Side.no),
      '41%',
    );
  });
}
