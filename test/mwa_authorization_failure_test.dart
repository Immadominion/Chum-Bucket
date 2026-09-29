import 'package:chumbucket/features/authentication/session/mwa_authorization_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each wallet stage has a safe, useful connection refusal', () {
    for (final step in MwaAuthorizationStep.values) {
      final message = mwaAuthorizationFailureMessage(step);
      expect(message, isNotEmpty);
      expect(message, contains('wallet'));
      expect(message.toLowerCase(), isNot(contains('token')));
      expect(message.toLowerCase(), isNot(contains('address')));
      expect(message.toLowerCase(), isNot(contains('uri')));
    }
  });

  test('post-approval storage error is distinct from wallet handoff', () {
    expect(
      mwaAuthorizationFailureMessage(MwaAuthorizationStep.association),
      contains('did not finish connecting'),
    );
    expect(
      mwaAuthorizationFailureMessage(MwaAuthorizationStep.secureSave),
      contains('secure session could not be saved'),
    );
  });
}
