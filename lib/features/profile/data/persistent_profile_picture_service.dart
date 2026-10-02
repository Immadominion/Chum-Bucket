// Profile picture lookup for the legacy wallet surfaces (the header avatar,
// the wallet profile screen).
//
// READS ONLY, plus a per-device cache. The chosen avatar is written to the
// person's own account through the BFF (`AccountApi.updateProfile(avatarId:)`),
// keyed by the signed-in session — never by a wallet string through the anon
// client, which let anyone re-picture anyone (prod readiness B1/M9) and is
// revoked by 20261002171000_lockdown_profiles_push_privacy.sql.

import 'dart:developer' as dev;

import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/features/profile/data/avatar_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersistentProfilePictureService {
  PersistentProfilePictureService._();

  /// The bundled avatars, in id order (1..5).
  static const List<String> availableProfileImages = kAvatarAssets;

  /// The person's picture: the id stored on their profile row, else this
  /// device's cache, else the default picture.
  ///
  /// Never invents and saves a random one: a picture nobody chose must not be
  /// written to anybody's account, and must not change between launches.
  static Future<String> getUserProfilePicture(String key) async {
    try {
      final stored = await _getProfilePictureFromProfileRow(key);
      if (stored != null) {
        await _saveToSharedPreferences(key, stored);
        return stored;
      }
      final cached = await _getProfilePictureFromSharedPrefs(key);
      if (cached != null && kAvatarAssets.contains(cached)) return cached;
    } catch (e) {
      AppLogger.error(
        'Error getting user profile picture: $e',
        tag: 'ProfilePictureService',
      );
    }
    return avatarAssetFor(kDefaultAvatarId)!;
  }

  /// Cache a picture the person has ALREADY saved to their account (through
  /// the BFF) on this device. Returns false for a path outside the set.
  static Future<bool> setUserProfilePicture(
    String key,
    String profileImagePath,
  ) async {
    if (!kAvatarAssets.contains(profileImagePath)) {
      AppLogger.warning(
        'Invalid profile image path: $profileImagePath',
        tag: 'ProfilePictureService',
      );
      return false;
    }
    await _saveToSharedPreferences(key, profileImagePath);
    return true;
  }

  /// The default picture (kept for callers that asked for "a random one":
  /// a stable default reads better than a different face every launch).
  static String getRandomProfilePicture() => avatarAssetFor(kDefaultAvatarId)!;

  static List<String> getAllAvailableProfilePictures() =>
      List.unmodifiable(availableProfileImages);

  static final RegExp _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');

  /// Read-only lookup of the avatar id on the profile row for a wallet key.
  /// A key that is not a wallet (a Google/X account has none) is simply "no
  /// row here" — those accounts read their avatar from `account.me`.
  static Future<String?> _getProfilePictureFromProfileRow(String key) async {
    if (!_base58.hasMatch(key)) return null;
    try {
      final response =
          await Supabase.instance.client
              .from('users')
              .select('profile_image_id')
              .or('wallet_address.eq.$key,privy_id.eq.$key')
              .limit(1)
              .maybeSingle();
      return avatarAssetFor(response?['profile_image_id']);
    } catch (e) {
      AppLogger.error(
        'Error reading profile picture: $e',
        tag: 'ProfilePictureService',
      );
      return null;
    }
  }

  static Future<String?> _getProfilePictureFromSharedPrefs(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_pfp_$key');
    } catch (e) {
      dev.log('Error reading cached profile picture: $e');
      return null;
    }
  }

  static Future<void> _saveToSharedPreferences(String key, String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_pfp_$key', path);
    } catch (e) {
      AppLogger.error(
        'Error caching profile picture: $e',
        tag: 'ProfilePictureService',
      );
    }
  }

  /// Forget this device's cached picture for a key (sign-out, deletion).
  static Future<void> clearUserProfilePictureData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_pfp_$key');
    } catch (e) {
      AppLogger.error(
        'Error clearing profile picture data: $e',
        tag: 'ProfilePictureService',
      );
    }
  }
}
