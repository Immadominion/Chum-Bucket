import 'dart:developer' as dev;
import '../models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Unified database service using Supabase for all operations
/// Migrated from local SQLite to remote Supabase for production use
class UnifiedDatabaseService {
  static SupabaseClient? _supabase;

  static void configure({required SupabaseClient supabase}) {
    if (_supabase == null) {
      _supabase = supabase;
      dev.log('Database service configured with Supabase');
    } else {
      dev.log('Database service already configured, skipping reconfiguration');
    }
  }

  // Getter for the configured Supabase client
  static SupabaseClient get _client {
    if (_supabase == null) {
      throw Exception('Database service not configured');
    }
    return _supabase!;
  }

  // Challenge operations
  static Future<Challenge> createChallenge({
    required String title,
    required String description,
    required double amountInSol,
    required String creatorPrivyId,
    required String member1Address,
    required String member2Address,
    DateTime? expiresAt,
    String? participantEmail,
    String? escrowAddress,
    String? vaultAddress,
    required double platformFee,
    required double winnerAmount,
    String? challengeId, // Optional blockchain challenge address to use as ID
  }) async {
    try {
      // Get creator user ID from privy_id
      final creatorResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', creatorPrivyId)
              .maybeSingle();

      if (creatorResponse == null) {
        throw Exception(
          'Creator user not found with privy_id: $creatorPrivyId',
        );
      }

      final creatorDbId = creatorResponse['id'];

      final insertData = {
        'creator_id': creatorDbId,
        'participant_id':
            creatorDbId, // Default to creator, updated when participant joins
        'participant_email': participantEmail ?? '',
        'title': title,
        'description': description,
        'amount': amountInSol, // Fill the NOT NULL amount column
        'amount_sol': amountInSol,
        'platform_fee_sol': platformFee,
        'winner_amount_sol': winnerAmount,
        'expires_at':
            (expiresAt ?? DateTime.now().add(const Duration(days: 7)))
                .toIso8601String(),
        'status': 'pending',
        'multisig_address': escrowAddress,
        'vault_address': vaultAddress,
        // Store member addresses in metadata since they're not direct columns
        'metadata':
            '{"member1Address": "$member1Address", "member2Address": "$member2Address"}',
      };

      // For blockchain challenges, store the blockchain ID in blockchain_id field, not id
      if (challengeId != null && challengeId.isNotEmpty) {
        insertData['blockchain_id'] = challengeId;
      }

      final response =
          await _client.from('challenges').insert(insertData).select().single();

      final createdChallenge = Challenge.fromJson(response);
      dev.log(
        'Challenge created with ID: ${createdChallenge.id}, Blockchain ID: $challengeId',
      );
      return createdChallenge;
    } catch (e) {
      dev.log('Error creating challenge: $e');
      rethrow;
    }
  }

  static Future<Challenge?> getChallenge(String id) async {
    try {
      final response =
          await _client.from('challenges').select().eq('id', id).single();

      return Challenge.fromJson(response);
    } catch (e) {
      dev.log('Error getting challenge: $e');
      return null;
    }
  }

