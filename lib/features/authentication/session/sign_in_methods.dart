/// One account, many sign-ins: what `auth.signInMethods` and the link
/// procedures answer with, read strictly.
///
/// Settings shows every way into the account (wallet, X, Google), the one this
/// session used, Link for the others, and unlink where the BFF allows it —
/// never the way in being used, never the last. When Supabase can't link (the
/// X/Google is on another account, or the wallet signs in to one), the person
/// proves the other side with a sign-in made only for that and confirms what
/// happens (`LinkPreview`).
library;

/// The three ways in Settings knows.
enum SignInMethodKind { wallet, x, google }

SignInMethodKind? signInMethodKindOf(Object? value) => switch (value) {
  'wallet' => SignInMethodKind.wallet,
  'x' => SignInMethodKind.x,
  'google' => SignInMethodKind.google,
  _ => null,
};

extension SignInMethodKindNames on SignInMethodKind {
  /// What the BFF calls it (`auth.startSignInLink` `method`).
  String get wire => name;

  /// What a person reads.
  String get title => switch (this) {
    SignInMethodKind.wallet => 'Wallet',
    SignInMethodKind.x => 'X',
    SignInMethodKind.google => 'Google',
  };

  /// The Basil icon (assets/icons/basil).
  String get basilIcon => switch (this) {
    SignInMethodKind.wallet => 'wallet-outline',
    SignInMethodKind.x => 'twitter-solid',
    SignInMethodKind.google => 'google-solid',
  };
}

/// How a row unlinks: on this session's own sign-in through Supabase
/// ([nativeIdentityId]), or through the BFF ([serverRef]). Exactly one is set.
class SignInUnlink {
  const SignInUnlink.native(String this.nativeIdentityId) : serverRef = null;
  const SignInUnlink.server(String this.serverRef) : nativeIdentityId = null;

  final String? nativeIdentityId;
  final String? serverRef;
}

class SignInMethodRow {
  const SignInMethodRow({
    required this.id,
    required this.kind,
    required this.label,
    required this.current,
    this.unlink,
    this.alsoUnlinks = const [],
  });

  final String id;
  final SignInMethodKind kind;

  /// X username (no @), Google email, or wallet address. Null when unknown.
  final String? label;

  /// The way this session signed in.
  final bool current;

  /// Null: it can't be unlinked (in use, the account's first, or the last).
  final SignInUnlink? unlink;

  /// Other kinds on the same sign-in, which go with it.
  final List<SignInMethodKind> alsoUnlinks;

  /// "@name", the email, or a short wallet.
  String get display {
    final value = label;
    if (value == null || value.isEmpty) return kind.title;
    return switch (kind) {
      SignInMethodKind.x => '@$value',
      SignInMethodKind.wallet =>
        value.length > 12
            ? '${value.substring(0, 4)}…${value.substring(value.length - 4)}'
            : value,
      SignInMethodKind.google => value,
    };
  }
}

class SignInMethods {
  const SignInMethods({
    required this.rows,
    required this.linking,
    required this.fold,
  });

  final List<SignInMethodRow> rows;

  /// The server links and unlinks (ACCOUNT_LINKING_ENABLED).
  final bool linking;

  /// The server folds another account in (ACCOUNT_FOLD_ENABLED).
  final bool fold;

  SignInMethodRow? get current {
    for (final row in rows) {
      if (row.current) return row;
    }
    return null;
  }

  /// The kinds with no row yet: what Link is offered for.
  List<SignInMethodKind> get missing =>
      linking
          ? [
            for (final kind in SignInMethodKind.values)
              if (!rows.any((r) => r.kind == kind)) kind,
          ]
          : const [];

