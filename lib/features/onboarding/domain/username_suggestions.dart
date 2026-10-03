/// Username suggestions from what the person already gave us (onboarding
/// spec §6 A2): their X username, their wallet's .sol/.skr name, or their
/// Google name. Pure: the screen checks each with `auth.usernameStatus` and
/// prefills only one the server says is available. Nothing is ever claimed
/// without the person tapping Claim.
library;

import 'package:chumbucket/features/authentication/session/profile_hints.dart';

export 'package:chumbucket/features/authentication/session/profile_hints.dart';

enum UsernameSuggestionSource {
  x('x'),
  domain('domain'),
  google('google');

  const UsernameSuggestionSource(this.wire);
  final String wire;
}

class UsernameSuggestion {
  const UsernameSuggestion(this.handle, this.source, {this.domain});

  /// Already valid: `[a-z0-9_]{3,20}`.
  final String handle;
  final UsernameSuggestionSource source;

  /// The full name it came from, for "Suggested from dominion.sol".
  final String? domain;

  @override
  bool operator ==(Object other) =>
      other is UsernameSuggestion &&
      other.handle == handle &&
      other.source == source &&
      other.domain == domain;

  @override
  int get hashCode => Object.hash(handle, source, domain);

  @override
  String toString() => 'UsernameSuggestion($handle, ${source.wire})';
}

final RegExp _valid = RegExp(r'^[a-z0-9_]{3,20}$');

/// Lowercase, keep a-z 0-9 _, trim to 20. Null when fewer than 3 survive.
String? sanitizeHandle(String? raw) {
  if (raw == null) return null;
  final cleaned = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^@+'), '')
      .replaceAll(RegExp(r'[\s.\-]+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final cut = cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
  final trimmed = cut.replaceAll(RegExp(r'_+$'), '');
  return _valid.hasMatch(trimmed) ? trimmed : null;
}

/// "dominion.sol" → "dominion"; "ada.skr" → "ada". Null for anything that is
/// not a single-label .sol/.skr name.
String? domainLabel(String? domain) {
  final d = domain?.trim().toLowerCase();
  if (d == null) return null;
  final match = RegExp(r'^([a-z0-9_\-]+)\.(sol|skr)$').firstMatch(d);
  return match == null ? null : sanitizeHandle(match.group(1));
}

/// Candidates in the spec's order: X, then the wallet's name, then Google.
/// Duplicates are dropped. The caller keeps the first one the server says is
/// available.
List<UsernameSuggestion> usernameCandidates({
  ProfileHints? hints,
  String? walletDomain,
}) {
  final out = <UsernameSuggestion>[];
  void add(String? handle, UsernameSuggestionSource source, {String? domain}) {
    if (handle == null || out.any((s) => s.handle == handle)) return;
    out.add(UsernameSuggestion(handle, source, domain: domain));
  }

  if (hints?.isX == true) {
    add(sanitizeHandle(hints!.userName), UsernameSuggestionSource.x);
    add(sanitizeHandle(hints.preferredUsername), UsernameSuggestionSource.x);
  }
  final label = domainLabel(walletDomain);
  if (label != null) {
    add(
      label,
      UsernameSuggestionSource.domain,
      domain: walletDomain!.trim().toLowerCase(),
    );
  }
  if (hints?.isGoogle == true) {
    final parts = (hints!.fullName ?? '').split(RegExp(r'\s+'));
    final given = hints.givenName ?? (parts.isNotEmpty ? parts.first : null);
    final family = hints.familyName ?? (parts.length > 1 ? parts.last : null);
    final initial =
        family == null || family.isEmpty ? '' : family.substring(0, 1);
    add(sanitizeHandle('$given$initial'), UsernameSuggestionSource.google);
  }
  return out;
}

/// The name to prefill for a new account: the provider's full name, else
/// nothing (the field stays empty rather than guessed).
String? nameSuggestion(ProfileHints? hints) {
  final full = hints?.fullName?.trim();
  if (full == null || full.isEmpty) return null;
  return full.length > 60 ? full.substring(0, 60).trim() : full;
}
