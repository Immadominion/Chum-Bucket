import 'dart:convert';
import 'dart:typed_data';
import 'package:solana/base58.dart';

/// MWA credential, not application identity. Never log/serialize for diagnostics.
class MwaAuthResult {
  final String walletAddress;
  final String authToken;
  final String? accountLabel;
  final Uri? walletUriBase;
  final Uint8List publicKeyBytes;
  final String? snsDomain;

  const MwaAuthResult({
    required this.walletAddress,
    required this.authToken,
    required this.publicKeyBytes,
    this.accountLabel,
    this.walletUriBase,
    this.snsDomain,
  });

  bool get hasSeekerDomain =>
      snsDomain?.toLowerCase().endsWith('.skr') ?? false;
  bool get hasSnsDomain => snsDomain != null && snsDomain!.isNotEmpty;
  String get displayName {
    if (hasSnsDomain) return snsDomain!;
    return walletAddress.length > 12
        ? '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}'
        : walletAddress;
  }

  /// Credential-bearing representation: for the secure store ONLY.
  Map<String, dynamic> toJson() => {
    'walletAddress': walletAddress,
    'authToken': authToken,
    'accountLabel': accountLabel,
    'walletUriBase': walletUriBase?.toString(),
    'publicKeyBytes': base64Encode(publicKeyBytes),
    'snsDomain': snsDomain,
  };

  factory MwaAuthResult.fromJson(Map<String, dynamic> json) {
    try {
      final address = json['walletAddress'] as String;
      final token = json['authToken'] as String;
      final key = base64Decode(json['publicKeyBytes'] as String);
      final uriValue = json['walletUriBase'] as String?;
      // wallet_uri_base is an optional reconnection hint, not the credential.
      // Only HTTPS endpoint-specific URIs are safe to use (MWA 2.0). A wallet
      // returning another scheme must not prevent a valid grant from being
      // saved; simply never persist or follow that untrusted hint.
      final parsedUri = uriValue == null ? null : Uri.tryParse(uriValue);
      final uri =
          parsedUri != null &&
                  parsedUri.scheme == 'https' &&
                  parsedUri.host.isNotEmpty &&
                  parsedUri.userInfo.isEmpty
              ? parsedUri
              : null;
      if (key.length != 32 ||
          base58encode(key) != address ||
          token.isEmpty ||
          token.length > 16384) {
        throw const FormatException();
      }
      return MwaAuthResult(
        walletAddress: address,
        authToken: token,
        publicKeyBytes: key,
        accountLabel: json['accountLabel'] as String?,
        walletUriBase: uri,
        snsDomain: json['snsDomain'] as String?,
      );
    } catch (_) {
      // Parsing exceptions can embed the entire credential-bearing JSON.
      throw const FormatException('Invalid saved wallet session');
    }
  }

  MwaAuthResult copyWithDomain(String? domain) => MwaAuthResult(
    walletAddress: walletAddress,
    authToken: authToken,
    publicKeyBytes: publicKeyBytes,
    accountLabel: accountLabel,
    walletUriBase: walletUriBase,
    snsDomain: domain,
  );

  @override
  String toString() => 'MwaAuthResult(<redacted>)';
}
