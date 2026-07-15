import 'dart:convert';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'dart:typed_data';
import 'package:solana/solana.dart' as solana;
import 'package:solana/dto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/shared/models/models.dart';

/// Service to sync challenges from the blockchain
/// This ensures the local database stays in sync with on-chain state
///
/// IMPORTANT: This service is now updated to work with the Pinocchio program.
/// The account layout is 146 bytes with the following structure:
/// [0..8]:    discriminator "CHALL001"
/// [8..40]:   initiator (32 bytes)
/// [40..72]:  witness (32 bytes)
/// [72..104]: platform_fee_account (32 bytes)
/// [104..112]: amount_staked (8 bytes)
/// [112..120]: platform_fee (8 bytes)
/// [120..128]: winner_amount (8 bytes)
/// [128..136]: deadline (8 bytes)
/// [136]:     is_resolved (1 byte)
/// [137]:     initiator_won (1 byte)
/// [138]:     bump (1 byte)
/// [139..146]: reserved (7 bytes)
class BlockchainSyncService {
  // Pinocchio program ID (updated from legacy Anchor program)
  static const String ESCROW_PROGRAM_ID =
      'D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1';

  // Challenge account discriminator: "CHALL001" in ASCII
  // This matches the Pinocchio program's CHALLENGE_DISCRIMINATOR constant
  static const List<int> CHALLENGE_DISCRIMINATOR = [
    0x43, // 'C'
    0x48, // 'H'
    0x41, // 'A'
    0x4C, // 'L'
    0x4C, // 'L'
    0x30, // '0'
    0x30, // '0'
    0x31, // '1'
  ];

  // Pinocchio challenge account size (146 bytes)
  static const int CHALLENGE_ACCOUNT_SIZE = 146;

  // Caching & throttling
  static final Map<String, List<Challenge>> _cacheByWallet = {};
  static final Map<String, DateTime> _lastSyncAt = {};
  static const Duration _cacheTtl = Duration(seconds: 45);

  // Verbose logging and remote sync toggle via .env - PRODUCTION: DISABLED
  static bool get _verbose => false; // Disabled for production performance
  static bool get _remoteSyncEnabled =>
      false; // Disabled for production performance

  final solana.SolanaClient _solanaClient;
  final SupabaseClient _supabase;

  BlockchainSyncService({
    required solana.SolanaClient solanaClient,
    required SupabaseClient supabase,
  }) : _solanaClient = solanaClient,
       _supabase = supabase;

