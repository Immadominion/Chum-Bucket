import 'dart:convert';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart';
import 'package:chumbucket/features/profile/data/persistent_profile_picture_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileProvider extends BaseChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Profile Picture Methods - Now using persistent service for better reliability

  /// Get user's profile picture with full persistence across app reinstalls
  Future<String> getUserPfp(String privyId) async {
    return await PersistentProfilePictureService.getUserProfilePicture(privyId);
  }

  /// Remember a picture the person just saved to their account (through
  /// `AccountApi.updateProfile`) on this device, and tell listeners. This does
  /// not write the account — the BFF already did.
  Future<bool> setUserPfp(String key, String pfpPath) async {
    final success = await PersistentProfilePictureService.setUserProfilePicture(
      key,
      pfpPath,
    );

    if (success) {
      notifyListeners();
      AppLogger.info(
        'Profile picture remembered and listeners notified',
        tag: 'ProfileProvider',
      );
    }

    return success;
  }

  /// Get a random profile picture from available options
  String getRandomPfp() {
    return PersistentProfilePictureService.getRandomProfilePicture();
  }

  /// Get all available profile pictures for user selection
  List<String> get availablePfps {
    return PersistentProfilePictureService.getAllAvailableProfilePictures();
  }

  /// Legacy method for backward compatibility - deprecated, use setUserPfp instead
  @Deprecated('Use setUserPfp instead for better persistence')
  Future<void> saveUserPfp(String privyId, String pfpPath) async {
    await setUserPfp(privyId, pfpPath);
  }

  Future<Map<String, dynamic>?> fetchUserProfile(String privyId) async {
    if (!await hasInternetConnection()) {
      setError(
        "No internet connection. Please check your network and try again.",
      );
      return null;
    }

    try {
      setLoading();
      final response =
          await _supabase
              .rpc('fetch_user_profile', params: {'p_privy_id': privyId})
              .maybeSingle();

      AppLogger.debug(
        'Raw fetch_user_profile response: $response',
        tag: 'ProfileProvider',
      );

      if (response != null) {
        // Handle direct JSON object (no fetch_user_profile key)
        final profile = response;
        setSuccess();
        return profile;
      }

      setSuccess();
      return null;
    } catch (e) {
      AppLogger.debug(
        'Error fetching user profile: $e',
        tag: 'ProfileProvider',
      );
      if (e is PostgrestException) {
        AppLogger.debug(
          'Postgrest details: code=${e.code}, message=${e.message}, details=${e.details}',
        );
      }
      setError('Failed to fetch user profile: $e');
      return null;
    }
  }

  // Profile WRITES no longer live here. Name, bio and avatar are edited through
  // the BFF (`AccountApi.updateProfile`), keyed by the signed-in session: the
  // old `update_user_profile*` RPCs took any wallet string, so anyone could
  // rewrite anyone's profile (prod readiness B1), and they are revoked by
  // supabase/migrations/20261002171000_lockdown_profiles_push_privacy.sql.

  Future<void> saveUserProfileLocally(Map<String, dynamic> profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = jsonEncode(profile);
      await prefs.setString('user_profile', profileJson);
      AppLogger.debug(
        'Profile saved locally: ${profile['full_name']} (${profile['email']})',
        tag: 'ProfileProvider',
      );
    } catch (e) {
      AppLogger.error('Failed to save profile locally: $e');
    }
  }

  Future<Map<String, dynamic>?> getUserProfileFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString('user_profile');

      if (profileJson != null && profileJson.isNotEmpty) {
        final profile = jsonDecode(profileJson) as Map<String, dynamic>;
        AppLogger.debug(
          'Profile loaded locally: ${profile['full_name']} (${profile['email']})',
          tag: 'ProfileProvider',
        );
        return profile;
      }

      AppLogger.debug('No local profile found', tag: 'ProfileProvider');
      return null;
    } catch (e) {
      AppLogger.error('Failed to load profile locally: $e');
      return null;
    }
  }

  // Enhanced method to fetch user profile and ensure PFP is assigned
  Future<Map<String, dynamic>?> fetchUserProfileWithPfp(String privyId) async {
    final profile = await fetchUserProfile(privyId);

    if (profile != null) {
      // Get the user's PFP (either existing or newly assigned)
      final pfpPath = await getUserPfp(privyId);

      // Add the PFP to the profile data
      profile['pfp_path'] = pfpPath;

      // Save the complete profile locally
      await saveUserProfileLocally(profile);

      return profile;
    }

    return null;
  }

  @override
  Future<void> clearUserData() async {
    // Clear the cached user_profile from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_profile');

    // Note: We intentionally don't clear PFP data here as we want it to persist
    // across sessions for better user experience. If you need to clear it,
    // call PersistentProfilePictureService.clearUserProfilePictureData() explicitly

    await super.clearUserData();
  }
}
