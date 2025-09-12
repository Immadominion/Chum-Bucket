// Enhanced Profile Picture Service
// Provides persistent profile picture management using both local database and Supabase
// Ensures profile pictures persist across app reinstalls and device changes

import 'dart:developer' as dev;
import 'dart:math';
import 'package:chumbucket/core/utils/app_logger.dart';
// Removed local_user_service import after Supabase migration
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistentProfilePictureService {
  // Temporarily disabled until database migration is complete
  // static final SupabaseClient _supabase = Supabase.instance.client;

  // Available profile images from assets
  static const List<String> availableProfileImages = [
    'assets/images/ai_gen/profile_images/1.png',
    'assets/images/ai_gen/profile_images/2.png',
    'assets/images/ai_gen/profile_images/3.png',
    'assets/images/ai_gen/profile_images/4.png',
    'assets/images/ai_gen/profile_images/5.png',
  ];

  /// Get user's profile picture - checks multiple sources for maximum persistence
  /// Priority order: Local DB -> SharedPreferences -> Generate new (Supabase temporarily disabled)
  static Future<String> getUserProfilePicture(String privyId) async {
    try {
      // 1. Try local database first (most reliable while Supabase is disabled)
      final localDbProfilePic = await _getProfilePictureFromLocalDB(privyId);
      if (localDbProfilePic != null && localDbProfilePic.isNotEmpty) {
        AppLogger.info(
          'Retrieved profile picture from local DB: $localDbProfilePic',
          tag: 'ProfilePictureService',
        );

        // Update SharedPreferences to match
        await _saveToSharedPreferences(privyId, localDbProfilePic);

        return localDbProfilePic;
      }

      // 2. Try SharedPreferences (legacy support)
      final sharedPrefsProfilePic = await _getProfilePictureFromSharedPrefs(
        privyId,
      );
      if (sharedPrefsProfilePic != null && sharedPrefsProfilePic.isNotEmpty) {
        AppLogger.info(
          'Retrieved profile picture from SharedPreferences: $sharedPrefsProfilePic',
          tag: 'ProfilePictureService',
        );

        // Update local database
        await _saveToLocalDatabase(privyId, sharedPrefsProfilePic);

        return sharedPrefsProfilePic;
      }

      // 3. Generate new profile picture and save to available sources
      final newProfilePic = _generateRandomProfilePicture();
      AppLogger.info(
        'Generated new profile picture: $newProfilePic',
        tag: 'ProfilePictureService',
      );

      await setUserProfilePicture(privyId, newProfilePic);

      return newProfilePic;
    } catch (e) {
      AppLogger.error(
        'Error getting user profile picture: $e',
        tag: 'ProfilePictureService',
      );

      // Fallback to first available image
      return availableProfileImages.first;
    }
  }

  /// Set user's profile picture - saves to all persistent sources
  static Future<bool> setUserProfilePicture(
    String privyId,
    String profileImagePath,
  ) async {
    if (!availableProfileImages.contains(profileImagePath)) {
      AppLogger.warning(
        'Invalid profile image path: $profileImagePath',
        tag: 'ProfilePictureService',
      );
      return false;
    }

    try {
      // Save to all sources for maximum persistence
      await Future.wait([
        _saveToSupabase(privyId, profileImagePath),
        _saveToLocalDatabase(privyId, profileImagePath),
        _saveToSharedPreferences(privyId, profileImagePath),
      ]);

      AppLogger.info(
        'Successfully saved profile picture to all sources: $profileImagePath',
        tag: 'ProfilePictureService',
      );
      return true;
    } catch (e) {
      AppLogger.error(
        'Error setting user profile picture: $e',
        tag: 'ProfilePictureService',
      );
      return false;
    }
  }

  /// Get a random profile picture from available options
  static String getRandomProfilePicture() {
    return _generateRandomProfilePicture();
  }

  /// Get all available profile pictures
  static List<String> getAllAvailableProfilePictures() {
    return List.unmodifiable(availableProfileImages);
  }

  // Private methods for different storage backends

  static Future<String?> _getProfilePictureFromLocalDB(String privyId) async {
    try {
      AppLogger.debug(
        'Fetching profile picture from Supabase for user: $privyId',
        tag: 'ProfilePictureService',
      );

      final response =
          await Supabase.instance.client
              .from('users')
              .select('profile_image_id')
              .eq('privy_id', privyId)
              .maybeSingle();

      if (response != null && response['profile_image_id'] != null) {
        final imageId = response['profile_image_id'] as int;
        final imagePath = 'assets/images/ai_gen/profile_images/$imageId.png';

        AppLogger.info(
          'Retrieved profile picture from Supabase: $imagePath (ID: $imageId)',
          tag: 'ProfilePictureService',
        );

        return imagePath;
      }

      AppLogger.debug(
        'No profile picture found in Supabase for user: $privyId',
        tag: 'ProfilePictureService',
      );
      return null;
    } catch (e) {
      AppLogger.error(
        'Error fetching profile picture from Supabase: $e',
        tag: 'ProfilePictureService',
      );
      return null;
    }
  }

  static Future<String?> _getProfilePictureFromSharedPrefs(
    String privyId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_pfp_$privyId');
    } catch (e) {
      dev.log('Error fetching profile picture from SharedPreferences: $e');
      return null;
    }
  }

  static Future<void> _saveToSupabase(
    String privyId,
    String profileImagePath,
  ) async {
    try {
      AppLogger.debug(
        'Saving profile picture to Supabase: $profileImagePath for user: $privyId',
        tag: 'ProfilePictureService',
      );

      // Extract the number from the path (e.g., "assets/images/ai_gen/profile_images/3.png" -> 3)
      final regex = RegExp(r'(\d+)\.png$');
      final match = regex.firstMatch(profileImagePath);

      if (match != null) {
        final imageId = int.parse(match.group(1)!);

        await Supabase.instance.client
            .from('users')
            .update({'profile_image_id': imageId})
            .eq('privy_id', privyId);

        AppLogger.info(
          'Successfully saved profile picture ID $imageId to Supabase for user: $privyId',
          tag: 'ProfilePictureService',
        );
      } else {
        AppLogger.warning(
          'Could not extract image ID from path: $profileImagePath',
          tag: 'ProfilePictureService',
        );
      }
    } catch (e) {
      AppLogger.error(
        'Error saving profile picture to Supabase: $e',
        tag: 'ProfilePictureService',
      );
      rethrow;
    }
  }

  static Future<void> _saveToLocalDatabase(
    String privyId,
    String profileImagePath,
  ) async {
    try {
      // Now handled by Supabase users table via _saveToSupabase
      AppLogger.debug(
        'Profile picture saved to Supabase users table instead of local DB',
        tag: 'ProfilePictureService',
      );
    } catch (e) {
      AppLogger.error(
        'Error in local DB placeholder: $e',
        tag: 'ProfilePictureService',
      );
      // Don't throw - we want to continue with other storage methods
    }
  }

  static Future<void> _saveToSharedPreferences(
    String privyId,
    String profileImagePath,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_pfp_$privyId', profileImagePath);
    } catch (e) {
      AppLogger.error(
        'Error saving profile picture to SharedPreferences: $e',
        tag: 'ProfilePictureService',
      );
      // Don't throw - we want to continue with other storage methods
    }
  }

  static String _generateRandomProfilePicture() {
    final random = Random();
    return availableProfileImages[random.nextInt(
      availableProfileImages.length,
    )];
  }

  /// Clean up profile picture data for a user (useful for logout/account deletion)
  static Future<void> clearUserProfilePictureData(String privyId) async {
    try {
      // Clear from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_pfp_$privyId');

      AppLogger.info(
        'Cleared profile picture data for user: $privyId',
        tag: 'ProfilePictureService',
      );
    } catch (e) {
      AppLogger.error(
        'Error clearing profile picture data: $e',
        tag: 'ProfilePictureService',
      );
    }
  }
}
