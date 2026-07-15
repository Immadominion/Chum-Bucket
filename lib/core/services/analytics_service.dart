import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// Service for sending analytics events to Telegram
/// Tracks user signups, logins, and challenge creation
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService _instance = AnalyticsService._();
  static AnalyticsService get instance => _instance;

  /// Track user login/signup event
  ///
  /// [walletAddress] - The user's wallet address
  /// [displayName] - SNS domain or truncated wallet
  /// [isNewUser] - Whether this is a new signup
  static Future<void> trackUserAuth({
    required String walletAddress,
    String? displayName,
    required bool isNewUser,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.functions.invoke(
        'analytics-telegram',
        body: {
          'event': isNewUser ? 'user_signup' : 'user_login',
          'wallet_address': walletAddress,
          'display_name': displayName,
        },
      );

      AppLogger.info(
        'Analytics: Tracked ${isNewUser ? "signup" : "login"} for ${displayName ?? walletAddress}',
      );
    } catch (e) {
      // Analytics should never block the main flow
      AppLogger.error('Analytics: Failed to track auth: $e');
    }
  }

  /// Track challenge creation event
  ///
  /// [challengeId] - The challenge ID
  /// [creatorWallet] - Creator's wallet address
  /// [creatorName] - Creator's display name
  /// [witnessWallet] - Witness wallet address
  /// [witnessName] - Witness display name
  /// [amountSol] - Challenge amount in SOL
  /// [feeSol] - Platform fee in SOL
  static Future<void> trackChallengeCreated({
    required String challengeId,
    required String creatorWallet,
    String? creatorName,
    required String witnessWallet,
    String? witnessName,
    required double amountSol,
    required double feeSol,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.functions.invoke(
        'analytics-telegram',
        body: {
          'event': 'challenge_created',
          'challenge_id': challengeId,
          'creator_wallet': creatorWallet,
          'creator_name': creatorName,
          'witness_wallet': witnessWallet,
          'witness_name': witnessName,
          'amount_sol': amountSol,
          'fee_sol': feeSol,
          'network': NetworkConfig.currentNetwork,
        },
      );

      AppLogger.info(
        'Analytics: Tracked challenge $challengeId ($amountSol SOL)',
      );
    } catch (e) {
      // Analytics should never block the main flow
      AppLogger.error('Analytics: Failed to track challenge: $e');
    }
  }

  /// Track challenge resolution event (so you know when you earned fees!)
  ///
  /// [challengeId] - The challenge ID
  /// [winnerWallet] - Winner's wallet address
  /// [winnerName] - Winner's display name
  /// [initiatorWon] - Did the initiator win?
  /// [winnerAmountSol] - Amount winner received in SOL
  /// [feeSol] - Platform fee in SOL (YOUR MONEY!)
  static Future<void> trackChallengeResolved({
    required String challengeId,
    required String winnerWallet,
    String? winnerName,
    required bool initiatorWon,
    required double winnerAmountSol,
    required double feeSol,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.functions.invoke(
        'analytics-telegram',
        body: {
          'event': 'challenge_resolved',
          'challenge_id': challengeId,
          'winner_wallet': winnerWallet,
          'winner_name': winnerName,
          'initiator_won': initiatorWon,
          'winner_amount_sol': winnerAmountSol,
          'fee_sol': feeSol,
          'network': NetworkConfig.currentNetwork,
        },
      );

      AppLogger.info(
        'Analytics: Tracked resolution $challengeId (fee: $feeSol SOL)',
      );
    } catch (e) {
      // Analytics should never block the main flow
      AppLogger.error('Analytics: Failed to track resolution: $e');
    }
  }

  /// Track app error (for monitoring)
  static Future<void> trackError({
    required String errorType,
    required String message,
    String? context,
  }) async {
    // Only track critical errors in production
    if (kDebugMode) return;

    try {
      final supabase = Supabase.instance.client;

      await supabase.functions.invoke(
        'analytics-telegram',
        body: {
          'event': 'error',
          'error_type': errorType,
          'message': message,
          'context': context,
        },
      );
    } catch (e) {
      // Silently fail - we can't track errors about tracking errors
    }
  }
}
