import 'dart:developer' as dev;
import 'dart:math';
import 'package:chumbucket/services/local_database_service.dart';

class LocalFriendsService {
  // Available avatar colors
  static const List<String> _avatarColors = [
    '#FFBE55', // Gold
    '#FF5A55', // Red
    '#55A9FF', // Blue
    '#FF55A9', // Pink
    '#55FFBE', // Green
    '#A955FF', // Purple
    '#FFD700', // Golden
    '#32CD32', // Lime
    '#FF6347', // Tomato
    '#4169E1', // Royal Blue
  ];

  // Available profile images
  static const List<String> _profileImages = [
    'assets/images/ai_gen/profile_images/1.png',
    'assets/images/ai_gen/profile_images/2.png',
    'assets/images/ai_gen/profile_images/3.png',
    'assets/images/ai_gen/profile_images/4.png',
    'assets/images/ai_gen/profile_images/5.png',
  ];

  static String _getRandomAvatarColor() {
    final random = Random();
    return _avatarColors[random.nextInt(_avatarColors.length)];
  }

  static String _getRandomProfileImage() {
    final random = Random();
    return _profileImages[random.nextInt(_profileImages.length)];
  }

  // Add a new friend
  static Future<String> addFriend({
    required String userPrivyId,
    required String friendName,
    required String friendWalletAddress,
    String? avatarColor,
    String? profileImagePath,
  }) async {
    try {
      // Generate random avatar color and profile image if not provided
      final finalAvatarColor = avatarColor ?? _getRandomAvatarColor();
      final finalProfileImage = profileImagePath ?? _getRandomProfileImage();

      final friendId = await LocalDatabaseService.insertFriend(
        userPrivyId: userPrivyId,
        friendName: friendName,
        friendWalletAddress: friendWalletAddress,
        avatarColor: finalAvatarColor,
        profileImagePath: finalProfileImage,
      );

      dev.log('Added friend $friendName with wallet $friendWalletAddress');
      return friendId;
    } catch (e) {
      dev.log('Error adding friend: $e');
      rethrow;
    }
  }

  // Get all friends for a user
  static Future<List<Map<String, dynamic>>> getFriends(
    String userPrivyId,
  ) async {
    try {
      dev.log('LocalFriendsService: Getting friends for user: $userPrivyId');
      final friends = await LocalDatabaseService.getFriends(userPrivyId);
      dev.log(
        'LocalFriendsService: Found ${friends.length} friends in database',
      );
      return friends;
    } catch (e) {
      dev.log('Error getting friends: $e');
      rethrow;
    }
  }

  // Get friend by wallet address
  static Future<Map<String, dynamic>?> getFriendByWallet(
    String walletAddress,
  ) async {
    try {
      return await LocalDatabaseService.getFriendByWallet(walletAddress);
    } catch (e) {
      dev.log('Error getting friend by wallet: $e');
      rethrow;
    }
  }

  // Update friend information
  static Future<bool> updateFriend({
    required String friendId,
    String? friendName,
    String? avatarColor,
    String? profileImagePath,
  }) async {
    try {
      return await LocalDatabaseService.updateFriend(
        friendId: friendId,
        friendName: friendName,
        avatarColor: avatarColor,
        profileImagePath: profileImagePath,
      );
    } catch (e) {
      dev.log('Error updating friend: $e');
      rethrow;
    }
  }

  // Remove a friend
  static Future<bool> removeFriend(String friendId) async {
    try {
      return await LocalDatabaseService.deleteFriend(friendId);
    } catch (e) {
      dev.log('Error removing friend: $e');
      rethrow;
    }
  }

  // Initialize with some default friends for testing
  static Future<void> initializeDefaultFriends(String userPrivyId) async {
    try {
      // Check if user already has friends
      final existingFriends = await getFriends(userPrivyId);
      if (existingFriends.isNotEmpty) {
        dev.log(
          'User already has ${existingFriends.length} friends, skipping initialization',
        );
        return;
      }

      // Add some default friends with REAL wallet addresses for testing
      // These are public Solana wallet addresses that can be used for testing
      final defaultFriends = [
        {
          'name': 'Alice',
          'wallet': '11111111111111111111111111111112', // System Program
          'color': '#FFBE55',
          'image': 'assets/images/ai_gen/profile_images/1.png',
        },
        {
          'name': 'Bob',
          'wallet':
              'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', // Token Program
          'color': '#FF5A55',
          'image': 'assets/images/ai_gen/profile_images/2.png',
        },
        {
          'name': 'Charlie',
          'wallet':
              'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL', // Associated Token Program
          'color': '#55A9FF',
          'image': 'assets/images/ai_gen/profile_images/3.png',
        },
        {
          'name': 'Diana',
          'wallet':
              'SysvarRent111111111111111111111111111111111', // Rent Sysvar
          'color': '#FF55A9',
          'image': 'assets/images/ai_gen/profile_images/4.png',
        },
        {
          'name': 'Eve',
          'wallet':
              'SysvarC1ock11111111111111111111111111111111', // Clock Sysvar
          'color': '#55FFBE',
          'image': 'assets/images/ai_gen/profile_images/5.png',
        },
      ];

      for (final friend in defaultFriends) {
        await addFriend(
          userPrivyId: userPrivyId,
          friendName: friend['name']!,
          friendWalletAddress: friend['wallet']!,
          avatarColor: friend['color']!,
          profileImagePath: friend['image']!,
        );
      }

      dev.log('Initialized ${defaultFriends.length} default friends for user');
    } catch (e) {
      dev.log('Error initializing default friends: $e');
      // Don't rethrow - this is not critical
    }
  }

  // Convert database friend record to UI format
  static Map<String, String> friendToUIFormat(Map<String, dynamic> friend) {
    return {
      'id': friend['id']?.toString() ?? '',
      'name': friend['friend_name']?.toString() ?? 'Unknown',
      'walletAddress': friend['friend_wallet_address']?.toString() ?? '',
      'avatarColor': friend['avatar_color']?.toString() ?? '#FFBE55',
      'imagePath':
          friend['profile_image_path']?.toString() ??
          'assets/images/ai_gen/profile_images/1.png',
    };
  }
}
