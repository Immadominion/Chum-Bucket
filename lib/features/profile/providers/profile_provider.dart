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

  /// Set user's profile picture and save to all storage backends
  Future<bool> setUserPfp(String privyId, String pfpPath) async {
    return await PersistentProfilePictureService.setUserProfilePicture(
      privyId,
      pfpPath,
    );
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

  Future<bool> updateUserProfile(
    String privyId,
    Map<String, dynamic> updates,
  ) async {
    if (!await hasInternetConnection()) {
      setError(
        "No internet connection. Please check your network and try again.",
      );
      return false;
    }

    try {
      setLoading();

      // Extract fields from updates
      final fullName = updates['full_name'] ?? '';
      final bio = updates['bio'] ?? '';

      // Call the stored procedure
      await _supabase.rpc(
        'update_user_profile',
        params: {'p_privy_id': privyId, 'p_full_name': fullName, 'p_bio': bio},
      );

      AppLogger.debug(
        'User profile updated successfully for privy_id: $privyId',
        tag: 'ProfileProvider',
      );
      setSuccess();
      return true;
    } catch (e) {
      AppLogger.debug(
        'Error updating user profile: $e',
        tag: 'ProfileProvider',
      );
      if (e is PostgrestException) {
        AppLogger.debug(
          'Postgrest details: code=${e.code}, message=${e.message}, details=${e.details}',
        );
      }
      setError('Failed to update user profile: $e');
      return false;
    }
  }

  Future<void> saveUserProfileLocally(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', profile.toString());
  }

  Future<Map<String, dynamic>?> getUserProfileFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final profileString = prefs.getString('user_profile');

    if (profileString != null) {
      final profileParts = profileString
          .substring(1, profileString.length - 1) // Remove braces
          .split(', ');

      final profileMap = {
        for (var part in profileParts) part.split(': ')[0]: part.split(': ')[1],
      };

      return profileMap;
    }

    return null;
  }

  // Optional: Update profile with PFP in database
  Future<bool> updateUserProfileWithPfp(
    String privyId,
    Map<String, dynamic> updates,
    String pfpPath,
  ) async {
    if (!await hasInternetConnection()) {
      setError(
        "No internet connection. Please check your network and try again.",
      );
      return false;
    }

    try {
      setLoading();

      // Extract fields from updates
      final fullName = updates['full_name'] ?? '';
      final bio = updates['bio'] ?? '';

      // Call the stored procedure with PFP
      await _supabase.rpc(
        'update_user_profile_with_pfp',
        params: {
          'p_privy_id': privyId,
          'p_full_name': fullName,
          'p_bio': bio,
          'p_pfp_path': pfpPath,
        },
      );

      AppLogger.debug(
        'User profile updated successfully with PFP for privy_id: $privyId',
      );
      setSuccess();
      return true;
    } catch (e) {
      AppLogger.debug(
        'Error updating user profile with PFP: $e',
        tag: 'ProfileProvider',
      );
      if (e is PostgrestException) {
        AppLogger.debug(
          'Postgrest details: code=${e.code}, message=${e.message}, details=${e.details}',
        );
      }
      setError('Failed to update user profile with PFP: $e');
      return false;
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
    await super.clearUserData();
    // Note: We intentionally don't clear PFP data here as we want it to persist
    // across sessions for better user experience. If you need to clear it,
    // call PersistentProfilePictureService.clearUserProfilePictureData() explicitly
  }
}
