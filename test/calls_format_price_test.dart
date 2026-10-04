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
  });
}
