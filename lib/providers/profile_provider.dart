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
              .from('users')
              .select()
              .eq('privy_id', privyId)
              .single();

      setSuccess();
      return response;
    } catch (e) {
      log('Error fetching user profile: ${e.toString()}');
      setError('Failed to fetch user profile');
      return null;
    }
  }

  Future<bool> updateUserProfile(
    String privyId,
    Map<String, dynamic> updates,
  ) async {
    try {
      setLoading();

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('users').update(updates).eq('privy_id', privyId);

      setSuccess();
      return true;
    } catch (e) {
      log('Error updating user profile: ${e.toString()}');
      setError('Failed to update user profile');
      return false;
    }
  }
}
