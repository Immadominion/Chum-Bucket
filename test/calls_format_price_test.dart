import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('display prices round half-up on the decimal string', () {
    for (final (raw, shown) in [
      ('0.500096044', '0.50'),
      ('0.502247129', '0.50'),
      ('0.499903956', '0.50'),
      ('0.620000000000000001', '0.62'),
      ('0.625', '0.63'),
      ('0.624999999999999999', '0.62'),
      ('0.995', '1.00'),
      ('1.25', '1.25'),
      ('0.5', '0.50'),
      ('1', '1.00'),
      ('0.004', '<0.01'),
      ('0.005', '0.01'),
      ('0', '0.00'),
      ('0.000', '0.00'),
    ]) {
      expect(CallsFormat.displayPrice(raw), shown, reason: raw);
    }
  });

  test('a value it cannot parse is returned unchanged, never guessed', () {
    for (final raw in ['', '-0.5', '1e-3', 'abc', '.5']) {
      expect(CallsFormat.displayPrice(raw), raw);
      expect(CallsFormat.priceWasRounded(raw), isFalse);
    }
  });

  test('rounding is flagged only when figures were dropped', () {
    expect(CallsFormat.priceWasRounded('0.500096044'), isTrue);
    expect(CallsFormat.priceWasRounded('0.004'), isTrue);
    expect(CallsFormat.priceWasRounded('0.62'), isFalse);
    expect(CallsFormat.priceWasRounded('0.5'), isFalse);
    expect(CallsFormat.priceWasRounded('0.500'), isFalse);
    expect(CallsFormat.priceWasRounded('1'), isFalse);
  });
}
