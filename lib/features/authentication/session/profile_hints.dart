/// What the sign-in provider told Supabase about the person, as
/// `user_metadata` / `app_metadata` hold it: an X username, a Google name.
/// Display-only hints for prefilling a username and name — never identity,
/// never sent anywhere, never logged.
library;

/// The provider's profile fields, as Supabase stores them in
/// `user_metadata`. Every field may be missing.
class ProfileHints {
  const ProfileHints({
    this.provider,
    this.userName,
    this.preferredUsername,
    this.fullName,
    this.givenName,
    this.familyName,
  });

  /// `google`, `twitter`/`x`, `web3`, … (`app_metadata.provider`).
  final String? provider;

  /// X: `user_name`.
  final String? userName;

  /// X: `preferred_username`.
  final String? preferredUsername;

  /// `full_name` or `name`.
  final String? fullName;
  final String? givenName;
  final String? familyName;

  bool get isX => provider == 'twitter' || provider == 'x';
  bool get isGoogle => provider == 'google';

  static ProfileHints fromMetadata({
    Map<String, dynamic>? userMetadata,
    Map<String, dynamic>? appMetadata,
  }) {
    String? s(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final m = userMetadata ?? const <String, dynamic>{};
    return ProfileHints(
      provider: s(appMetadata?['provider']),
      userName: s(m['user_name']),
      preferredUsername: s(m['preferred_username']),
      fullName: s(m['full_name']) ?? s(m['name']),
      givenName: s(m['given_name']),
      familyName: s(m['family_name']),
    );
  }
}