  /// Discover all challenges from the blockchain for a given user
  Future<List<Challenge>> discoverUserChallenges(
    String userWalletAddress,
  ) async {
    if (_verbose) {
      AppLogger.info(
        '🚨 DISCOVERY METHOD CALLED FOR: $userWalletAddress',
        tag: 'BlockchainSyncService',
      );
      AppLogger.info(
        '🔍 Discovering challenges from blockchain for user: $userWalletAddress',
      );
      AppLogger.info(
        '🌐 Network: ${_solanaClient.rpcClient}',
        tag: 'BlockchainSyncService',
      );
      AppLogger.info(
        '📡 Calling getProgramAccounts for program: $ESCROW_PROGRAM_ID',
        tag: 'BlockchainSyncService',
      );
      AppLogger.info(
        '🌐 RPC URL: ${_solanaClient.rpcClient}',
        tag: 'BlockchainSyncService',
      );
    }

    try {
      // First, verify the program actually exists
      try {
        final programAccountInfo = await _solanaClient.rpcClient.getAccountInfo(
          ESCROW_PROGRAM_ID,
          encoding: Encoding.base64,
        );

        if (programAccountInfo.value == null) {
          if (_verbose) {
            AppLogger.info(
              '❌ PROGRAM NOT FOUND ON NETWORK! -> $ESCROW_PROGRAM_ID',
              tag: 'BlockchainSyncService',
            );
          }
          return [];
        } else {
          if (_verbose) {
            AppLogger.info(
              '✅ Program found on network',
              tag: 'BlockchainSyncService',
            );
            AppLogger.info(
              '   Owner: ${programAccountInfo.value!.owner}',
              tag: 'BlockchainSyncService',
            );
            AppLogger.info(
              '   Executable: ${programAccountInfo.value!.executable}',
              tag: 'BlockchainSyncService',
            );
          }
        }
      } catch (e) {
        if (_verbose)
          AppLogger.info(
            '❌ Error checking program existence: $e',
            tag: 'BlockchainSyncService',
          );
        return [];
      }

      final programAccounts = await _solanaClient.rpcClient.getProgramAccounts(
        ESCROW_PROGRAM_ID,
        encoding: Encoding.base64,
        filters: [
          // Filter by account data size - Pinocchio Challenge accounts are 146 bytes
          ProgramDataFilter.dataSize(CHALLENGE_ACCOUNT_SIZE),
          // Filter by discriminator to only get Challenge accounts
          ProgramDataFilter.memcmp(offset: 0, bytes: CHALLENGE_DISCRIMINATOR),
        ],
      );

      if (_verbose)
        AppLogger.info(
          '📊 Found ${programAccounts.length} total Challenge accounts',
          tag: 'BlockchainSyncService',
        );

      if (programAccounts.isEmpty) {
        return [];
      }

      final challenges = <Challenge>[];

      for (final programAccount in programAccounts) {
        try {
          if (_verbose)
            AppLogger.info(
              '🔍 Processing account: ${programAccount.pubkey}',
              tag: 'BlockchainSyncService',
            );

          // Convert to map format for our decoder
          final accountMap = {
            'pubkey': programAccount.pubkey,
            'account': {
              'data': programAccount.account.data,
              'executable': programAccount.account.executable,
              'lamports': programAccount.account.lamports,
              'owner': programAccount.account.owner,
            },
          };

          if (_verbose) {
            AppLogger.info(
              '🔍 Account data type: ${programAccount.account.data.runtimeType}',
            );
          }

          final challenge = await _decodeChallengeAccount(
            accountMap,
            userWalletAddress,
          );

          if (challenge != null) {
            challenges.add(challenge);
            if (_verbose)
              AppLogger.info(
                '✅ Successfully decoded challenge: ${challenge.id}',
                tag: 'BlockchainSyncService',
              );
          } else {
            if (_verbose) {
              AppLogger.info(
                '⚠️ Challenge was null after decoding for account: ${programAccount.pubkey}',
              );
            }
          }
        } catch (e) {
          if (_verbose) {
            AppLogger.info(
              '⚠️ Failed to decode challenge account ${programAccount.pubkey}: $e',
            );
            AppLogger.info(
              '⚠️ Stack trace: ${StackTrace.current}',
              tag: 'BlockchainSyncService',
            );
          }
        }
      }

      if (_verbose)
        AppLogger.info(
          '✅ Discovered ${challenges.length} challenges for user',
          tag: 'BlockchainSyncService',
        );
      return challenges;
    } catch (e) {
      AppLogger.debug(
        '❌ Error discovering challenges from blockchain: $e',
        tag: 'BlockchainSyncService',
      );
      return [];
    }
  }