  /// Strict: a row that doesn't read cleanly is left out, never guessed.
  static SignInMethods? parse(Object? value) {
    if (value is! Map || value['methods'] is! List) return null;
    final rows = <SignInMethodRow>[];
    for (final raw in value['methods'] as List) {
      if (raw is! Map) continue;
      final kind = signInMethodKindOf(raw['kind']);
      final id = raw['id'];
      if (kind == null || id is! String || id.isEmpty) continue;
      final label = raw['label'];
      final unlink = raw['unlink'];
      SignInUnlink? route;
      if (unlink is Map) {
        if (unlink['mode'] == 'native' && unlink['identityId'] is String) {
          route = SignInUnlink.native(unlink['identityId'] as String);
        } else if (unlink['mode'] == 'server' && unlink['ref'] is String) {
          route = SignInUnlink.server(unlink['ref'] as String);
        }
      }
      final also = raw['alsoUnlinks'];
      rows.add(
        SignInMethodRow(
          id: id,
          kind: kind,
          label: label is String && label.isNotEmpty ? label : null,
          current: raw['current'] == true,
          unlink: route,
          alsoUnlinks: [
            if (also is List)
              for (final k in also)
                if (signInMethodKindOf(k) case final SignInMethodKind kind)
                  kind,
          ],
        ),
      );
    }
    return SignInMethods(
      rows: List.unmodifiable(rows),
      linking: value['linking'] == true,
      fold: value['fold'] == true,
    );
  }
}

/// An account, as a confirm sheet names it.
class LinkedAccount {
  const LinkedAccount({required this.userId, this.handle, this.displayName});

  final String userId;
  final String? handle;
  final String? displayName;

  String get display =>
      handle != null ? '@$handle' : (displayName ?? 'another account');

  static LinkedAccount? parse(Object? value) {
    if (value is! Map || value['userId'] is! String) return null;
    final handle = value['handle'];
    final name = value['displayName'];
    return LinkedAccount(
      userId: value['userId'] as String,
      handle: handle is String && handle.isNotEmpty ? handle : null,
      displayName: name is String && name.isNotEmpty ? name : null,
    );
  }
}

enum LinkOutcome { already, link, fold }

/// What completing a link would do (`auth.previewSignInLink`).
class LinkPreview {
  const LinkPreview({
    required this.outcome,
    required this.into,
    this.from,
    this.refusal,
  });

  final LinkOutcome outcome;
  final LinkedAccount into;
  final LinkedAccount? from;

  /// ACCOUNT_HAS_MONEY or ACCOUNT_FOLD_DISABLED: why it can't happen.
  final String? refusal;

  static LinkPreview? parse(Object? value) {
    if (value is! Map) return null;
    final outcome = switch (value['outcome']) {
      'already' => LinkOutcome.already,
      'link' => LinkOutcome.link,
      'fold' => LinkOutcome.fold,
      _ => null,
    };
    final into = LinkedAccount.parse(value['into']);
    if (outcome == null || into == null) return null;
    final refusal = value['refusal'];
    return LinkPreview(
      outcome: outcome,
      into: into,
      from: LinkedAccount.parse(value['from']),
      refusal: refusal is String && refusal.isNotEmpty ? refusal : null,
    );
  }
}

/// Link and unlink refusals (the BFF's codes, and Supabase's), one line each.
String signInLinkCopy(String code) => switch (code) {
  'ACCOUNT_LINKING_DISABLED' ||
  'manual_linking_disabled' => 'Linking isn’t on yet.',
  'ACCOUNT_FOLD_DISABLED' => 'Moving accounts isn’t on yet.',
  'ACCOUNT_HAS_MONEY' =>
    'It has trades, so it stays separate. Sign in to it and link from there.',
  'ACCOUNT_NOT_FOLDABLE' => 'That account can’t be moved.',
  'LINK_TICKET_INVALID' => 'That took too long. Try again.',
  'LINK_METHOD_MISMATCH' => 'That was a different sign-in. Try again.',
  'LINK_RATE_LIMITED' => 'Too many tries. Wait a minute.',
  'SIGN_IN_IN_USE' => 'You’re signed in with that one.',
  'SIGN_IN_NOT_FOUND' => 'Already unlinked.',
  'WALLET_OWNED_BY_ANOTHER_USER' ||
  'WALLET_REQUIRES_TRANSFER' => 'That wallet is on another account.',
  'identity_already_exists' => 'That one is on another account.',
  'single_identity_not_deletable' => 'It’s your only way in.',
  'cancelled' => 'Nothing changed.',
  _ => 'That didn’t work. Try again.',
};
