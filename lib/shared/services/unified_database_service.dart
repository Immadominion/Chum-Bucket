import 'dart:developer' as dev;
import '../models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/core/config/network_config.dart';

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
      // Get creator user ID - check both privy_id and wallet_address (for MWA auth)
      var creatorResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', creatorPrivyId)
              .maybeSingle();

      // If not found by privy_id, try wallet_address (MWA auth)
      creatorResponse ??=
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', creatorPrivyId)
              .maybeSingle();

      if (creatorResponse == null) {
        throw Exception(
          'Creator user not found with privy_id or wallet_address: $creatorPrivyId',
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
        'amount_in_sol': amountInSol,
        'platform_fee_sol': platformFee,
        'winner_amount_sol': winnerAmount,
        'expires_at':
            (expiresAt ?? DateTime.now().add(const Duration(days: 7)))
                .toIso8601String(),
        'status': 'pending',
        'escrow_address': escrowAddress,
        'multisig_address': escrowAddress,
        'vault_address': vaultAddress,
        'member1_address': member1Address,
        'member2_address': member2Address,
        // Store the current network for devnet/mainnet separation
        'network': NetworkConfig.currentNetwork,
      };

      // For blockchain challenges, store the blockchain ID in blockchain_id field, not id
      if (challengeId != null && challengeId.isNotEmpty) {
        insertData['blockchain_id'] = challengeId;
      }

      final response =
          await _client.from('challenges').insert(insertData).select().single();

      final createdChallenge = Challenge.fromJson(response);
      dev.log(
        'Challenge created with ID: ${createdChallenge.id}, Blockchain ID: $challengeId, Network: ${NetworkConfig.currentNetwork}',
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
      final currentNetwork = NetworkConfig.currentNetwork;

      dev.log(
        'Fetching challenges for wallet $userPrivyId on network $currentNetwork using RPC',
      );

      // Use the secure RPC function for server-side filtering
      // This ensures only challenges where user is creator OR witness are returned
      final response = await _client.rpc(
        'get_challenges_for_wallet',
        params: {'p_wallet_address': userPrivyId, 'p_network': currentNetwork},
      );

      if (response == null || response is! List) {
        dev.log('RPC returned no data or invalid format');
        return [];
      }

      dev.log(
        'RPC returned ${response.length} challenges for user $userPrivyId on network $currentNetwork',
      );

      return response.map((json) {
        final challengeData = Map<String, dynamic>.from(json);

        // Map the Supabase column names to what Challenge.fromJson expects
        // Database has amount_in_sol, platform_fee_sol, winner_amount_sol
        challengeData['amount_sol'] =
            challengeData['amount_in_sol'] ?? challengeData['amount'];
        challengeData['platform_fee'] = challengeData['platform_fee_sol'];
        challengeData['winner_amount'] = challengeData['winner_amount_sol'];
        challengeData['escrow_address'] =
            challengeData['escrow_address'] ?? challengeData['vault_address'];

        return Challenge.fromJson(challengeData);
      }).toList();
    } catch (e) {
      dev.log('Error getting challenges for user via RPC: $e');
      // Fallback to direct query if RPC fails
      return _getChallengesForUserFallback(userPrivyId);
    }
  }

  /// Fallback method using direct query if RPC fails
  static Future<List<Challenge>> _getChallengesForUserFallback(
    String userPrivyId,
  ) async {
    try {
      dev.log('Using fallback query for challenges');

      // Build query that checks multiple fields for MWA compatibility
      // User should see challenges where they are:
      // - creator (creator_wallet_address, member1_address)
      // - witness (member2_address)
      List<String> userConditions = [
        'creator_wallet_address.eq.$userPrivyId',
        'member1_address.eq.$userPrivyId',
        'member2_address.eq.$userPrivyId',
      ];

      // Also check if user has a UUID in the users table
      final userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', userPrivyId)
              .maybeSingle();

      if (userResponse != null) {
        final userId = userResponse['id'] as String;
        userConditions.add('creator_id.eq.$userId');
        userConditions.add('witness_id.eq.$userId');
      }

      final currentNetwork = NetworkConfig.currentNetwork;

      // Query with user conditions
      final response = await _client
          .from('challenges')
          .select('*')
          .or(userConditions.join(','));

      // Filter by network in memory
      final filteredResponse =
          response.where((challenge) {
            final challengeNetwork = challenge['network'] as String?;
            return challengeNetwork == null ||
                challengeNetwork == currentNetwork;
          }).toList();

      dev.log(
        'Fallback: ${response.length} total, ${filteredResponse.length} for network $currentNetwork',
      );

      return filteredResponse.map((json) {
          final challengeData = Map<String, dynamic>.from(json);
          challengeData['amount_sol'] =
              challengeData['amount_in_sol'] ?? challengeData['amount'];
          challengeData['platform_fee'] = challengeData['platform_fee_sol'];
          challengeData['winner_amount'] = challengeData['winner_amount_sol'];
          challengeData['escrow_address'] =
              challengeData['escrow_address'] ?? challengeData['vault_address'];
          return Challenge.fromJson(challengeData);
        }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      dev.log('Fallback query also failed: $e');
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
      dev.log('📤 UnifiedDB: updateChallenge($id) - $updates');
      await _client.from('challenges').update(updates).eq('id', id);
      dev.log('✅ UnifiedDB: updateChallenge($id) succeeded');
      return true;
    } catch (e) {
      dev.log('❌ UnifiedDB: Error updating challenge $id: $e');
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
      'updated_at': DateTime.now().toIso8601String(),
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

    dev.log('📤 UnifiedDB: Updating challenge $id with: $updates');
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
  /// Note: userPrivyId can be either a privy_id or wallet_address (for MWA auth)
  static Future<bool> addFriend({
    required String userPrivyId,
    required String friendName,
    required String friendWalletAddress,
  }) async {
    try {
      dev.log(
        'Adding friend: $friendName ($friendWalletAddress) for user: $userPrivyId',
      );

      // Get the user's database ID - check both privy_id and wallet_address
      var userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      // If not found by privy_id, try wallet_address (MWA auth)
      userResponse ??=
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        throw Exception(
          'User not found with privy_id or wallet_address: $userPrivyId',
        );
      }

      final userId = userResponse['id'] as String;

      // Check if friend exists by wallet address, if not create them
      final existingFriendResponse =
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', friendWalletAddress)
              .maybeSingle();

      String friendId;

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

        friendId = newFriendResponse['id'] as String;
        dev.log('Created new user for friend with ID: $friendId');
      } else {
        friendId = existingFriendResponse['id'] as String;

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
  /// Note: userPrivyId can be either a privy_id or wallet_address (for MWA auth)
  static Future<List<Map<String, String>>> getUserFriends(
    String id, {
    required String userPrivyId,
  }) async {
    try {
      dev.log('Getting friends for user: $userPrivyId');

      // Get user's database ID - check both privy_id and wallet_address
      var userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      // If not found by privy_id, try wallet_address (MWA auth)
      userResponse ??=
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        throw Exception(
          'User not found with privy_id or wallet_address: $userPrivyId',
        );
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
  /// Note: userPrivyId can be either a privy_id or wallet_address (for MWA auth)
  static Future<bool> removeFriend({
    required String userPrivyId,
    required String friendWalletAddress,
  }) async {
    try {
      dev.log(
        'Removing friend with wallet: $friendWalletAddress for user: $userPrivyId',
      );

      // Get user ID - check both privy_id and wallet_address (for MWA auth)
      var userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      // If not found by privy_id, try wallet_address (MWA auth)
      userResponse ??=
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', userPrivyId)
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
      // Get user ID - check both privy_id and wallet_address (for MWA auth)
      var userResponse =
          await _client
              .from('users')
              .select('id')
              .eq('privy_id', userPrivyId)
              .maybeSingle();

      // If not found by privy_id, try wallet_address (MWA auth)
      userResponse ??=
          await _client
              .from('users')
              .select('id')
              .eq('wallet_address', userPrivyId)
              .maybeSingle();

      if (userResponse == null) {
        dev.log(
          'DEBUG: User not found with privy_id or wallet_address: $userPrivyId',
        );
        return;
      }

      final userId = userResponse['id'];
      dev.log('DEBUG: Found user ID: $userId for identifier: $userPrivyId');

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
