import 'package:supabase_flutter/supabase_flutter.dart';

/// This only prevents a device test from creating a second person. A wallet
/// lookup is not proof that the wallet may claim a canonical user account.
enum ExistingWalletProfile { found, missing, unavailable }

class ExistingWalletProfileGuard {
  const ExistingWalletProfileGuard(this._supabase);

  final SupabaseClient _supabase;

  /// Read-only and fail-closed: never call legacy sync or upsert from here.
  Future<ExistingWalletProfile> check(String walletAddress) async {
    try {
      final row =
          await _supabase
              .from('users')
              .select('id')
              .eq('wallet_address', walletAddress)
              .maybeSingle();
      return row == null
          ? ExistingWalletProfile.missing
          : ExistingWalletProfile.found;
    } catch (_) {
      return ExistingWalletProfile.unavailable;
    }
  }
}
