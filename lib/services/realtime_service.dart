import 'dart:async';
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/models/models.dart';

/// Service for handling real-time updates for challenges
/// This service manages Supabase real-time subscriptions to keep the UI updated
class RealtimeService {
  final SupabaseClient _supabase;
  StreamSubscription<List<Map<String, dynamic>>>? _challengeSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _userChallengesSubscription;

  RealtimeService({required SupabaseClient supabase}) : _supabase = supabase;

  /// Subscribe to real-time updates for a specific challenge
  void subscribeToChallenge(String challengeId, Function(Challenge) onUpdate) {
    try {
      log('Subscribing to real-time updates for challenge: $challengeId');

      _challengeSubscription = _supabase
          .from('challenges')
          .stream(primaryKey: ['id'])
          .eq('id', challengeId)
          .listen((data) {
            if (data.isNotEmpty) {
              try {
                final challenge = Challenge.fromJson(data.first);
                log(
                  'Received real-time update for challenge $challengeId: ${challenge.status}',
                );
                onUpdate(challenge);
              } catch (e) {
                log('Error parsing challenge update: $e');
              }
            }
          });

      log('Successfully subscribed to challenge $challengeId updates');
    } catch (e) {
      log('Error subscribing to challenge updates: $e');
    }
  }

  /// Subscribe to real-time updates for all challenges for a specific user
  void subscribeToUserChallenges(
    String privyId,
    Function(List<Challenge>) onUpdate,
  ) {
    try {
      log('Subscribing to real-time updates for user challenges: $privyId');

      _userChallengesSubscription = _supabase
          .from('challenges')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .listen((data) {
            try {
              // Filter challenges for the user on the client side
              final userChallenges =
                  data.where((challengeData) {
                    final creatorId =
                        challengeData['creator_privy_id'] as String?;
                    final participantId =
                        challengeData['participant_privy_id'] as String?;
                    return creatorId == privyId || participantId == privyId;
                  }).toList();

              final challenges =
                  userChallenges
                      .map((json) => Challenge.fromJson(json))
                      .toList();
              log(
                'Received real-time update for user challenges: ${challenges.length} challenges',
              );
              onUpdate(challenges);
            } catch (e) {
              log('Error parsing user challenges update: $e');
            }
          });

      log('Successfully subscribed to user $privyId challenges updates');
    } catch (e) {
      log('Error subscribing to user challenges updates: $e');
    }
  }

  /// Subscribe to platform fee updates (for admin/analytics purposes)
  void subscribeToPlatformFees(Function(List<PlatformFee>) onUpdate) {
    try {
      log('Subscribing to real-time platform fee updates');

      _supabase
          .from('platform_fees')
          .stream(primaryKey: ['id'])
          .order('collected_at', ascending: false)
          .listen((data) {
            try {
              final fees =
                  data.map((json) => PlatformFee.fromJson(json)).toList();
              log(
                'Received real-time platform fees update: ${fees.length} fees',
              );
              onUpdate(fees);
            } catch (e) {
              log('Error parsing platform fees update: $e');
            }
          });

      log('Successfully subscribed to platform fees updates');
    } catch (e) {
      log('Error subscribing to platform fees updates: $e');
    }
  }

  /// Subscribe to challenge transaction updates for a specific challenge
  void subscribeToChallengeTransactions(
    String challengeId,
    Function(List<ChallengeTransaction>) onUpdate,
  ) {
    try {
      log(
        'Subscribing to real-time transaction updates for challenge: $challengeId',
      );

      _supabase
          .from('challenge_transactions')
          .stream(primaryKey: ['id'])
          .eq('challenge_id', challengeId)
          .order('created_at', ascending: false)
          .listen((data) {
            try {
              final transactions =
                  data
                      .map((json) => ChallengeTransaction.fromJson(json))
                      .toList();
              log(
                'Received real-time transaction update for challenge $challengeId: ${transactions.length} transactions',
              );
              onUpdate(transactions);
            } catch (e) {
              log('Error parsing challenge transactions update: $e');
            }
          });

      log(
        'Successfully subscribed to challenge $challengeId transaction updates',
      );
    } catch (e) {
      log('Error subscribing to challenge transaction updates: $e');
    }
  }