  /// Decode a Challenge account and convert to local Challenge model
  Future<Challenge?> _decodeChallengeAccount(
    Map<String, dynamic> programAccount,
    String userWalletAddress,
  ) async {
    final account = programAccount['account'] as Map<String, dynamic>;
    final accountData = account['data'];
    final pubkey = programAccount['pubkey'] as String;

    if (_verbose)
      AppLogger.info(
        '🔍 Decoding account: $pubkey for user: $userWalletAddress',
        tag: 'BlockchainSyncService',
      );

    try {
      if (accountData == null) return null;

      late Uint8List data;
      if (accountData is List<int>) {
        data = Uint8List.fromList(accountData);
        if (_verbose)
          AppLogger.info(
            '✅ Account data is List<int> with ${data.length} bytes',
            tag: 'BlockchainSyncService',
          );
      } else if (accountData is String) {
        // Handle base64 encoded data
        try {
          data = base64Decode(accountData);
          if (_verbose) {
            AppLogger.info(
              '✅ Account data is base64 string, decoded to ${data.length} bytes',
            );
          }
        } catch (e) {
          if (_verbose)
            AppLogger.info(
              '⚠️ Failed to decode base64 data: $pubkey - $e',
              tag: 'BlockchainSyncService',
            );
          return null;
        }
      } else if (accountData.runtimeType.toString().contains(
        'BinaryAccountData',
      )) {
        // Handle BinaryAccountData from solana package
        try {
          final dynamic binaryData = (accountData as dynamic).data;
          if (binaryData is List<int>) {
            data = Uint8List.fromList(binaryData);
            if (_verbose) {
              AppLogger.info(
                '✅ Account data is BinaryAccountData with ${data.length} bytes',
              );
            }
          } else if (binaryData is String) {
            data = base64Decode(binaryData);
            if (_verbose) {
              AppLogger.info(
                '✅ Account data is BinaryAccountData (base64) with ${data.length} bytes',
              );
            }
          } else {
            if (_verbose) {
              AppLogger.info(
                '⚠️ BinaryAccountData contains unknown data type: ${binaryData.runtimeType}',
              );
            }
            return null;
          }
        } catch (e) {
          if (_verbose) {
            AppLogger.info(
              '⚠️ Failed to extract data from BinaryAccountData: $pubkey - $e',
            );
          }
          return null;
        }
      } else {
        if (_verbose) {
          AppLogger.info(
            '⚠️ Unknown account data type: $pubkey - ${accountData.runtimeType}',
          );
        }
        return null;
      }

      // Verify discriminator
      if (data.length < 8) return null;

      final discriminator = data.sublist(0, 8);
      if (!_listEquals(discriminator, CHALLENGE_DISCRIMINATOR)) {
        if (_verbose) {
          AppLogger.info(
            '⚠️ Invalid discriminator for account: $pubkey',
            tag: 'BlockchainSyncService',
          );
          AppLogger.info(
            '   Expected: $CHALLENGE_DISCRIMINATOR',
            tag: 'BlockchainSyncService',
          );
          AppLogger.info(
            '   Found: $discriminator',
            tag: 'BlockchainSyncService',
          );
        }
        return null;
      }

      // Decode Pinocchio Challenge struct fields
      // Layout (146 bytes total):
      // [0..8]:    discriminator \"CHALL001\"
      // [8..40]:   initiator (32 bytes)
      // [40..72]:  witness (32 bytes)
      // [72..104]: platform_fee_account (32 bytes)
      // [104..112]: amount_staked (8 bytes)
      // [112..120]: platform_fee (8 bytes)
      // [120..128]: winner_amount (8 bytes)
      // [128..136]: deadline (8 bytes)
      // [136]:     is_resolved (1 byte)
      // [137]:     initiator_won (1 byte)
      // [138]:     bump (1 byte)
      // [139..146]: reserved (7 bytes)
      if (data.length < CHALLENGE_ACCOUNT_SIZE) {
        if (_verbose) {
          AppLogger.info(
            '⚠️ Challenge account data incomplete: $pubkey (${data.length} bytes, need $CHALLENGE_ACCOUNT_SIZE)',
          );
        }
        return null;
      }

      int offset = 8; // Skip discriminator

      // Initiator (32 bytes)
      final initiatorBytes = data.sublist(offset, offset + 32);
      final initiatorAddress =
          solana.Ed25519HDPublicKey(initiatorBytes).toBase58();
      offset += 32;

      // Witness (32 bytes)
      final witnessBytes = data.sublist(offset, offset + 32);
      final witnessAddress = solana.Ed25519HDPublicKey(witnessBytes).toBase58();
      offset += 32;

      // Platform fee account (32 bytes) - skip, we already know it
      offset += 32;

      if (_verbose) {
        AppLogger.info(
          '🔍 Challenge participants:',
          tag: 'BlockchainSyncService',
        );
        AppLogger.info(
          '   Initiator: $initiatorAddress',
          tag: 'BlockchainSyncService',
        );
        AppLogger.info(
          '   Witness: $witnessAddress',
          tag: 'BlockchainSyncService',
        );
        AppLogger.info(
          '   Current user: $userWalletAddress',
          tag: 'BlockchainSyncService',
        );
      }

      // Check if user is involved in this challenge
      final isUserInitiator = initiatorAddress == userWalletAddress;
      final isUserWitness = witnessAddress == userWalletAddress;

      if (_verbose) {
        AppLogger.info(
          '🔍 User involvement check:',
          tag: 'BlockchainSyncService',
        );
        AppLogger.info(
          '   Is user initiator: $isUserInitiator',
          tag: 'BlockchainSyncService',
        );
        AppLogger.info(
          '   Is user witness: $isUserWitness',
          tag: 'BlockchainSyncService',
        );
      }

      if (!isUserInitiator && !isUserWitness) {
        // User is not involved in this challenge
        if (_verbose)
          AppLogger.info(
            '❌ User not involved in this challenge, filtering out',
            tag: 'BlockchainSyncService',
          );
        return null;
      }

      // Pinocchio layout (after platform_fee_account at offset 104):
      // [104..112]: amount_staked (8 bytes)
      // [112..120]: platform_fee (8 bytes)
      // [120..128]: winner_amount (8 bytes)
      // [128..136]: deadline (8 bytes)
      // [136]:     is_resolved (1 byte)
      // [137]:     initiator_won (1 byte)

      // Amount staked (8 bytes, little endian u64) - this is the original staked amount
      final amountStaked = _readU64LE(data, offset);
      offset += 8;

      // Platform fee (8 bytes, little endian u64)
      final platformFee = _readU64LE(data, offset);
      offset += 8;

      // Winner amount (8 bytes, little endian u64) - amount after fee deduction
      final winnerAmount = _readU64LE(data, offset);
      offset += 8;

      // Deadline (8 bytes, little endian i64)
      final deadline = _readI64LE(data, offset);
      offset += 8;

      // is_resolved (1 byte boolean)
      final isResolved = data[offset] != 0;
      offset += 1;

      // initiator_won (1 byte boolean) - only meaningful if resolved
      final initiatorWon = data[offset] != 0;

      // Convert deadline to proper DateTime - check if it's in seconds or milliseconds
      late DateTime deadlineDateTime;
      if (deadline > 1000000000000) {
        // Looks like milliseconds
        deadlineDateTime = DateTime.fromMillisecondsSinceEpoch(deadline);
      } else {
        // Looks like seconds
        deadlineDateTime = DateTime.fromMillisecondsSinceEpoch(deadline * 1000);
      }

      // Estimate creation time (7 days before deadline)
      final estimatedCreationTime = deadlineDateTime.subtract(
        const Duration(days: 7),
      );

      AppLogger.debug(
        '📝 Decoded challenge: $pubkey',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Initiator: $initiatorAddress',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Witness: $witnessAddress',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Amount Staked: ${amountStaked / solana.lamportsPerSol} SOL',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Winner Amount: ${winnerAmount / solana.lamportsPerSol} SOL',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Platform Fee: ${platformFee / solana.lamportsPerSol} SOL',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Deadline: $deadlineDateTime',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Created (est): $estimatedCreationTime',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Resolved: $isResolved',
        tag: 'BlockchainSyncService',
      );
      AppLogger.debug(
        '  - Initiator Won: $initiatorWon',
        tag: 'BlockchainSyncService',
      );

      // Convert to local Challenge model
      // Determine status based on on-chain state
      ChallengeStatus status;
      if (isResolved) {
        // Challenge has been resolved
        status =
            initiatorWon ? ChallengeStatus.completed : ChallengeStatus.failed;
      } else if (DateTime.now().isAfter(deadlineDateTime)) {
        // Deadline has passed but not resolved
        status = ChallengeStatus.expired;
      } else {
        // Active challenge
        status = ChallengeStatus.active;
      }

      // Use default description for discovered challenges
      // (Challenge descriptions are now stored in Supabase)
      const challengeDescription = 'Challenge discovered from blockchain';
      const challengeTitle = 'On-chain Challenge';

      return Challenge(
        id: 'onchain_$pubkey', // Prefix to indicate on-chain source
        title: challengeTitle,
        description: challengeDescription,
        amount: amountStaked / solana.lamportsPerSol, // Original staked amount
        // IMPORTANT: Use actual wallet address, not placeholder string
        creatorId: initiatorAddress, // Always the initiator's wallet address
        member1Address:
            initiatorAddress, // CRITICAL: Initiator wallet for resolution
        status: status,
        createdAt: estimatedCreationTime,
        expiresAt: deadlineDateTime,
        escrowAddress: pubkey, // The challenge account itself
        vaultAddress: ESCROW_PROGRAM_ID, // Program ID as vault reference
        platformFee: platformFee / solana.lamportsPerSol,
        winnerAmount:
            winnerAmount / solana.lamportsPerSol, // Net amount after fee
        participantEmail: witnessAddress, // Witness wallet address
        witnessAddress:
            witnessAddress, // CRITICAL: Witness wallet for resolution
        participantId: null,
        winnerId:
            isResolved
                ? (initiatorWon ? initiatorAddress : witnessAddress)
                : null,
      );
    } catch (e) {
      AppLogger.debug(
        '❌ Error decoding challenge account $pubkey: $e',
        tag: 'BlockchainSyncService',
      );
      return null;
    }
  }

