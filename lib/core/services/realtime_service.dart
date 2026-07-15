import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// Service for real-time Supabase subscriptions
/// Provides live updates when challenges are created or updated
class RealtimeService {
  RealtimeService._();
  static final RealtimeService _instance = RealtimeService._();
  static RealtimeService get instance => _instance;

  RealtimeChannel? _challengesChannel;
  String? _currentUserId;
  bool _isSubscribed = false;

  /// Initialize realtime subscriptions for a user
  Future<void> subscribe(String userId) async {
    // Don't re-subscribe for same user
    if (_isSubscribed && _currentUserId == userId) {
      AppLogger.debug('RealtimeService: Already subscribed for user $userId');
      return;
    }

    // Unsubscribe from previous if different user
    if (_currentUserId != userId) {
      await unsubscribe();
    }

    _currentUserId = userId;

    try {
      final supabase = Supabase.instance.client;

      // Subscribe to challenges table for this user
      // We listen for challenges where user is creator OR witness
      _challengesChannel = supabase.channel('challenges:$userId');

      _challengesChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'challenges',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'creator_id',
              value: userId,
            ),
            callback: (payload) => _handleChallengeChange(payload, userId),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'challenges',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'witness_address',
              value: userId,
            ),
            callback: (payload) => _handleChallengeChange(payload, userId),
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              _isSubscribed = true;
              AppLogger.info('RealtimeService: Subscribed to challenges');
            } else if (status == RealtimeSubscribeStatus.closed) {
              _isSubscribed = false;
              AppLogger.info('RealtimeService: Channel closed');
            } else if (error != null) {
              AppLogger.error('RealtimeService: Subscription error: $error');
            }
          });
    } catch (e) {
      AppLogger.error('RealtimeService: Failed to subscribe: $e');
    }
  }

  void _handleChallengeChange(PostgresChangePayload payload, String userId) {
    AppLogger.info(
      'RealtimeService: Challenge change detected: ${payload.eventType}',
    );

    // Trigger a soft refresh to pick up the changes
    // This is more reliable than trying to parse the payload
    ChallengeStateProvider.instance.softRefresh(userId).catchError((e) {
      AppLogger.error('RealtimeService: Failed to refresh after change: $e');
    });
  }

  /// Unsubscribe from realtime updates
  Future<void> unsubscribe() async {
    if (_challengesChannel != null) {
      try {
        await Supabase.instance.client.removeChannel(_challengesChannel!);
        AppLogger.info('RealtimeService: Unsubscribed from challenges');
      } catch (e) {
        AppLogger.error('RealtimeService: Error unsubscribing: $e');
      }
      _challengesChannel = null;
    }
    _isSubscribed = false;
    _currentUserId = null;
  }

  /// Check if currently subscribed
  bool get isSubscribed => _isSubscribed;
}
