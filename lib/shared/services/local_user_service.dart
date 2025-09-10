import 'dart:developer' as dev;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalUserService {
  static Database? _database;
  static const String _databaseName = 'chumbucket_users.db';
  static const int _databaseVersion = 1;
  static const String _usersTable = 'users';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    dev.log('Initializing local user database at: $path');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    dev.log('Creating local user tables...');

    await db.execute('''
      CREATE TABLE $_usersTable (
        privy_id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        full_name TEXT,
        bio TEXT,
        wallet_address TEXT,
        profile_image_url TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_login TEXT,
        onboarding_completed INTEGER NOT NULL DEFAULT 0,
        settings TEXT DEFAULT '{}'
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_users_email ON $_usersTable(email)');
    await db.execute(
      'CREATE INDEX idx_users_wallet ON $_usersTable(wallet_address)',
    );

    dev.log('Local user tables created successfully');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    dev.log('Upgrading user database from version $oldVersion to $newVersion');
  }

  static Future<UserProfile> upsertUser({
    required String privyId,
    required String email,
    String? fullName,
    String? bio,
    String? walletAddress,
    String? profileImageUrl,
    bool? onboardingCompleted,
    Map<String, dynamic>? settings,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();

      // Check if user exists
      final existingUser = await getUser(privyId);

      final userData = {
        'privy_id': privyId,
        'email': email,
        'full_name': fullName ?? existingUser?.fullName,
        'bio': bio ?? existingUser?.bio,
        'wallet_address': walletAddress ?? existingUser?.walletAddress,
        'profile_image_url': profileImageUrl ?? existingUser?.profileImageUrl,
        'updated_at': now,
        'last_login': now,
        'onboarding_completed':
            (onboardingCompleted ?? existingUser?.onboardingCompleted ?? false)
                ? 1
                : 0,
        'settings':
            settings != null
                ? _mapToJson(settings)
                : (existingUser?.settings != null
                    ? _mapToJson(existingUser!.settings!)
                    : '{}'),
      };

      if (existingUser == null) {
        // Create new user
        userData['created_at'] = now;
        await db.insert(_usersTable, userData);
        dev.log('Created new local user: $privyId');
      } else {
        // Update existing user
        await db.update(
          _usersTable,
          userData,
          where: 'privy_id = ?',
          whereArgs: [privyId],
        );
        dev.log('Updated local user: $privyId');
      }

      return UserProfile(
        privyId: privyId,
        email: email,
        fullName: userData['full_name'] as String?,
        bio: userData['bio'] as String?,
        walletAddress: userData['wallet_address'] as String?,
        profileImageUrl: userData['profile_image_url'] as String?,
        createdAt: DateTime.parse(userData['created_at'] as String? ?? now),
        updatedAt: DateTime.parse(userData['updated_at'] as String),
        lastLogin: DateTime.parse(userData['last_login'] as String),
        onboardingCompleted: userData['onboarding_completed'] == 1,
        settings: settings ?? existingUser?.settings ?? {},
      );
    } catch (e) {
      dev.log('Error upserting user: $e');
      rethrow;
    }
  }

  static Future<UserProfile?> getUser(String privyId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _usersTable,
        where: 'privy_id = ?',
        whereArgs: [privyId],
      );

      if (maps.isNotEmpty) {
        return UserProfile.fromLocalJson(maps.first);
      }
      return null;
    } catch (e) {
      dev.log('Error getting user: $e');
      return null;
    }
  }

  static Future<UserProfile?> getUserByEmail(String email) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _usersTable,
        where: 'email = ?',
        whereArgs: [email],
      );

      if (maps.isNotEmpty) {
        return UserProfile.fromLocalJson(maps.first);
      }
      return null;
    } catch (e) {
      dev.log('Error getting user by email: $e');
      return null;
    }
  }

  static Future<List<UserProfile>> getAllUsers() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _usersTable,
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => UserProfile.fromLocalJson(map)).toList();
    } catch (e) {
      dev.log('Error getting all users: $e');
      return [];
    }
  }

  static Future<int> updateUser(
    String privyId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final db = await database;
      updates['updated_at'] = DateTime.now().toIso8601String();

      return await db.update(
        _usersTable,
        updates,
        where: 'privy_id = ?',
        whereArgs: [privyId],
      );
    } catch (e) {
      dev.log('Error updating user: $e');
      return 0;
    }
  }

  static Future<void> clearAllUsers() async {
    try {
      final db = await database;
      await db.delete(_usersTable);
      dev.log('All local users cleared');
    } catch (e) {
      dev.log('Error clearing users: $e');
    }
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // Helper method to convert Map to JSON string
  static String _mapToJson(Map<String, dynamic> map) {
    try {
      return map.toString(); // Simple string representation for now
    } catch (e) {
      return '{}';
    }
  }
}

// Enhanced UserProfile model for local storage
class UserProfile {
  final String privyId;
  final String email;
  final String? fullName;
  final String? bio;
  final String? walletAddress;
  final String? profileImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastLogin;
  final bool onboardingCompleted;
  final Map<String, dynamic>? settings;

  const UserProfile({
    required this.privyId,
    required this.email,
    this.fullName,
    this.bio,
    this.walletAddress,
    this.profileImageUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.lastLogin,
    required this.onboardingCompleted,
    this.settings,
  });

  factory UserProfile.fromLocalJson(Map<String, dynamic> json) {
    return UserProfile(
      privyId: json['privy_id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      bio: json['bio'] as String?,
      walletAddress: json['wallet_address'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastLogin: DateTime.parse(json['last_login'] as String),
      onboardingCompleted: (json['onboarding_completed'] as int) == 1,
      settings: {}, // TODO: Parse JSON string if needed
    );
  }

  Map<String, dynamic> toLocalJson() {
    return {
      'privy_id': privyId,
      'email': email,
      'full_name': fullName,
      'bio': bio,
      'wallet_address': walletAddress,
      'profile_image_url': profileImageUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_login': lastLogin.toIso8601String(),
      'onboarding_completed': onboardingCompleted ? 1 : 0,
      'settings': settings?.toString() ?? '{}',
    };
  }
}