  static Future<List<Challenge>> getChallengesForUser(
    String userPrivyId,
  ) async {
    try {
      // Get user ID from privy_id first
      final userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        dev.log('User not found with privy_id: $userPrivyId');
        return [];
      }

      final userId = userResponse['id'];

      // Query challenges where user is creator or participant
      final response = await _client
          .from('challenges')
          .select(
            '*, blockchain_id, creator:creator_id(privy_id), participant:participant_id(privy_id), witness:witness_id(privy_id)',
          )
          .or('creator_id.eq.$userId,participant_id.eq.$userId')
          .order('created_at', ascending: false);

      dev.log(
        'Database query returned ${response.length} challenges for user $userPrivyId',
      );

      return response.map((json) {
        // Convert the joined data back to the expected format
        final challengeData = Map<String, dynamic>.from(json);

        // Map the foreign key relationships back to privy_ids
        if (challengeData['creator'] != null) {
          challengeData['creator_privy_id'] =
              challengeData['creator']['privy_id'];
        }
        if (challengeData['participant'] != null) {
          challengeData['participant_privy_id'] =
              challengeData['participant']['privy_id'];
        }

        // Map the Supabase column names to what Challenge.fromJson expects
        challengeData['amount'] = challengeData['amount_sol'];
        challengeData['platform_fee'] = challengeData['platform_fee_sol'];
        challengeData['winner_amount'] = challengeData['winner_amount_sol'];
        challengeData['escrow_address'] = challengeData['multisig_address'];

        return Challenge.fromJson(challengeData);
      }).toList();
    } catch (e) {
      dev.log('Error getting challenges for user: $e');
      return [];
    }
  }

  static Future<String?> getParticipantWalletAddress(
    String challengeId,
    String participantPrivyId,
  ) async {
    try {
      final response =
          await _client
              .from('challenge_participants')
              .select('wallet_address')
              .eq('challenge_id', challengeId)
              .eq('user_privy_id', participantPrivyId)
              .maybeSingle();

      return response?['wallet_address'] as String?;
    } catch (e) {
      dev.log('Error getting participant wallet address: $e');
      return null;
    }
  }

  static Future<bool> updateChallenge(
    String id,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _client.from('challenges').update(updates).eq('id', id);
      return true;
    } catch (e) {
      dev.log('Error updating challenge: $e');
      return false;
    }
  }

  /// Convenience method for updating challenge status
  static Future<bool> updateChallengeStatus(
    String id,
    String status, {
    String? transactionSignature,
    String? winnerId,
    DateTime? completedAt,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      // Note: challenges table doesn't have updated_at column, using completed_at instead
    };

    if (transactionSignature != null) {
      updates['transaction_signature'] = transactionSignature;
    }
    if (winnerId != null) {
      updates['winner_privy_id'] = winnerId;
    }
    if (completedAt != null) {
      updates['completed_at'] = completedAt.toIso8601String();
    }

    return await updateChallenge(id, updates);
  }

  // Platform fee operations
  static Future<String> insertPlatformFee(PlatformFee fee) async {
    try {
      final response =
          await _client
              .from('platform_fees')
              .insert(fee.toJson())
              .select()
              .single();

      return response['id'] as String;
    } catch (e) {
      dev.log('Error inserting platform fee: $e');
      rethrow;
    }
  }

  // Challenge transaction operations
  static Future<String> insertChallengeTransaction(
    ChallengeTransaction transaction,
  ) async {
    try {
      final response =
          await _client
              .from('challenge_transactions')
              .insert(transaction.toJson())
              .select()
              .single();

      return response['id'] as String;
    } catch (e) {
      dev.log('Error inserting challenge transaction: $e');
      rethrow;
    }
  }

  // Challenge participant operations
  static Future<String> insertChallengeParticipant(
    ChallengeParticipant participant,
  ) async {
    try {
      final response =
          await _client
              .from('challenge_participants')
              .insert(participant.toJson())
              .select()
              .single();

      return response['id'] as String;
    } catch (e) {
      dev.log('Error inserting challenge participant: $e');
      rethrow;
    }
  }

  // Friends operations
  /// Add a friend by their wallet address
  static Future<bool> addFriend({
    required String userPrivyId,
    required String friendName,
    required String friendWalletAddress,
  }) async {
    try {
      dev.log(
        'Adding friend: $friendName ($friendWalletAddress) for user: $userPrivyId',
      );

      // Get the user's database ID
      final userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        throw Exception('User not found with privy_id: $userPrivyId');
      }

      final userId = userResponse['id'];

      // Check if friend exists by wallet address, if not create them
      final existingFriendResponse =
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', friendWalletAddress)
              .maybeSingle();

      int friendId;

      if (existingFriendResponse == null) {
        // Friend doesn't exist, create a new user record with minimal info
        final newFriendResponse =
            await _client
                .from('users')
                .insert({
                  'privy_id':
                      'wallet_${friendWalletAddress.substring(0, 8)}', // Temporary privy_id
                  'email':
                      'wallet_${friendWalletAddress.substring(0, 8)}@temp.com', // Temporary email
                  'full_name': friendName,
                  'wallet_address': friendWalletAddress,
                  'created_at': DateTime.now().toIso8601String(),
                })
                .select('id')
                .single();

        friendId = newFriendResponse['id'];
        dev.log('Created new user for friend with ID: $friendId');
      } else {
        friendId = existingFriendResponse['id'];

        // Update the existing user's name if it's not set
        final currentUser =
            await _client
                .from('users')
                .select('full_name')
                .eq('id', friendId)
                .single();

        if (currentUser['full_name'] == null) {
          await _client
              .from('users')
              .update({'full_name': friendName})
              .eq('id', friendId);
        }

        dev.log('Found existing user for friend with ID: $friendId');
      }

      // Check if friendship already exists (bidirectional)
      final existingFriendship =
          await _client
              .from('friends')
              .select()
              .or(
                'and(user_id.eq.$userId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$userId)',
              )
              .maybeSingle();

      if (existingFriendship != null) {
        dev.log(
          'Friendship already exists between users $userId and $friendId',
        );
        return true; // Already friends
      }

      // Create bidirectional friendship
      await _client.from('friends').insert([
        {
          'user_id': userId,
          'friend_id': friendId,
          'status': 'accepted',
          'created_at': DateTime.now().toIso8601String(),
        },
        {
          'user_id': friendId,
          'friend_id': userId,
          'status': 'accepted',
          'created_at': DateTime.now().toIso8601String(),
        },
      ]);

      dev.log(
        'Successfully added friendship between users $userId and $friendId',
      );
      return true;
    } catch (e) {
      dev.log('Error adding friend: $e');
      return false;
    }
  }

  /// Get all friends for a user
  static Future<List<Map<String, String>>> getUserFriends(
    String id, {
    required String userPrivyId,
  }) async {
    try {
      dev.log('Getting friends for user: $userPrivyId');

      // Get user's database ID
      final userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        throw Exception('User not found with privy_id: $userPrivyId');
      }

      final userId = userResponse['id'];

      // Get friends with their details
      final friendsResponse = await _client
          .from('friends')
          .select('''
            friend_id,
            users!friends_friend_id_fkey(
              full_name,
              profile_image_id,
              wallet_address
            )
          ''')
          .eq('user_id', userId)
          .eq('status', 'accepted');

      dev.log(
        'Retrieved ${friendsResponse.length} friends for user $userPrivyId',
      );

      // Transform the data to the expected format
      final List<Map<String, String>> friends = [];
      for (final friendData in friendsResponse) {
        final friendDetails = friendData['users'] as Map<String, dynamic>;

        final walletAddress = friendDetails['wallet_address'] as String? ?? '';
        final friendName =
            friendDetails['full_name'] as String? ?? 'Unknown Friend';

        // Only add friends that have wallet addresses
        if (walletAddress.isNotEmpty) {
          friends.add({
            'name': friendName,
            'walletAddress': walletAddress,
            'profileImageId': '0', // Will be set based on position later
            'avatarColor':
                '#FF5A76', // Default color, will be set based on position
          });
          dev.log('Added friend: $friendName ($walletAddress)');
        } else {
          dev.log('Skipped friend $friendName - no wallet address');
        }
      }

      return friends;
    } catch (e) {
      dev.log('Error getting friends: $e');
      return [];
    }
  }

  /// Remove a friend
  static Future<bool> removeFriend({
    required String userPrivyId,
    required String friendWalletAddress,
  }) async {
    try {
      dev.log(
        'Removing friend with wallet: $friendWalletAddress for user: $userPrivyId',
      );

      // Get user and friend IDs
      final userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      final friendResponse =
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', friendWalletAddress)
              .maybeSingle();

      if (userResponse == null || friendResponse == null) {
        dev.log('User or friend not found');
        return false;
      }

      final userId = userResponse['id'];
      final friendId = friendResponse['id'];

      // Remove bidirectional friendship
      await _client
          .from('friends')
          .delete()
          .or(
            'and(user_id.eq.$userId,friend_id.eq.$friendId),and(user_id.eq.$friendId,friend_id.eq.$userId)',
          );

      dev.log(
        'Successfully removed friendship between users $userId and $friendId',
      );
      return true;
    } catch (e) {
      dev.log('Error removing friend: $e');
      return false;
    }
  }

  /// Debug method to check challenge data in Supabase
  static Future<void> debugChallengeData(String userPrivyId) async {
    try {
      // Get user ID from privy_id first
      final userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        dev.log('DEBUG: User not found with privy_id: $userPrivyId');
        return;
      }

      final userId = userResponse['id'];
      dev.log('DEBUG: Found user ID: $userId for privy_id: $userPrivyId');

      // Count total challenges in the system
      final totalChallenges = await _client.from('challenges').select('id');
      dev.log('DEBUG: Total challenges in database: ${totalChallenges.length}');

      // Show first 20 challenges with details
      final challengeDetails = await _client
          .from('challenges')
          .select('id, title, description, status, created_at')
          .or('creator_id.eq.$userId,participant_privy_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(20);

      dev.log('DEBUG: Found ${challengeDetails.length} challenges for user');
      dev.log('DEBUG: First 20 challenges for user:');
      for (int i = 0; i < challengeDetails.length; i++) {
        final challenge = challengeDetails[i];
        dev.log(
          '  ${i + 1}. ${challenge['title'] ?? 'No title'} - ${challenge['description'] ?? 'No description'} (${challenge['status']}) - ${challenge['created_at']}',
        );
      }
    } catch (e) {
      dev.log('DEBUG: Error checking challenge data: $e');
    }
  }

  // Utility methods - Supabase doesn't need manual data clearing or stats
  static Future<void> clearAllData() async {
    dev.log('Data clearing not available with Supabase (use dashboard)');
  }

  static Future<Map<String, int>> getDatabaseStats() async {
    try {
      // Get basic stats from Supabase
      final challengeData = await _client.from('challenges').select();
      final friendsData = await _client.from('friends').select();

      return {
        'challenges': challengeData.length,
        'friends': friendsData.length,
      };
    } catch (e) {
      dev.log('Error getting database stats: $e');
      return {};
    }
  }

  static String get currentMode => 'Supabase Remote Database';
}
