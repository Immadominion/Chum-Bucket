import 'package:solana/solana.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

enum FriendIdentifierKind {
  /// A Solana wallet address.
  wallet,

  /// A wallet name such as `you.skr`, resolved to a wallet on the device.
  domain,

  /// An X profile link: an X account, and nothing else.
  xLink,

  /// `@name` or `name`: an X handle or a Chumbucket @username — the server
  /// looks up both.
  handle,
}

/// What a person typed into Add a friend, recognised by its shape only. Who
/// it belongs to is the server's answer (`people.find`), shown on a card
/// before anything is added.
class FriendIdentifier {
  const FriendIdentifier(this.kind, this.value);
  final FriendIdentifierKind kind;

  /// The wallet as typed; otherwise lowercase, without @.
  final String value;

  static bool isWallet(String value) {
    if (value.length < 32 || value.length > 44) return false;
    try {
      return Ed25519HDPublicKey.fromBase58(value).bytes.length == 32;
    } catch (_) {
      return false;
    }
  }

  static const _xHosts = {
    'x.com',
    'www.x.com',
    'mobile.x.com',
    'twitter.com',
    'www.twitter.com',
    'mobile.twitter.com',
  };

  /// X paths that are pages, not people — the same list as the server's
  /// (personFinder.ts X_RESERVED), so a link it would refuse is refused here.
  static const _xReserved = {
    'home',
    'explore',
    'search',
    'intent',
    'settings',
    'i',
    'messages',
    'notifications',
    'compose',
    'hashtag',
    'share',
    'login',
    'logout',
    'signup',
    'tos',
    'privacy',
    'about',
  };

  static final _xHandle = RegExp(r'^[A-Za-z0-9_]{1,15}$');

  /// X handles are 1–15 characters, Chumbucket usernames 3–20.
  static final _handle = RegExp(r'^[A-Za-z0-9_]{1,20}$');

  static FriendIdentifier? parse(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    if (isWallet(value)) {
      return FriendIdentifier(FriendIdentifierKind.wallet, value);
    }
    if (RegExp(r'^[a-zA-Z0-9-]+\.[a-zA-Z]+$').hasMatch(value) &&
        AddressNameResolver.isSupportedDomain(value)) {
      return FriendIdentifier(FriendIdentifierKind.domain, value.toLowerCase());
    }
    if (value.contains('/') || value.contains('.')) {
      final uri = Uri.tryParse(
        value.contains('://') ? value : 'https://$value',
      );
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          !_xHosts.contains(uri.host.toLowerCase())) {
        return null;
      }
      // x.com/name, or a post's author: x.com/name/status/123.
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return null;
      final handle = segments.first;
      if (_xReserved.contains(handle.toLowerCase()) ||
          !_xHandle.hasMatch(handle)) {
        return null;
      }
      return FriendIdentifier(FriendIdentifierKind.xLink, handle.toLowerCase());
    }
    final bare = value.replaceFirst(RegExp(r'^@'), '');
    if (!_handle.hasMatch(bare)) return null;
    return FriendIdentifier(FriendIdentifierKind.handle, bare.toLowerCase());
  }

  /// Whether this can be an X account, so "not on Chumbucket" can show it.
  bool get canBeXHandle =>
      kind == FriendIdentifierKind.xLink ||
      (kind == FriendIdentifierKind.handle && _xHandle.hasMatch(value));

  /// What to ask `people.find`. A link stays a link so only X accounts are
  /// looked up; a name needs resolving to its wallet first (null).
  String? get query => switch (kind) {
    FriendIdentifierKind.wallet => value,
    FriendIdentifierKind.xLink => 'https://x.com/$value',
    FriendIdentifierKind.handle => '@$value',
    FriendIdentifierKind.domain => null,
  };

  /// How the sheet names what was typed.
  String get label => switch (kind) {
    FriendIdentifierKind.wallet =>
      '${value.substring(0, 4)}…${value.substring(value.length - 4)}',
    FriendIdentifierKind.domain => value,
    FriendIdentifierKind.xLink || FriendIdentifierKind.handle => '@$value',
  };
}