  /// Sync discovered challenges with local database
  Future<void> syncChallengesWithDatabase(
    List<Challenge> onChainChallenges,
    String userId,
  ) async {
    // Skip remote sync unless explicitly enabled
    if (!_remoteSyncEnabled) {
      if (_verbose)
        AppLogger.debug(
          '⏭️ Remote sync disabled. Skipping Supabase writes.',
          tag: 'BlockchainSyncService',
        );
      return;
    }

    try {
      AppLogger.debug(
        '🔄 Syncing ${onChainChallenges.length} on-chain challenges with database',
      );

      for (final challenge in onChainChallenges) {
        // Check if challenge already exists in database
        final existingChallenge =
            await _supabase
                .from('challenges')
                .select()
                .eq('escrow_address', challenge.escrowAddress!)
                .maybeSingle();

        if (existingChallenge == null) {
          // Challenge not in database, insert it
          AppLogger.debug(
            '➕ Adding new on-chain challenge to database: ${challenge.escrowAddress}',
          );

          await _supabase.from('challenges').insert({
            'id': challenge.id,
            'title': challenge.title.isEmpty ? 'Challenge' : challenge.title,
            'description':
                challenge.description.isEmpty
                    ? 'Challenge recovered from blockchain'
                    : challenge.description,
            'amount': challenge.amount, // NOT NULL column
            'amount_in_sol': challenge.amount,
            'creator_id':
                userId, // Current user as creator for discovered challenges
            'status': challenge.status.toString().split('.').last,
            'created_at': challenge.createdAt.toIso8601String(),
            'expires_at': challenge.expiresAt.toIso8601String(),
            'escrow_address': challenge.escrowAddress,
            'multisig_address': challenge.escrowAddress,
            'vault_address': challenge.vaultAddress,
            'platform_fee_sol': challenge.platformFee,
            'winner_amount_sol': challenge.winnerAmount,
            'member1_address': challenge.creatorId,
            'member2_address': challenge.participantEmail,
            'winner_id': challenge.winnerId,
          });
        } else {
          // Challenge exists, update status if different but preserve original descriptions
          final dbStatus = existingChallenge['status'] as String;
          final onChainStatus = challenge.status.toString().split('.').last;

          if (dbStatus != onChainStatus) {
            AppLogger.debug(
              '🔄 Updating challenge status: ${challenge.escrowAddress} -> $onChainStatus',
            );

            // Only update status and winner, preserve existing title/description
            await _supabase
                .from('challenges')
                .update({
                  'status': onChainStatus,
                  'winner_privy_id': challenge.winnerId,
                  'winner_amount_sol': challenge.winnerAmount,
                })
                .eq('multisig_address', challenge.escrowAddress!);
          }
        }
      }

      AppLogger.debug(
        '✅ Database sync completed',
        tag: 'BlockchainSyncService',
      );
    } catch (e) {
      AppLogger.debug(
        '❌ Error syncing challenges with database: $e',
        tag: 'BlockchainSyncService',
      );
    }
  }

