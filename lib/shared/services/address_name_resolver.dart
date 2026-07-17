import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// TLD Parser (AllDomains/ANS protocol) for .skr, .abc, .poor, .bonk and
// other multi-TLD domains. Does NOT cover .sol (that's the separate,
// Bonfida-only SNS protocol, dropped from this app).
import 'package:tld_parser/tld_parser.dart';
import 'package:solana/solana.dart' as solana;

/// Resolves Solana wallet addresses to domain names when available,
/// and resolves domains to wallet addresses when provided by user.
///
/// Supported domain extensions (all via AllDomains/ANS, tld_parser):
/// - .skr - Seeker wallet domains (Solana Mobile)
/// - .abc, .poor, .bonk, etc. - other AllDomains TLDs
class AddressNameResolver {
  static final Map<String, String> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static TldParser? _tldParser;
  static const Duration _cacheExpiry = Duration(hours: 1); // Cache for 1 hour

  // Track pending lookups to prevent duplicate concurrent requests
  static final Map<String, Future<String>> _pendingLookups = {};

  // RPC URL for mainnet - prefer Helius if available, otherwise public RPC
  static String get _mainnetRpcUrl {
    // Try to get Helius API key from env
    final heliusKey = dotenv.env['HELIUS_API_KEY'];
    if (heliusKey != null && heliusKey.isNotEmpty) {
      return 'https://mainnet.helius-rpc.com/?api-key=$heliusKey';
    }

    // Try to extract API key from existing SOLANA_RPC_URL (might be devnet Helius)
    final solanaRpcUrl = dotenv.env['SOLANA_RPC_URL'];
    if (solanaRpcUrl != null && solanaRpcUrl.contains('helius-rpc.com')) {
      // Extract API key and use it for mainnet
      final apiKeyMatch = RegExp(
        r'api-key=([a-f0-9-]+)',
      ).firstMatch(solanaRpcUrl);
      if (apiKeyMatch != null) {
        final apiKey = apiKeyMatch.group(1);
        if (kDebugMode) {
          log(
            'AddressNameResolver: Using Helius API key for mainnet SNS lookups',
          );
        }
        return 'https://mainnet.helius-rpc.com/?api-key=$apiKey';
      }
    }

    // Fallback to public mainnet (rate limited)
    if (kDebugMode) {
      log(
        'AddressNameResolver: Using public mainnet RPC (may be rate limited)',
      );
    }
    return 'https://api.mainnet-beta.solana.com';
  }

  // Base58 charset check (quick heuristic)
  static final RegExp _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');

  // AllDomains/ANS TLDs (tld_parser) — the only domain protocol this app
  // resolves. SNS (.sol) was dropped: it's a separate, Bonfida-only
  // protocol tld_parser explicitly does not cover.
  static const List<String> _allDomainsTldExtensions = [
    '.skr', // Seeker/Solana Mobile
    '.bonk',
    '.backpack',
    '.blink',
    '.monke',
    '.ninja',
    '.solana',
    // Add more as needed
  ];

  // Public helpers
  static bool isBase58Address(String value) =>
      value.length >= 32 && value.length <= 50 && _base58.hasMatch(value);

  /// Check if value is a .skr domain (Seeker wallet)
  static bool isSkrDomain(String value) => value.toLowerCase().endsWith('.skr');

  /// Check if value is an AllDomains TLD (.skr, .abc, .poor, etc.)
  static bool isAllDomainsTld(String value) {
    final lower = value.toLowerCase();
    return _allDomainsTldExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Check if value is any domain this resolver supports (.skr, .abc, etc.)
  static bool isSupportedDomain(String value) => isAllDomainsTld(value);

  /// Get or create the TLD Parser for AllDomains TLDs
  static TldParser _getTldParser() {
    if (_tldParser != null) return _tldParser!;
    final rpcClient = solana.RpcClient(_mainnetRpcUrl);
    _tldParser = TldParser(rpcClient);
    return _tldParser!;
  }

  /// Resolve a display name for a given input which may be a wallet or name.
  static Future<String> resolveDisplayName(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Unknown';
    if (_looksLikeName(trimmed)) return trimmed; // already a name/domain/email

    final cacheKey = 'name:$trimmed';

    // Check cache with expiry
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < _cacheExpiry) {
        return _cache[cacheKey]!;
      } else {
        // Cache expired, remove it
        _cache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
      }
    }

    // Only try reverse lookup if it looks like a base58 address
    if (!isBase58Address(trimmed)) {
      final fallback = _shorten(trimmed);
      _cache['name:$trimmed'] = fallback;
      return fallback;
    }

    // Check if there's already a pending lookup for this address
    // This prevents duplicate concurrent requests which cause rate limiting
    if (_pendingLookups.containsKey(cacheKey)) {
      return _pendingLookups[cacheKey]!;
    }

