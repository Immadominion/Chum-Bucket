import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Compile-time configuration for the mobile client.
///
/// The app used to ship its whole `.env` as a Flutter asset, which meant every
/// value in that file — including a provider API key and an access token — was
/// readable byte-for-byte inside every release APK. Nothing secret may reach
/// the client any more, so configuration now arrives through `--dart-define`
/// and is limited to the allowlist below.
///
/// Boundary rule: the client may hold the Supabase URL and publishable/anon
/// key, the BFF base URL, the network name, and a *credential-free* RPC URL.
/// Provider API keys, the Supabase service-role key, OAuth client secrets, the
/// Firebase Admin credential and server signing keys live on the BFF only.
///
/// Local development:
///   flutter run --dart-define-from-file=env.local.json
/// (`env.local.json` is gitignored; `env.example.json` shows the shape.)
class AppConfig {
  AppConfig._();

  /// Internal preview only until account continuity and the full return loop
  /// pass device testing. Never replace the installed app's entry flow.
  static const bool callReceiptExperienceEnabled = bool.fromEnvironment(
    'CALL_RECEIPT_EXPERIENCE',
    defaultValue: false,
  );

  /// The Chumbucket wallet: one wallet that follows the account across
  /// iPhone, Android and the web (a Privy embedded Solana wallet), the default
  /// for trades. Off unless the build passes
  /// `--dart-define=CHUMBUCKET_WALLET_ENABLED=true`, matching the BFF's flag of
  /// the same name, and only used when both Privy ids below are set too.
  static const bool chumbucketWalletEnabled = bool.fromEnvironment(
    'CHUMBUCKET_WALLET_ENABLED',
    defaultValue: false,
  );

  /// Calls with an amount, the balance pill, deposits, cash out and winnings
  /// (money v1). Off unless the build passes
  /// `--dart-define=MONEY_CALLS_ENABLED=true`; even then everything stays
  /// hidden until the BFF's `money.status` says it is on
  /// (`MONEY_CALLS_ENABLED` there too).
  static const bool moneyCallsEnabled = bool.fromEnvironment(
    'MONEY_CALLS_ENABLED',
    defaultValue: false,
  );

  /// Every configuration key the client is allowed to carry.
  ///
  /// Adding a key here is a security decision: it makes the value public,
  /// because anyone can unzip the APK and read it. `app_config_test.dart`
  /// fails the build if a secret-shaped name is added.
  static const List<String> publicKeys = <String>[
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'SUPABASE_PUBLISHABLE_KEY',
    'ARENA_BACKEND_URL',
    'SOLANA_NETWORK',
    'SOLANA_RPC_URL',
    'SOLANA_DEVNET_RPC_URL',
    'SOLANA_MAINNET_RPC_URL',
    'PLATFORM_WALLET_ADDRESS',
    'PLATFORM_FEE_PERCENTAGE',
    'MIN_FEE_SOL',
    'MAX_FEE_SOL',
    'TAWK_TO_URL',
    // Which CallsRepository the build runs on ('mock' or 'bff'), and where
    // the calls BFF lives. Both are public: a base URL is not a credential,
    // and AppConfig drops any URL carrying an inline one.
    'CALLS_BACKEND',
    'CALLS_BFF_URL',
    'CALLS_LINK_HOST',
    'CALL_RECEIPT_EXPERIENCE',
    // Legacy Privy export bridge only. The app *secret* is server-side.
    'PRIVY_APP_ID',
    'PRIVY_API_URL',
    // The Chumbucket wallet's Privy app and this app's client in it. Both are
    // public identifiers (Privy ships them in every client); there is no
    // Privy secret anywhere in the apps or the BFF for this wallet.
    'CHUMBUCKET_PRIVY_APP_ID',
    'CHUMBUCKET_PRIVY_CLIENT_ID',
  ];

