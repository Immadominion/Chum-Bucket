import 'dart:developer' as dev;
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/providers/base_change_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileProvider extends BaseChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final List<String> availablePfps = [
    'assets/images/ai_gen/profile_images/1.png',
    'assets/images/ai_gen/profile_images/2.png',
    'assets/images/ai_gen/profile_images/3.png',
    'assets/images/ai_gen/profile_images/4.png',
    'assets/images/ai_gen/profile_images/5.png',
  ];

  // Selects a random PFP from the available options
  String getRandomPfp() {
    final random = Random();
    return availablePfps[random.nextInt(availablePfps.length)];
  }

  // Saves the selected PFP for a specific user
  Future<void> saveUserPfp(String privyId, String pfpPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_pfp_$privyId', pfpPath);
  }

  // Retrieves the saved PFP for a specific user, or assigns a random one if none exists
  Future<String> getUserPfp(String privyId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPfp = prefs.getString('user_pfp_$privyId');

    if (savedPfp != null) {
      return savedPfp;
    } else {
      // No PFP assigned yet, select a random one and save it
      final randomPfp = getRandomPfp();
      await saveUserPfp(privyId, randomPfp);
      return randomPfp;
    }
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

      dev.log('Raw fetch_user_profile response: $response');

      if (response != null) {
        // Handle direct JSON object (no fetch_user_profile key)
        final profile = response;
        setSuccess();
        return profile;
      }

      setSuccess();
      return null;
    } catch (e) {
      dev.log('Error fetching user profile: $e');
      if (e is PostgrestException) {
        dev.log(
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

      dev.log('User profile updated successfully for privy_id: $privyId');
      setSuccess();
      return true;
    } catch (e) {
      dev.log('Error updating user profile: $e');
      if (e is PostgrestException) {
        dev.log(
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

      dev.log(
        'User profile updated successfully with PFP for privy_id: $privyId',
      );
      setSuccess();
      return true;
    } catch (e) {
      dev.log('Error updating user profile with PFP: $e');
      if (e is PostgrestException) {
        dev.log(
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
    // We don't clear PFP data here as we want it to persist across sessions
  }
}
