import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Import your local SNS SDK
import 'package:sns_sdk/sns_sdk.dart';

/// Resolves Solana wallet addresses to SNS (.sol) domain names when available,
/// and resolves .sol domains to wallet addresses when provided by user.
/// Uses your local SNS SDK for proper resolution with graceful caching.
class AddressNameResolver {
  static final Map<String, String> _cache = {};
  static SnsClient? _snsClient;

  // Base58 charset check (quick heuristic)
  static final RegExp _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');

  // Public helpers
  static bool isBase58Address(String value) =>
      value.length >= 32 && value.length <= 50 && _base58.hasMatch(value);
  static bool isSolDomain(String value) => value.toLowerCase().endsWith('.sol');

  /// Get or create the SNS client using your local package
  static SnsClient _getSnsClient() {
    if (_snsClient != null) return _snsClient!;

    // Use mainnet for SNS resolution since .sol domains are on mainnet
    final rpcUrl = 'https://api.mainnet-beta.solana.com';
    final rpcClient = HttpRpcClient(rpcUrl);
    _snsClient = SnsClient(rpcClient);
    return _snsClient!;
  }

  /// Resolve a display name for a given input which may be a wallet or name.
  static Future<String> resolveDisplayName(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Unknown';
    if (_looksLikeName(trimmed)) return trimmed; // already a name/domain/email
    if (_cache.containsKey('name:$trimmed')) return _cache['name:$trimmed']!;

    // Only try reverse lookup if it looks like a base58 address
    if (!isBase58Address(trimmed)) {
      final fallback = _shorten(trimmed);
      _cache['name:$trimmed'] = fallback;
      return fallback;
    }

    try {
      final client = _getSnsClient();

      // Try to get primary domain for this wallet first
      final primaryResult = await getPrimaryDomain(
        GetPrimaryDomainParams(rpc: client.rpc, walletAddress: trimmed),
      );

      if (primaryResult != null && primaryResult.domainName.isNotEmpty) {
        final domain =
            primaryResult.domainName.endsWith('.sol')
                ? primaryResult.domainName
                : '${primaryResult.domainName}.sol';
        _cache['name:$trimmed'] = domain;
        return domain;
      }
    } catch (e) {
      if (kDebugMode)
        log('AddressNameResolver: Primary domain lookup failed: $e');
    }

    // Try to get all domains owned by this address and pick the first one
    try {
      final client = _getSnsClient();
      final domains = await getDomainsForAddress(
        GetDomainsForAddressParams(rpc: client.rpc, address: trimmed),
      );

      if (domains.isNotEmpty) {
        final domain = domains.first.domain;
        if (domain.isNotEmpty) {
          _cache['name:$trimmed'] = domain;
          return domain;
        }
      }
    } catch (e) {
      if (kDebugMode) log('AddressNameResolver: Domain lookup failed: $e');
    }

    // Fallback to shortened address
    final fallback = _shorten(trimmed);
    _cache['name:$trimmed'] = fallback;
    return fallback;
  }

  /// Resolve a user-provided input into a wallet address.
  /// - If input is a base58 address, returns it as-is.
  /// - If input looks like an SNS .sol domain, tries to resolve owner address.
  /// - Otherwise returns null (caller can handle error).
  static Future<String?> resolveAddress(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // If it's already a base58 address, accept as-is
    if (isBase58Address(trimmed)) return trimmed;

    // Cache hit
    if (_cache.containsKey('addr:$trimmed')) return _cache['addr:$trimmed'];

    // If it looks like a .sol domain, try resolving via your SNS SDK
    if (isSolDomain(trimmed)) {
      try {
        final client = _getSnsClient();

        // Use your SNS SDK resolve function
        final ownerAddress = await resolve(
          client,
          trimmed,
          config: const ResolveConfig(allowPda: 'any'),
        );

        if (ownerAddress.isNotEmpty && isBase58Address(ownerAddress)) {
          _cache['addr:$trimmed'] = ownerAddress;
          return ownerAddress;
        }
      } catch (e) {
        if (kDebugMode)
          log('AddressNameResolver: Domain resolution failed for $trimmed: $e');
      }
    }

    // Unknown format
    return null;
  }

  static bool _looksLikeName(String value) {
    if (value.contains(' ') || value.contains('@')) return true;
    if (value.toLowerCase().endsWith('.sol')) return true; // SNS primary
    if (value.length < 32 || !_base58.hasMatch(value))
      return true; // not an address
    return false;
  }

  static String _shorten(String address) {
    if (address.length <= 14) return address;
    final start = address.substring(0, 6);
    final end = address.substring(address.length - 4);
    return '$start...$end';
  }
}

class ResolvedAddressText extends StatelessWidget {
  final String addressOrLabel;
  final TextStyle? style;
  final String prefix;
  final int maxLines;

  const ResolvedAddressText({
    super.key,
    required this.addressOrLabel,
    this.style,
    this.prefix = '',
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
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
