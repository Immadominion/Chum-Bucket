/// The release configuration gate.
///
/// Pure Dart (no Flutter imports) so `scripts/build_release.sh` can run it with
/// `dart run tool/check_release_config.dart` before Gradle is ever started, and
/// `test/release_config_test.dart` can pin every rule.
///
/// A release that fails any rule is not built. The rules exist because each
/// one has shipped wrong before (prod-readiness audit B4, B10, m2):
///   * CALL_RECEIPT_EXPERIENCE off ships the old Arena product.
///   * SOLANA_NETWORK not mainnet shows a devnet balance beside mainnet trades.
///   * CALLS_BACKEND not bff can put the seeded demo catalog in front of people.
///   * a link host other than chumbucket.fun builds links nobody can open.
///   * a legal site other than chumbucket.fun sends Terms, Privacy and the
///     account-deletion page (trust) somewhere that does not serve them.
library;

import 'dart:convert';
import 'dart:io';

/// The live site; must match `kCallsLinkHostDefault` in the app.
const String kReleaseLinkHost = 'https://chumbucket.fun';

/// Keys that must come from the builder's machine, never from git.
const List<String> kLocalOnlyKeys = ['SUPABASE_URL', 'SUPABASE_ANON_KEY'];

/// Mirrors `AppConfig.forbiddenKeyFragments`; a test keeps them equal.
const List<String> kForbiddenKeyFragments = [
  'SECRET',
  'PRIVATE',
  'SERVICE_ROLE',
  'ACCESS_TOKEN',
  'API_KEY',
  'APIKEY',
  'PASSWORD',
  'CLIENT_SECRET',
  'SIGNING',
  'MNEMONIC',
  'SEED_PHRASE',
];

/// Mirrors `AppConfig.urlCarriesCredential`.
bool urlCarriesCredential(String value) {
  final lower = value.toLowerCase();
  return lower.contains('api-key=') ||
      lower.contains('api_key=') ||
      lower.contains('apikey=') ||
      lower.contains('access_token=') ||
      lower.contains('token=') ||
      RegExp(r'https?://[^/@\s]+:[^/@\s]+@').hasMatch(lower);
}

bool _isPublicHttps(String? value) {
  if (value == null) return false;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
  const local = {'localhost', '127.0.0.1', '10.0.2.2', '0.0.0.0'};
  return !local.contains(uri.host);
}

/// Every reason [config] must not become a release. Empty means it may.
///
/// [requireLocalKeys] is false when checking the committed file alone, which
/// deliberately does not carry the Supabase project values.
List<String> releaseConfigProblems(
  Map<String, String> config, {
  bool requireLocalKeys = true,
}) {
  final problems = <String>[];
  String? v(String key) => config[key]?.trim();

  if (v('CALL_RECEIPT_EXPERIENCE') != 'true') {
    problems.add(
      'CALL_RECEIPT_EXPERIENCE must be "true" (got ${_show(v('CALL_RECEIPT_EXPERIENCE'))}). '
      'Off ships the old Arena product.',
    );
  }

  final network = v('SOLANA_NETWORK')?.toLowerCase();
  if (network != 'mainnet-beta' && network != 'mainnet') {
    problems.add(
      'SOLANA_NETWORK must be "mainnet-beta" (got ${_show(v('SOLANA_NETWORK'))}). '
      'Panta positions settle in mainnet USDC.',
    );
  }

  if (v('CALLS_BACKEND')?.toLowerCase() != 'bff') {
    problems.add(
      'CALLS_BACKEND must be "bff" (got ${_show(v('CALLS_BACKEND'))}). '
      'Any other value can put the demo catalog in front of people.',
    );
  }

  if (!_isPublicHttps(v('CALLS_BFF_URL'))) {
    problems.add(
      'CALLS_BFF_URL must be a public https URL (got ${_show(v('CALLS_BFF_URL'))}).',
    );
  }

  final linkHost = v('CALLS_LINK_HOST')?.replaceAll(RegExp(r'/+$'), '');
  if (linkHost != kReleaseLinkHost) {
    problems.add(
      'CALLS_LINK_HOST must be "$kReleaseLinkHost" (got ${_show(v('CALLS_LINK_HOST'))}). '
      'It is the only host the app verifies and the site serves.',
    );
  }

  // Optional (lib/features/trust/data/legal_links.dart defaults to the live
  // site): when a build names them, they must still be the right places.
  final legal = v('LEGAL_SITE_URL')?.replaceAll(RegExp(r'/+$'), '');
  if (legal != null && legal.isNotEmpty && legal != kReleaseLinkHost) {
    problems.add(
      'LEGAL_SITE_URL must be "$kReleaseLinkHost" when set (got ${_show(v('LEGAL_SITE_URL'))}). '
      'It serves /terms, /privacy and /delete-account.',
    );
  }
  final store = v('STORE_LISTING_URL');
  if (store != null && store.isNotEmpty && !_isPublicHttps(store) &&
      !store.startsWith('solanadappstore://')) {
    problems.add(
      'STORE_LISTING_URL must be a public https or solanadappstore:// link when set (got ${_show(store)}).',
    );
  }

  for (final key in ['ARENA_BACKEND_URL', 'SOLANA_RPC_URL', 'SOLANA_MAINNET_RPC_URL']) {
    final value = v(key);
    if (value != null && value.isNotEmpty && !_isPublicHttps(value)) {
      problems.add('$key must be a public https URL when set (got ${_show(value)}).');
    }
  }

  if (requireLocalKeys) {
    final supabase = v('SUPABASE_URL');
    final uri = supabase == null ? null : Uri.tryParse(supabase);
    if (uri == null || uri.scheme != 'https' || !uri.host.endsWith('.supabase.co')) {
      problems.add(
        'SUPABASE_URL must be the https://<project>.supabase.co URL '
        '(set it in your environment or env.local.json).',
      );
    }
    if ((v('SUPABASE_ANON_KEY') ?? '').isEmpty) {
      problems.add(
        'SUPABASE_ANON_KEY is missing (set it in your environment or env.local.json).',
      );
    }
  }

  config.forEach((key, value) {
    if (key.startsWith('_')) return;
    final upper = key.toUpperCase();
    for (final fragment in kForbiddenKeyFragments) {
      if (upper.contains(fragment)) {
        problems.add('$key looks like a secret ("$fragment") and must not ship in the app.');
      }
    }
    if (urlCarriesCredential(value)) {
      problems.add('$key carries an inline credential and must not ship in the app.');
    }
  });

  return problems;
}

String _show(String? value) => value == null ? 'nothing' : '"$value"';

/// Reads a flat JSON object of string values (`--dart-define-from-file`).
Map<String, String> readDefinesFile(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map) {
    throw FormatException('$path is not a JSON object');
  }
  return {
    for (final e in decoded.entries) '${e.key}': '${e.value}',
  };
}

/// The committed release file plus the two Supabase values from the builder's
/// machine: the process environment first, then `env.local.json`. Nothing else
/// is taken from the local file, so a devnet or mock setting there can never
/// leak into a release.
Map<String, String> mergeReleaseConfig({
  required Map<String, String> committed,
  Map<String, String> environment = const {},
  Map<String, String> localFile = const {},
}) {
  final merged = Map<String, String>.of(committed);
  for (final key in kLocalOnlyKeys) {
    final fromEnv = environment[key]?.trim();
    final fromFile = localFile[key]?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      merged[key] = fromEnv;
    } else if (fromFile != null && fromFile.isNotEmpty) {
      merged[key] = fromFile;
    }
  }
  return merged;
}
