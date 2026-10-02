// The app's copy of the BFF text policy (src/trust/contentFilter.ts). Same
// cases as the API test, so the two cannot quietly disagree on what they say.
import 'package:chumbucket/features/trust/data/content_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links are refused with a reason a person can act on', () {
    for (final t in [
      'see https://x.co',
      'www.scam.xyz now',
      'claim at pump.fun',
      'dm me t.me/rug',
      'bit.ly/abc',
      'free.money here',
    ]) {
      expect(
        contentPolicyProblem(t, ContentField.thesis),
        "Links aren't allowed in your thesis. Remove the web address and try again.",
        reason: t,
      );
    }
  });

  test('slurs and strong profanity are refused, disguised or not', () {
    for (final t in [
      'what a fucking call',
      'F U C K this',
      'fuuuuck',
      'f.u.c.k',
      'b1tch',
      'kys',
    ]) {
      expect(
        contentPolicyProblem(t, ContentField.thesis),
        isNotNull,
        reason: t,
      );
    }
    expect(
      contentPolicyProblem('total motherfucker', ContentField.name),
      "Your name includes language we don't allow. Please rephrase it.",
    );
    expect(
      contentPolicyProblem('slutty', ContentField.bio),
      "Your bio includes language we don't allow. Please rephrase it.",
    );
  });

  test('ordinary writing passes', () {
    for (final t in [
      'BTC breaks 100k by Friday. So it goes.',
      "Damn, this is a hell of a market. I'm 70% sure.",
      'toly.sol called this first',
      'U.S. CPI comes in at 2.9, e.g. below consensus',
      'Scunthorpe United win; the therapist agrees',
      '',
      null,
    ]) {
      expect(contentPolicyProblem(t, ContentField.thesis), isNull, reason: t);
    }
  });
}
