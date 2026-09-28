import 'dart:async';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Challenge fixture(String user) => Challenge(
  id: 'challenge-$user',
  creatorId: user,
  title: 'Fixture',
  description: '',
  amount: 0,
  platformFee: 0,
  winnerAmount: 0,
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2027),
);

void main() {
  test('clearing invalidates an in-flight initialization', () async {
    final held = Completer<List<Challenge>>();
    final state = ChallengeStateProvider(loadChallenges: (_) => held.future);
    addTearDown(state.dispose);
    final loading = state.initialize('account-a');
    state.clear();
    held.complete([fixture('account-a')]);
    await loading;
    expect(state.challenges, isEmpty);
    expect(state.isInitialized, isFalse);
  });
  test('account switch does not inherit or wait for the old history', () async {
    final held = Completer<List<Challenge>>();
    final state = ChallengeStateProvider(
      loadChallenges:
          (user) async =>
              user == 'account-a' ? await held.future : [fixture(user)],
    );
    addTearDown(state.dispose);
    final first = state.initialize('account-a');
    await state.initialize('account-b');
    held.complete([fixture('account-a')]);
    await first;
    expect(state.challenges.single.creatorId, 'account-b');
    expect(state.isInitialized, isTrue);
  });
}
