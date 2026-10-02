/// The first-run pages say what the product is, truthfully: people's calls on
/// real prediction markets, calls free, trades optional real USDC on Panta
/// that the person signs and can lose. Nothing from the old practice-network
/// challenge product.
library;

import 'package:chumbucket/features/authentication/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pages = OnboardingScreen.peopleFirstPages;
  final copy =
      [
        for (final page in pages) '${page.title}\n${page.description}',
      ].join('\n').toLowerCase();

  test('three pages, people and calls first', () {
    expect(pages, hasLength(3));
    expect(pages.first.title, 'See who called it');
    expect(copy, contains('real prediction markets'));
  });

  test('says calls are free and trades are real, signed and can lose', () {
    expect(copy, contains('making a call is free'));
    expect(copy, contains('real usdc on panta'));
    expect(copy, contains('you sign every trade'));
    expect(copy, contains('you can lose what you put in'));
  });

  test('none of the old challenge-product promises', () {
    for (final stale in [
      'practice network',
      'play money',
      'put money on the match',
      'held safely',
      'winners get paid',
      'make it count',
    ]) {
      expect(copy, isNot(contains(stale)), reason: stale);
    }
  });
}