  /// Update challenge status (typically called when multisig operations complete)
  Future<void> updateChallengeStatus(
    String challengeId,
    ChallengeStatus status, {
    String? winnerId,
    String? transactionSignature,
    String? feeTransactionSignature,
  }) async {
    try {
      log('Updating challenge $challengeId status to $status');

      final updateData = <String, dynamic>{
        'status': status.toString().split('.').last,
      };

      if (status == ChallengeStatus.completed) {
        updateData['completed_at'] = DateTime.now().toIso8601String();
        if (winnerId != null) updateData['winner_privy_id'] = winnerId;
        if (transactionSignature != null)
          updateData['transaction_signature'] = transactionSignature;
        if (feeTransactionSignature != null)
          updateData['fee_transaction_signature'] = feeTransactionSignature;
      }

      await _supabase
          .from('challenges')
          .update(updateData)
          .eq('id', challengeId);

      log('Successfully updated challenge $challengeId status to $status');
    } catch (e) {
      log('Error updating challenge status: $e');
      rethrow;
    }
  }

  /// Record a challenge transaction (deposit, withdrawal, fee collection)
  Future<void> recordChallengeTransaction({
    required String challengeId,
    required String transactionType,
    required double amountSol,
    String? fromAddress,
    String? toAddress,
    required String transactionSignature,
    DateTime? blockTime,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      log(
        'Recording challenge transaction: $transactionType for challenge $challengeId',
      );

      final transaction = ChallengeTransaction(
        id: '', // Will be generated by Supabase
        challengeId: challengeId,
        transactionSignature: transactionSignature,
        transactionType: transactionType,
        amount: amountSol,
        fromAddress: fromAddress,
        toAddress: toAddress,
        createdAt: DateTime.now(),
      );

      await _supabase
          .from('challenge_transactions')
          .insert(transaction.toJson());

      log('Successfully recorded challenge transaction: $transactionSignature');
    } catch (e) {
      log('Error recording challenge transaction: $e');
      rethrow;
    }
  }

  /// Get challenge statistics (for analytics)
  Future<Map<String, dynamic>> getChallengeStatistics() async {
    try {
      log('Fetching challenge statistics');

      final response = await _supabase.from('challenge_stats').select('*');

      log('Successfully fetched challenge statistics');
      return {
        'stats': response,
        'fetched_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      log('Error fetching challenge statistics: $e');
      rethrow;
    }
  }

  /// Get user challenge summary
  Future<Map<String, dynamic>> getUserChallengeSummary(String privyId) async {
    try {
      log('Fetching user challenge summary for: $privyId');

      final response = await _supabase
          .from('user_challenge_summary')
          .select('*')
          .eq('user_privy_id', privyId);

      log('Successfully fetched user challenge summary');
      return {
        'summary': response,
        'fetched_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      log('Error fetching user challenge summary: $e');
      rethrow;
    }
  }

  /// Unsubscribe from challenge updates
  void unsubscribeFromChallenge() {
    try {
      if (_challengeSubscription != null) {
        _challengeSubscription!.cancel();
        _challengeSubscription = null;
        log('Unsubscribed from challenge updates');
      }
    } catch (e) {
      log('Error unsubscribing from challenge updates: $e');
    }
  }

  /// Unsubscribe from user challenges updates
  void unsubscribeFromUserChallenges() {
    try {
      if (_userChallengesSubscription != null) {
        _userChallengesSubscription!.cancel();
        _userChallengesSubscription = null;
        log('Unsubscribed from user challenges updates');
      }
    } catch (e) {
      log('Error unsubscribing from user challenges updates: $e');
    }
  }

  /// Clean up all subscriptions
  void dispose() {
    unsubscribeFromChallenge();
    unsubscribeFromUserChallenges();
    log('RealtimeService disposed');
  }
}