    // Start the lookup and track it
    final lookupFuture = _performDomainLookup(trimmed, cacheKey);
    _pendingLookups[cacheKey] = lookupFuture;

    try {
      final result = await lookupFuture;
      return result;
    } finally {
      _pendingLookups.remove(cacheKey);
    }
  }

  /// Internal method to actually perform the domain lookup
  static Future<String> _performDomainLookup(
    String address,
    String cacheKey,
  ) async {
    // Try AllDomains (tld_parser) first for main domain
    // This covers .skr, .abc, .poor, .bonk, etc.
    try {
      final parser = _getTldParser();
      final userPubkey = solana.Ed25519HDPublicKey.fromBase58(address);
      final mainDomain = await parser.tryGetMainDomain(userPubkey);

      if (mainDomain != null && mainDomain.domain.isNotEmpty) {
        final domain = '${mainDomain.domain}${mainDomain.tld}';
        _cache[cacheKey] = domain;
        _cacheTimestamps[cacheKey] = DateTime.now();
        return domain;
      }
    } catch (e) {
      if (kDebugMode) {
        log('AddressNameResolver: TLD Parser main domain lookup failed: $e');
      }
    }

    // Fallback to shortened address
    final fallback = _shorten(address);
    _cache[cacheKey] = fallback;
    _cacheTimestamps[cacheKey] = DateTime.now();
    return fallback;
  }

  /// Resolve a user-provided input into a wallet address.
  /// - If input is a base58 address, returns it as-is.
  /// - If input looks like a domain (.skr, .abc, etc.), tries to resolve owner address.
  /// - Otherwise returns null (caller can handle error).
  static Future<String?> resolveAddress(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // If it's already a base58 address, accept as-is
    if (isBase58Address(trimmed)) return trimmed;

    // Cache hit
    if (_cache.containsKey('addr:$trimmed')) return _cache['addr:$trimmed'];

    if (isAllDomainsTld(trimmed)) {
      // Use TLD Parser for .skr, .abc, .poor, .bonk, etc.
      return _resolveAllDomainsTld(trimmed);
    }

    // Unknown domain format
    return null;
  }

  /// Resolve an AllDomains TLD using TLD Parser
  static Future<String?> _resolveAllDomainsTld(String domain) async {
    try {
      final parser = _getTldParser();

      // Normalize to lowercase - ANS protocol is case-sensitive but users expect case-insensitive
      // e.g., "HeisjOel.skr" should resolve the same as "heisjoel.skr"
      final normalizedDomain = domain.toLowerCase();

      final owner = await parser.getOwnerFromDomainTld(normalizedDomain);

      if (owner != null) {
        final ownerAddress = owner.toBase58();
        _cache['addr:$domain'] = ownerAddress;
        return ownerAddress;
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'AddressNameResolver: TLD Parser resolution failed for $domain: $e',
        );
      }
    }
    return null;
  }

  static bool _looksLikeName(String value) {
    if (value.contains(' ') || value.contains('@')) return true;
    // Check for any domain extension (.sol, .skr, etc.)
    if (isSupportedDomain(value)) return true;
    if (value.length < 32 || !_base58.hasMatch(value)) {
      return true; // not an address
    }
    return false;
  }

  static String _shorten(String address) {
    if (address.length <= 14) return address;
    final start = address.substring(0, 6);
    final end = address.substring(address.length - 4);
    return '$start...$end';
  }
}

/// A widget that resolves and displays a domain name for a wallet address
/// Can also show "You" when the address matches the current user's wallet
class ResolvedAddressText extends StatelessWidget {
  final String addressOrLabel;
  final TextStyle? style;
  final String prefix;
  final int maxLines;

  /// If provided and matches addressOrLabel, displays "You" instead
  final String? currentUserAddress;

  /// Custom label when address matches current user (default: "You")
  final String youLabel;

  const ResolvedAddressText({
    super.key,
    required this.addressOrLabel,
    this.style,
    this.prefix = '',
    this.maxLines = 1,
    this.currentUserAddress,
    this.youLabel = 'You',
  });

  @override
  Widget build(BuildContext context) {
    // Check if this is the current user
    if (currentUserAddress != null &&
        addressOrLabel.isNotEmpty &&
        addressOrLabel == currentUserAddress) {
      return Text(
        '$prefix$youLabel',
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );
    }

    return FutureBuilder<String>(
      future: AddressNameResolver.resolveDisplayName(addressOrLabel),
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        final text =
            (resolved == null || resolved.isEmpty) ? addressOrLabel : resolved;
        return Text(
          '$prefix$text',
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        );
      },
    );
  }
}
