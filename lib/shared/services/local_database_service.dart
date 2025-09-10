import 'dart:developer' as dev;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class LocalDatabaseService {
  static Database? _database;
  static const String _databaseName = 'chumbucket_local.db';
  static const int _databaseVersion = 2; // Increased version for friends table

  // Table names
  static const String _challengesTable = 'challenges';
  static const String _platformFeesTable = 'platform_fees';
  static const String _challengeTransactionsTable = 'challenge_transactions';
  static const String _challengeParticipantsTable = 'challenge_participants';
  static const String _friendsTable = 'friends';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    dev.log('Initializing local database at: $path');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    dev.log('Creating local database tables...');

    // Create challenges table
    await db.execute('''
      CREATE TABLE $_challengesTable (
        id TEXT PRIMARY KEY,
        creator_privy_id TEXT NOT NULL,
        participant_privy_id TEXT,
        participant_email TEXT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        amount_sol REAL NOT NULL CHECK (amount_sol > 0),
        platform_fee_sol REAL NOT NULL DEFAULT 0,
        winner_amount_sol REAL NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        completed_at TEXT,
        status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'funded', 'completed', 'failed', 'cancelled', 'expired')),
        multisig_address TEXT,
        vault_address TEXT,
        winner_privy_id TEXT,
        transaction_signature TEXT,
        fee_transaction_signature TEXT,
        metadata TEXT DEFAULT '{}'
      )
    ''');

    // Create platform_fees table
    await db.execute('''
      CREATE TABLE $_platformFeesTable (
        id TEXT PRIMARY KEY,
        challenge_id TEXT NOT NULL,
        amount_sol REAL NOT NULL,
        transaction_signature TEXT NOT NULL UNIQUE,
        collected_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        fee_percentage REAL NOT NULL DEFAULT 0.01,
        platform_wallet_address TEXT NOT NULL,
        FOREIGN KEY (challenge_id) REFERENCES $_challengesTable (id) ON DELETE CASCADE
      )
    ''');

    // Create challenge_transactions table
    await db.execute('''
      CREATE TABLE $_challengeTransactionsTable (
        id TEXT PRIMARY KEY,
        challenge_id TEXT NOT NULL,
        transaction_signature TEXT NOT NULL,
        transaction_type TEXT NOT NULL CHECK (transaction_type IN ('deposit', 'release', 'refund', 'platform_fee')),
        amount_sol REAL,
        from_address TEXT,
        to_address TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (challenge_id) REFERENCES $_challengesTable (id) ON DELETE CASCADE
      )
    ''');

    // Create challenge_participants table
    await db.execute('''
      CREATE TABLE $_challengeParticipantsTable (
        id TEXT PRIMARY KEY,
        challenge_id TEXT NOT NULL,
        user_privy_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('creator', 'participant')),
        wallet_address TEXT NOT NULL,
        joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        has_deposited INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (challenge_id) REFERENCES $_challengesTable (id) ON DELETE CASCADE
      )
    ''');

    // Create friends table
    await db.execute('''
      CREATE TABLE $_friendsTable (
        id TEXT PRIMARY KEY,
        user_privy_id TEXT NOT NULL,
        friend_name TEXT NOT NULL,
        friend_wallet_address TEXT NOT NULL,
        avatar_color TEXT NOT NULL,
        profile_image_path TEXT,
        added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Create indexes for better performance
    await db.execute(
      'CREATE INDEX idx_challenges_creator ON $_challengesTable(creator_privy_id)',
    );
    await db.execute(
      'CREATE INDEX idx_challenges_participant ON $_challengesTable(participant_privy_id)',
    );
    await db.execute(
      'CREATE INDEX idx_challenges_status ON $_challengesTable(status)',
    );
    await db.execute(
      'CREATE INDEX idx_challenges_created_at ON $_challengesTable(created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_challenges_expires_at ON $_challengesTable(expires_at)',
    );
    await db.execute(
      'CREATE INDEX idx_platform_fees_challenge ON $_platformFeesTable(challenge_id)',
    );
    await db.execute(
      'CREATE INDEX idx_challenge_transactions_challenge ON $_challengeTransactionsTable(challenge_id)',
    );
    await db.execute(
      'CREATE INDEX idx_challenge_participants_challenge ON $_challengeParticipantsTable(challenge_id)',
    );
    await db.execute(
      'CREATE INDEX idx_friends_user ON $_friendsTable(user_privy_id)',
    );
    await db.execute(
      'CREATE INDEX idx_friends_wallet ON $_friendsTable(friend_wallet_address)',
    );

    dev.log('Local database tables created successfully');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    dev.log('Upgrading local database from version $oldVersion to $newVersion');

    // Handle database upgrades here
    if (oldVersion < 2) {
      // Add friends table for version 2
      await db.execute('''
        CREATE TABLE $_friendsTable (
          id TEXT PRIMARY KEY,
          user_privy_id TEXT NOT NULL,
          friend_name TEXT NOT NULL,
          friend_wallet_address TEXT NOT NULL,
          avatar_color TEXT NOT NULL,
          profile_image_path TEXT,
          added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_friends_user ON $_friendsTable(user_privy_id)',
      );
      await db.execute(
        'CREATE INDEX idx_friends_wallet ON $_friendsTable(friend_wallet_address)',
      );

      dev.log('Added friends table in database upgrade');
    }
  }

  // Challenge operations
  static Future<String> insertChallenge(Challenge challenge) async {
    try {
      final db = await database;

      // Generate a UUID-like ID for local database
      final id =
          'local_${DateTime.now().millisecondsSinceEpoch}_${challenge.creatorId.hashCode.abs()}';

      final challengeWithId = Challenge(
        id: id,
        creatorId: challenge.creatorId,
        participantId: challenge.participantId,
        participantEmail: challenge.participantEmail,
        title: challenge.title,
        description: challenge.description,
        amount: challenge.amount,
        platformFee: challenge.platformFee,
        winnerAmount: challenge.winnerAmount,
        createdAt: challenge.createdAt,
        expiresAt: challenge.expiresAt,
        completedAt: challenge.completedAt,
        status: challenge.status,
        escrowAddress: challenge.escrowAddress,
        vaultAddress: challenge.vaultAddress,
        winnerId: challenge.winnerId,
        transactionSignature: challenge.transactionSignature,
        feeTransactionSignature: challenge.feeTransactionSignature,
      );

      await db.insert(_challengesTable, challengeWithId.toJson());
      dev.log('Challenge inserted with ID: $id');
      return id;
    } catch (e) {
      dev.log('Error inserting challenge: $e');
      rethrow;
    }
  }

  static Future<Challenge?> getChallenge(String id) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _challengesTable,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isNotEmpty) {
        return Challenge.fromJson(maps.first);
      }
      return null;
    } catch (e) {
      dev.log('Error getting challenge: $e');
      return null;
    }
  }

  static Future<List<Challenge>> getChallengesForUser(
    String userPrivyId,
  ) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _challengesTable,
        where: 'creator_privy_id = ? OR participant_privy_id = ?',
        whereArgs: [userPrivyId, userPrivyId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => Challenge.fromJson(map)).toList();
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
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _challengeParticipantsTable,
        columns: ['wallet_address'],
        where: 'challenge_id = ? AND user_privy_id = ?',
        whereArgs: [challengeId, participantPrivyId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return maps.first['wallet_address'] as String?;
      }
      return null;
    } catch (e) {
      dev.log('Error getting participant wallet address: $e');
      return null;
    }
  }

  static Future<int> updateChallenge(
    String id,
    Map<String, dynamic> updates,
  ) async {
    try {
      final db = await database;
      return await db.update(
        _challengesTable,
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      dev.log('Error updating challenge: $e');
      return 0;
    }
  }

  static Future<int> deleteChallenge(String id) async {
    try {
      final db = await database;
      return await db.delete(
        _challengesTable,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      dev.log('Error deleting challenge: $e');
      return 0;
    }
  }

  // Platform fee operations
  static Future<String> insertPlatformFee(PlatformFee fee) async {
    try {
      final db = await database;
      final id = 'fee_${DateTime.now().millisecondsSinceEpoch}';

      final feeData = fee.toJson();
      feeData['id'] = id;

      await db.insert(_platformFeesTable, feeData);
      dev.log('Platform fee inserted with ID: $id');
      return id;
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
      final db = await database;
      final id = 'tx_${DateTime.now().millisecondsSinceEpoch}';

      final transactionData = transaction.toJson();
      transactionData['id'] = id;

      await db.insert(_challengeTransactionsTable, transactionData);
      dev.log('Challenge transaction inserted with ID: $id');
      return id;
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
      final db = await database;
      final id = 'participant_${DateTime.now().millisecondsSinceEpoch}';

      final participantData = participant.toJson();
      participantData['id'] = id;

      await db.insert(_challengeParticipantsTable, participantData);
      dev.log('Challenge participant inserted with ID: $id');
      return id;
    } catch (e) {
      dev.log('Error inserting challenge participant: $e');
      rethrow;
    }
  }

  // Utility methods
  static Future<void> clearAllData() async {
    try {
      final db = await database;
      await db.delete(_challengeParticipantsTable);
      await db.delete(_challengeTransactionsTable);
      await db.delete(_platformFeesTable);
      await db.delete(_challengesTable);
      await db.delete(_friendsTable); // Clear friends table too
      dev.log('All local data cleared including friends');
    } catch (e) {
      dev.log('Error clearing data: $e');
    }
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // Database info for debugging
  static Future<Map<String, int>> getDatabaseStats() async {
    try {
      final db = await database;
      final challengeCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_challengesTable'),
          ) ??
          0;

      final feeCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_platformFeesTable'),
          ) ??
          0;

      final transactionCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $_challengeTransactionsTable',
            ),
          ) ??
          0;

      final participantCount =
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $_challengeParticipantsTable',
            ),
          ) ??
          0;

      return {
        'challenges': challengeCount,
        'fees': feeCount,
        'transactions': transactionCount,
        'participants': participantCount,
      };
    } catch (e) {
      dev.log('Error getting database stats: $e');
      return {};
    }
  }

  // Friends operations
  static Future<String> insertFriend({
    required String userPrivyId,
    required String friendName,
    required String friendWalletAddress,
    required String avatarColor,
    String? profileImagePath,
  }) async {
    try {
      final db = await database;
      final uuid = const Uuid();
      final id = uuid.v4(); // Generate UUID v4

      await db.insert(_friendsTable, {
        'id': id,
        'user_privy_id': userPrivyId,
        'friend_name': friendName,
        'friend_wallet_address': friendWalletAddress,
        'avatar_color': avatarColor,
        'profile_image_path': profileImagePath,
        'added_at': DateTime.now().toIso8601String(),
        'is_active': 1,
      });

      dev.log('Friend inserted with ID: $id');
      return id;
    } catch (e) {
      dev.log('Error inserting friend: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getFriends(
    String userPrivyId,
  ) async {
    try {
      final db = await database;
      final results = await db.query(
        _friendsTable,
        where: 'user_privy_id = ? AND is_active = ?',
        whereArgs: [userPrivyId, 1],
        orderBy: 'added_at DESC',
      );

      dev.log('Retrieved ${results.length} friends for user: $userPrivyId');
      return results;
    } catch (e) {
      dev.log('Error getting friends: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> getFriendByWallet(
    String walletAddress,
  ) async {
    try {
      final db = await database;
      final results = await db.query(
        _friendsTable,
        where: 'friend_wallet_address = ? AND is_active = ?',
        whereArgs: [walletAddress, 1],
        limit: 1,
      );

      if (results.isNotEmpty) {
        dev.log('Found friend with wallet: $walletAddress');
        return results.first;
      }
      return null;
    } catch (e) {
      dev.log('Error getting friend by wallet: $e');
      rethrow;
    }
  }

  static Future<bool> updateFriend({
    required String friendId,
    String? friendName,
    String? avatarColor,
    String? profileImagePath,
  }) async {
    try {
      final db = await database;
      final updateData = <String, dynamic>{};

      if (friendName != null) updateData['friend_name'] = friendName;
      if (avatarColor != null) updateData['avatar_color'] = avatarColor;
      if (profileImagePath != null)
        updateData['profile_image_path'] = profileImagePath;

      if (updateData.isEmpty) return false;

      final rowsAffected = await db.update(
        _friendsTable,
        updateData,
        where: 'id = ?',
        whereArgs: [friendId],
      );

      dev.log('Updated friend $friendId: $rowsAffected rows affected');
      return rowsAffected > 0;
    } catch (e) {
      dev.log('Error updating friend: $e');
      rethrow;
    }
  }

  static Future<bool> deleteFriend(String friendId) async {
    try {
      final db = await database;

      // Soft delete - set is_active to 0
      final rowsAffected = await db.update(
        _friendsTable,
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [friendId],
      );

      dev.log('Deleted friend $friendId: $rowsAffected rows affected');
      return rowsAffected > 0;
    } catch (e) {
      dev.log('Error deleting friend: $e');
      rethrow;
    }
  }
}