  /// Mark challenges as completed when their on-chain account no longer exists
  /// This happens when a challenge is resolved - the Pinocchio program closes the account
  Future<void> _markClosedChallengesAsCompleted(
    String userWalletAddress,
    String userId,
  ) async {
    try {
      // Get all active/pending challenges from database that have an escrow address
      final activeFromDb = await _supabase
          .from('challenges')
          .select(
            'id, escrow_address, multisig_address, status, member1_address, member2_address',
          )
          .or(
            'creator_wallet_address.eq.$userWalletAddress,member1_address.eq.$userWalletAddress,member2_address.eq.$userWalletAddress',
          )
          .inFilter('status', ['active', 'pending', 'funded', 'accepted']);

      if (activeFromDb.isEmpty) {
        AppLogger.debug(
          'No active challenges to check for closure',
          tag: 'BlockchainSyncService',
        );
        return;
      }

      AppLogger.info(
        '🔍 Checking ${activeFromDb.length} active challenges for closure',
        tag: 'BlockchainSyncService',
      );

      for (final challenge in activeFromDb) {
        final escrowAddress =
            challenge['escrow_address'] ?? challenge['multisig_address'];
        if (escrowAddress == null || escrowAddress.toString().isEmpty) continue;

        try {
          // Check if the account still exists on-chain
          final accountInfo = await _solanaClient.rpcClient.getAccountInfo(
            escrowAddress,
            encoding: Encoding.base64,
          );

          if (accountInfo.value == null) {
            // Account is closed = challenge was resolved!
            AppLogger.info(
              '✅ Challenge account closed (resolved): $escrowAddress',
              tag: 'BlockchainSyncService',
            );

            // Mark as completed in database
            // We assume initiator won if the account is closed (they got refunded)
            // In practice, the actual winner info should come from resolution tx
            await _supabase
                .from('challenges')
                .update({
                  'status': 'completed',
                  'completed_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                })
                .eq('id', challenge['id']);

            AppLogger.info(
              '📝 Updated challenge ${challenge['id']} to completed',
              tag: 'BlockchainSyncService',
            );
          }
        } catch (e) {
          // If we get an error checking the account, log but don't fail
          AppLogger.debug(
            '⚠️ Error checking account $escrowAddress: $e',
            tag: 'BlockchainSyncService',
          );
        }
      }
    } catch (e) {
      AppLogger.error(
        '❌ Error marking closed challenges: $e',
        tag: 'BlockchainSyncService',
      );
    }
  }

  /// Full sync process: discover from blockchain and update database
  Future<List<Challenge>> fullSyncForUser(
    String userWalletAddress,
    String userId,
  ) async {
    final now = DateTime.now();
    final lastSync = _lastSyncAt[userWalletAddress];
    if (lastSync != null && now.difference(lastSync) < _cacheTtl) {
      if (_verbose) {
        AppLogger.info(
          '🧠 Using cached discovery for $userWalletAddress',
          tag: 'BlockchainSyncService',
        );
      }
      return _cacheByWallet[userWalletAddress] ?? [];
    }

    if (_verbose) {
      AppLogger.info(
        '🚨 FULL SYNC STARTED FOR: $userWalletAddress, USER ID: $userId',
        tag: 'BlockchainSyncService',
      );
      AppLogger.info(
        '🚀 Starting full blockchain sync for user: $userWalletAddress',
        tag: 'BlockchainSyncService',
      );
      AppLogger.info(
        '🚨 ABOUT TO CALL discoverUserChallenges...',
        tag: 'BlockchainSyncService',
      );
    }

    try {
      // Discover challenges from blockchain
      final onChainChallenges = await discoverUserChallenges(userWalletAddress);
      if (_verbose) {
        AppLogger.info(
          '🚨 DISCOVERY RETURNED: ${onChainChallenges.length} challenges',
          tag: 'BlockchainSyncService',
        );
        AppLogger.info(
          '🚨 ABOUT TO SYNC WITH DATABASE...',
          tag: 'BlockchainSyncService',
        );
      }

      // Update cache
      _cacheByWallet[userWalletAddress] = onChainChallenges;
      _lastSyncAt[userWalletAddress] = DateTime.now();

      // Sync with database (optional)
      await syncChallengesWithDatabase(onChainChallenges, userId);

      // CRITICAL: Check for resolved challenges (closed accounts)
      // When a challenge is resolved on-chain, the account is closed.
      // We need to mark those as completed in the database.
      await _markClosedChallengesAsCompleted(userWalletAddress, userId);

      if (_verbose)
        AppLogger.info(
          '🚨 DATABASE SYNC COMPLETED',
          tag: 'BlockchainSyncService',
        );

      AppLogger.debug(
        '✅ Full sync completed. Found ${onChainChallenges.length} challenges',
      );
      return onChainChallenges;
    } catch (e, stackTrace) {
      AppLogger.info('❌ Error in full sync: $e', tag: 'BlockchainSyncService');
      AppLogger.info(
        '❌ Stack trace: $stackTrace',
        tag: 'BlockchainSyncService',
      );
      return [];
    }
  }

  /// Get real-time challenge status from blockchain
  Future<Map<String, dynamic>?> getChallengeStatusFromBlockchain(
    String challengeAddress,
  ) async {
    try {
      final accountInfo = await _solanaClient.rpcClient.getAccountInfo(
        challengeAddress,
        encoding: Encoding.base64,
      );

      if (accountInfo.value == null) {
        AppLogger.debug(
          '⚠️ Challenge account not found: $challengeAddress',
          tag: 'BlockchainSyncService',
        );
        return null;
      }

      final accountData = accountInfo.value!.data;
      if (accountData == null) {
        return null;
      }

      // Handle account data - extract the raw bytes
      late Uint8List data;

      // AccountData should have a data property that contains the bytes
      if (accountData.runtimeType.toString().contains('BinaryAccountData')) {
        // For binary account data, get the data property
        final dynamic binaryData = (accountData as dynamic).data;
        if (binaryData is List<int>) {
          data = Uint8List.fromList(binaryData);
        } else {
          return null;
        }
      } else if (accountData.runtimeType.toString().contains(
        'ParsedAccountData',
      )) {
        // For parsed data, we can't easily get raw bytes
        return null;
      } else {
        // Try to handle as dynamic
        final dynamic rawData = (accountData as dynamic).data;
        if (rawData is List<int>) {
          data = Uint8List.fromList(rawData);
        } else if (rawData is String) {
          data = base64Decode(rawData);
        } else {
          return null;
        }
      }

      // Decode using Pinocchio layout (146 bytes)
      if (data.length < CHALLENGE_ACCOUNT_SIZE) return null;

      // Skip discriminator(8) + initiator(32) + witness(32) + platform_fee_account(32)
      int offset = 8 + 32 + 32 + 32; // = 104

      final amountStaked = _readU64LE(data, offset);
      offset += 8;
      final platformFee = _readU64LE(data, offset);
      offset += 8;
      final winnerAmount = _readU64LE(data, offset);
      offset += 8;
      final deadline = _readI64LE(data, offset);
      offset += 8;
      final isResolved = data[offset] != 0;
      offset += 1;
      final initiatorWon = data[offset] != 0;

      return {
        'exists': true,
        'isResolved': isResolved,
        'initiatorWon': initiatorWon,
        'amountStaked': amountStaked,
        'winnerAmount': winnerAmount,
        'platformFee': platformFee,
        'deadline': deadline,
      };
    } catch (e) {
      AppLogger.debug(
        '❌ Error getting challenge status from blockchain: $e',
        tag: 'BlockchainSyncService',
      );
      return null;
    }
  }

  // Helper methods for reading little-endian integers
  int _readU64LE(Uint8List data, int offset) {
    final view = ByteData.sublistView(data, offset, offset + 8);
    return view.getUint64(0, Endian.little);
  }

  int _readI64LE(Uint8List data, int offset) {
    final view = ByteData.sublistView(data, offset, offset + 8);
    return view.getInt64(0, Endian.little);
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
