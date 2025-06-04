import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/providers/base_change_notifier.dart';

class ProfileProvider extends BaseChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> fetchUserProfile(String privyId) async {
    try {
      setLoading();
      final response =
          await _supabase
              .rpc('fetch_user_profile', params: {'p_privy_id': privyId})
              .maybeSingle();

      log('Raw fetch_user_profile response: $response');

      if (response != null) {
        // Handle direct JSON object (no fetch_user_profile key)
        final profile = response as Map<String, dynamic>;
        setSuccess();
        return profile;
      }

      setSuccess();
      return null;
    } catch (e) {
      log('Error fetching user profile: $e');
      if (e is PostgrestException) {
        log(
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

      log('User profile updated successfully for privy_id: $privyId');
      setSuccess();
      return true;
    } catch (e) {
      log('Error updating user profile: $e');
      if (e is PostgrestException) {
        log(
          'Postgrest details: code=${e.code}, message=${e.message}, details=${e.details}',
        );
      }
      setError('Failed to update user profile: $e');
      return false;
    }
  }
}
