import 'package:solana/solana.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

enum FriendIdentifierKind { wallet, domain, xHandle }

/// Syntactic detection only. A handle is not proof of an X account or wallet.
class FriendIdentifier {
  const FriendIdentifier(this.kind, this.value);
  final FriendIdentifierKind kind;
  final String value;

  static bool isWallet(String value) {
    if (value.length < 32 || value.length > 44) return false;
    try {
      return Ed25519HDPublicKey.fromBase58(value).bytes.length == 32;
    } catch (_) {
      return false;
    }
  }

  static FriendIdentifier? parse(String input) {
    var value = input.trim();
    if (isWallet(value)) {
      return FriendIdentifier(FriendIdentifierKind.wallet, value);
    }
    if (RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]+$').hasMatch(value) &&
        AddressNameResolver.isSupportedDomain(value)) {
      return FriendIdentifier(FriendIdentifierKind.domain, value.toLowerCase());
    }
    if (value.contains('/')) {
      final uri = Uri.tryParse(
        value.contains('://') ? value : 'https://$value',
      );
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          !const {
            'x.com',
            'www.x.com',
            'twitter.com',
            'www.twitter.com',
          }.contains(uri.host) ||
          uri.pathSegments.length != 1) {
        return null;
      }
      value = uri.pathSegments.single;
      if (const {
        'home',
        'explore',
        'search',
        'intent',
        'settings',
        'i',
        'messages',
        'notifications',
      }.contains(value.toLowerCase())) {
        return null;
      }
    }
    value = value.replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(value)) return null;
    return FriendIdentifier(FriendIdentifierKind.xHandle, value.toLowerCase());
  }

  String get suggestedName => switch (kind) {
    FriendIdentifierKind.wallet =>
      '${value.substring(0, 4)}…${value.substring(value.length - 4)}',
    FriendIdentifierKind.domain => value,
    FriendIdentifierKind.xHandle => '@$value',
  };
}
