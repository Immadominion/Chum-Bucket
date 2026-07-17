import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('claimable positions preserve numeric payout fields as BigInt', () {
    final position = ArenaServerPosition.fromJson({
      'id': 'position-1',
      'match_id': 'match-1',
      'bucket': 'HOME',
      'stake_base_units': '1250000',
      'payout_base_units': '2300000',
      'pnl_base_units': '1050000',
      'open_tx_signature': 'signature',
      'placed_at': '2026-07-16T12:00:00.000Z',
      'status': 'CLAIMABLE',
      'metadata': {'home': 'Nigeria', 'away': 'Brazil'},
    });

    expect(position.status, 'CLAIMABLE');
    expect(position.payoutBaseUnits, BigInt.from(2300000));
    expect(position.pnlBaseUnits, BigInt.from(1050000));
  });

  test('notifications retain unread state and public routing data', () {
    final notification = ArenaNotification.fromJson({
      'id': 'notification-1',
      'type': 'CLAIM_AVAILABLE',
      'title': 'Winnings ready',
      'body': 'Your call settled.',
      'data': {'matchId': 'match-1', 'positionId': 'position-1'},
      'read_at': null,
      'created_at': '2026-07-16T12:00:00.000Z',
    });

    expect(notification.isUnread, isTrue);
    expect(notification.data['matchId'], 'match-1');
    expect(notification.copyWith(readAt: DateTime.utc(2026)).isUnread, isFalse);
  });
}