  /// Name fragments that must never appear in [publicKeys].
  static const List<String> forbiddenKeyFragments = <String>[
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

  static const Map<String, String> _defines = <String, String>{
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
    'SUPABASE_PUBLISHABLE_KEY': String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
    'ARENA_BACKEND_URL': String.fromEnvironment('ARENA_BACKEND_URL'),
    'SOLANA_NETWORK': String.fromEnvironment('SOLANA_NETWORK'),
    'SOLANA_RPC_URL': String.fromEnvironment('SOLANA_RPC_URL'),
    'SOLANA_DEVNET_RPC_URL': String.fromEnvironment('SOLANA_DEVNET_RPC_URL'),
    'SOLANA_MAINNET_RPC_URL': String.fromEnvironment('SOLANA_MAINNET_RPC_URL'),
    'PLATFORM_WALLET_ADDRESS': String.fromEnvironment(
      'PLATFORM_WALLET_ADDRESS',
    ),
    'PLATFORM_FEE_PERCENTAGE': String.fromEnvironment(
      'PLATFORM_FEE_PERCENTAGE',
    ),
    'MIN_FEE_SOL': String.fromEnvironment('MIN_FEE_SOL'),
    'MAX_FEE_SOL': String.fromEnvironment('MAX_FEE_SOL'),
    'TAWK_TO_URL': String.fromEnvironment('TAWK_TO_URL'),
    'CALLS_BACKEND': String.fromEnvironment('CALLS_BACKEND'),
    'CALLS_BFF_URL': String.fromEnvironment('CALLS_BFF_URL'),
    'CALLS_LINK_HOST': String.fromEnvironment('CALLS_LINK_HOST'),
    'CALL_RECEIPT_EXPERIENCE': String.fromEnvironment(
      'CALL_RECEIPT_EXPERIENCE',
    ),
    'PRIVY_APP_ID': String.fromEnvironment('PRIVY_APP_ID'),
    'PRIVY_API_URL': String.fromEnvironment('PRIVY_API_URL'),
    'CHUMBUCKET_PRIVY_APP_ID': String.fromEnvironment(
      'CHUMBUCKET_PRIVY_APP_ID',
    ),
    'CHUMBUCKET_PRIVY_CLIENT_ID': String.fromEnvironment(
      'CHUMBUCKET_PRIVY_CLIENT_ID',
    ),
  };

  /// A URL carrying an inline credential, e.g. a Helius RPC endpoint of the
  /// form `https://…helius-rpc.com/?api-key=<key>`.
  ///
  /// Such a URL is a secret wearing a URL costume. It is dropped rather than
  /// baked into the binary; the caller falls back to a public endpoint.
  static bool urlCarriesCredential(String value) {
    final lower = value.toLowerCase();
    return lower.contains('api-key=') ||
        lower.contains('api_key=') ||
        lower.contains('apikey=') ||
        lower.contains('access_token=') ||
        lower.contains('token=') ||
        RegExp(r'https?://[^/@\s]+:[^/@\s]+@').hasMatch(lower);
  }

  /// The values that will actually be exposed to the app, with any
  /// credential-bearing URL removed. Pure, so it can be unit-tested.
  static Map<String, String> sanitize(Map<String, String> raw) {
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (value.isEmpty) return;
      if (!publicKeys.contains(key)) return;
      if (urlCarriesCredential(value)) {
        assert(() {
          debugPrint(
            'AppConfig: dropped $key — it carries an inline credential and '
            'must not ship in the client. Route it through the BFF instead.',
          );
          return true;
        }());
        return;
      }
      out[key] = value;
    });
    return out;
  }

  static Map<String, String> get values => sanitize(_defines);

  static bool _initialized = false;

  /// Publishes the sanitized public configuration.
  ///
  /// Existing call sites read `dotenv.env[...]`, so the values are written
  /// there rather than rewriting every consumer. No `.env` asset is loaded and
  /// none is bundled — see `pubspec.yaml`.
  static void initialize() {
    if (_initialized) return;
    // Initialize the legacy reader without loading a file. Its env getter
    // throws until this happens, including on every fresh device process.
    dotenv.loadFromString(isOptional: true);
    dotenv.env
      ..clear()
      ..addAll(values);
    _initialized = true;
    assert(() {
      final missing = <String>[
        if ((dotenv.env['SUPABASE_URL'] ?? '').isEmpty) 'SUPABASE_URL',
        if ((dotenv.env['SUPABASE_ANON_KEY'] ?? '').isEmpty)
          'SUPABASE_ANON_KEY',
      ];
      if (missing.isNotEmpty) {
        debugPrint(
          'AppConfig: missing ${missing.join(', ')}. Pass '
          '--dart-define-from-file=env.local.json (see env.example.json).',
        );
      }
      return true;
    }());
  }

  @visibleForTesting
  static void resetForTest() => _initialized = false;
}
