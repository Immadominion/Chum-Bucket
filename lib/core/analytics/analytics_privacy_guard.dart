/// The privacy control for analytics — a mechanism, not a policy document.
///
/// Packet I's acceptance reads: *"Analytics events are deduplicated and contain
/// no secrets, balances, signatures, or full thesis text."* A rule that only
/// exists in a comment is not a control, so this file is the control: every
/// event passes through [AnalyticsPrivacyGuard] before any sink sees it, and a
/// payload that breaks a rule is **dropped**, not trimmed and not logged with
/// its offending value.
///
/// ## The rules, in the order they are checked
///
/// 1. **Shape.** A payload is flat: `bool`, finite `num`, or `String`. A `Map`,
///    a `List` or a `null` is rejected — nesting is how a whole object gets
///    smuggled into a "dimension".
/// 2. **Key.** Keys are split into words (`walletAddress` → `wallet`,
///    `address`; `amount_sol` → `amount`, `sol`) and each word is checked
///    against [deniedKeyWords]. Word-splitting rather than substring matching
///    is deliberate: `resolution` contains "sol" and must stay legal.
///    [allowedDerivedKeys] is the short, explicit list of keys that name a
///    *derivation* of a denied thing (`thesisPresent`, `thesisLengthBucket`)
///    rather than the thing itself.
/// 3. **Value.** Every string is scanned for the shapes a secret actually has:
///    an email, a JWT, a base58 address or signature, a long hex or base64
///    blob, a bearer prefix. Independent of the key, because a wallet under
///    `personId` is still a wallet.
/// 4. **Free text.** A value containing whitespace, or longer than
///    [maxValueLength], is user-authored prose — a thesis, a market question, a
///    display name — and is rejected. Ids and enum tokens have neither
///    property, which is what makes "an id is fine, a raw string is not"
///    mechanically decidable.
///
/// Nothing here inspects the *meaning* of a value. It inspects shape, which is
/// the only thing that cannot be argued with at 2am before a deadline.
library;

import 'package:chumbucket/core/analytics/analytics_event.dart';

/// Why a payload was refused. Carries the offending **key** and a rule id —
/// never the offending value, because a violation report that prints the
/// secret it caught is a second leak.
class AnalyticsPrivacyViolation {
  final AnalyticsPrivacyRule rule;

  /// The property key at fault, or `'<name>'` for a bad event name.
  final String key;

  final String detail;

  const AnalyticsPrivacyViolation({
    required this.rule,
    required this.key,
    required this.detail,
  });

  @override
  String toString() => '${rule.name} at "$key": $detail';
}

enum AnalyticsPrivacyRule {
  /// A `Map`, `List`, `null` or other non-scalar value.
  nonScalarValue,

  /// A number that is NaN or infinite.
  nonFiniteNumber,

  /// The key names something that must never be collected.
  deniedKey,

  /// The value has the shape of a secret (address, signature, token, email).
  secretShapedValue,

  /// The value is user-authored prose rather than an id or an enum token.
  freeTextValue,

  /// More properties than any legitimate event needs.
  tooManyProps,
}

/// Thrown only by [AnalyticsPrivacyGuard.enforce]. The recorder does not use
/// it — dropping is the production behaviour; throwing is for tests and for
/// anyone who wants a hard failure at a seam.
class AnalyticsPrivacyException implements Exception {
  final List<AnalyticsPrivacyViolation> violations;
  const AnalyticsPrivacyException(this.violations);

  @override
  String toString() =>
      'AnalyticsPrivacyException: ${violations.map((v) => '$v').join('; ')}';
}

abstract final class AnalyticsPrivacyGuard {
  /// Longest permissible string value. A UUID is 36; the longest legitimate
  /// enum token in this app is `CLOSED_PENDING_RESOLUTION` at 25.
  static const int maxValueLength = 64;

  /// A generous ceiling. Every event in `analytics_events.dart` is well under
  /// it; exceeding it means somebody is shipping a whole object.
  static const int maxProps = 24;

  /// Words that may never appear in a property key.
  ///
  /// Matched per word after splitting camelCase and snake_case, so
  /// `resolution`, `position` and `confidencePresent` are unaffected while
  /// `walletAddress`, `amountSol`, `txSignature` and `accessToken` are not.
  static const Set<String> deniedKeyWords = {
    // Identity credentials and keys
    'wallet', 'wallets', 'address', 'addresses', 'pubkey', 'pubkeys',
    'publickey', 'privatekey', 'key', 'keys', 'keypair', 'secret', 'secrets',
    'seed', 'seeds', 'mnemonic', 'passphrase', 'password', 'pin', 'nonce',
    'token', 'tokens', 'jwt', 'bearer', 'auth', 'session', 'credential',
    'credentials', 'apikey',
    // Proofs
    'signature', 'signatures', 'sig', 'sigs', 'siws', 'txsig', 'tx',
    // Money
    'balance', 'balances', 'lamports', 'lamport', 'sol', 'sols', 'usd', 'usdc',
    'stake', 'staked', 'amount', 'amounts', 'payout', 'payouts', 'pnl',
    'profit', 'loss', 'wager', 'deposit', 'withdrawal', 'cost', 'price',
    'fee', 'fees', 'value', 'spend',
    // Personal / user-authored content
    'email', 'emails', 'phone', 'msisdn', 'name', 'fullname', 'displayname',
    'username', 'handle', 'handles', 'bio', 'avatar', 'thesis', 'note',
    'notes', 'caption', 'message', 'body', 'text', 'comment', 'question',
    'rules', 'rulestext', 'query', 'search', 'ip', 'location', 'lat', 'lng',
  };

  /// Keys that contain a denied word but name a non-reversible *derivation* of
  /// it. Deliberately tiny, and every entry must be justifiable in one line.
  ///
  /// * `thesisPresent` — a bool. Says a thesis exists; reveals none of it.
  /// * `thesisLengthBucket` — one of four wide buckets. See
  ///   [ThesisLengthBucket].
  static const Set<String> allowedDerivedKeys = {
    AnalyticsProps.thesisPresent,
    AnalyticsProps.thesisLengthBucket,
  };

  // --- value shapes ---------------------------------------------------------

  static final RegExp _email = RegExp(
    r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$',
  );

  /// `header.payload.signature`, base64url segments.
  static final RegExp _jwt = RegExp(
    r'^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$',
  );

  /// Base58 with no separators, 32 chars or more: a Solana address (32–44) or
  /// an ed25519 signature (86–88). Ids in this codebase are slugs or UUIDs,
  /// both of which carry `_` or `-` and so cannot match.
  static final RegExp _base58Blob = RegExp(
    r'^[1-9A-HJ-NP-Za-km-z]{32,}$',
  );

  /// A hex key or transaction hash.
  static final RegExp _hexBlob = RegExp(r'^(0x)?[0-9a-fA-F]{32,}$');

  /// A base64 blob — a serialised transaction, a captured image, a key.
  static final RegExp _base64Blob = RegExp(r'^[A-Za-z0-9+/]{40,}={0,2}$');

  static final RegExp _keyWordSplit = RegExp(r'[^A-Za-z0-9]+');
  static final RegExp _camelBoundary = RegExp(r'(?<=[a-z0-9])(?=[A-Z])');

  /// Splits a key into lowercase words. `walletAddress` → `[wallet, address]`,
  /// `amount_sol` → `[amount, sol]`, `resolution` → `[resolution]`.
  static List<String> keyWords(String key) {
    return key
        .split(_keyWordSplit)
        .expand((part) => part.split(_camelBoundary))
        .where((word) => word.isNotEmpty)
        .map((word) => word.toLowerCase())
        .toList(growable: false);
  }

  /// Every violation in [props], or an empty list when the payload is clean.
  ///
  /// Returns all of them rather than the first so a test can assert on the
  /// specific rule that fired.
  static List<AnalyticsPrivacyViolation> inspect(Map<String, Object?> props) {
    final violations = <AnalyticsPrivacyViolation>[];

    if (props.length > maxProps) {
      violations.add(
        AnalyticsPrivacyViolation(
          rule: AnalyticsPrivacyRule.tooManyProps,
          key: '<payload>',
          detail: '${props.length} properties exceeds the $maxProps limit',
        ),
      );
    }

    for (final entry in props.entries) {
      final key = entry.key;
      final value = entry.value;

      // 2. Key.
      if (!allowedDerivedKeys.contains(key)) {
        for (final word in keyWords(key)) {
          if (deniedKeyWords.contains(word)) {
            violations.add(
              AnalyticsPrivacyViolation(
                rule: AnalyticsPrivacyRule.deniedKey,
                key: key,
                detail: 'key word "$word" may never be collected',
              ),
            );
            break;
          }
        }
      }

      // 1. Shape.
      if (value == null) {
        violations.add(
          AnalyticsPrivacyViolation(
            rule: AnalyticsPrivacyRule.nonScalarValue,
            key: key,
            detail: 'null — omit the property instead',
          ),
        );
        continue;
      }
      if (value is num) {
        if (value.isNaN || value.isInfinite) {
          violations.add(
            AnalyticsPrivacyViolation(
              rule: AnalyticsPrivacyRule.nonFiniteNumber,
              key: key,
              detail: 'not a finite number',
            ),
          );
        }
        continue;
      }
      if (value is bool) continue;
      if (value is! String) {
        violations.add(
          AnalyticsPrivacyViolation(
            rule: AnalyticsPrivacyRule.nonScalarValue,
            key: key,
            detail: '${value.runtimeType} is not bool, num or String',
          ),
        );
        continue;
      }

      // 3 and 4. Value.
      final violation = inspectStringValue(key, value);
      if (violation != null) violations.add(violation);
    }

    return violations;
  }

  /// The string scanner, exposed so it can be reused (and tested) on its own.
  static AnalyticsPrivacyViolation? inspectStringValue(
    String key,
    String value,
  ) {
    if (value.isEmpty) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.freeTextValue,
        key: key,
        detail: 'empty — omit the property instead',
      );
    }
    // Secret shapes are checked before the length rule. A signature is 88
    // characters and a JWT is longer still; both would trip the length rule,
    // but "too long" is the wrong diagnosis for a credential and reads as a
    // formatting nit in a review.
    if (_email.hasMatch(value)) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.secretShapedValue,
        key: key,
        detail: 'looks like an email address',
      );
    }
    if (_jwt.hasMatch(value)) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.secretShapedValue,
        key: key,
        detail: 'looks like a JWT',
      );
    }
    if (_base58Blob.hasMatch(value)) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.secretShapedValue,
        key: key,
        detail: 'looks like a base58 address or signature',
      );
    }
    if (_hexBlob.hasMatch(value)) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.secretShapedValue,
        key: key,
        detail: 'looks like a hex key or hash',
      );
    }
    if (_base64Blob.hasMatch(value)) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.secretShapedValue,
        key: key,
        detail: 'looks like a base64 blob',
      );
    }
    if (value.length > maxValueLength) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.freeTextValue,
        key: key,
        detail: '${value.length} chars exceeds the $maxValueLength limit',
      );
    }
    // Free text: prose has spaces; ids and enum tokens do not.
    if (value.contains(RegExp(r'\s'))) {
      return AnalyticsPrivacyViolation(
        rule: AnalyticsPrivacyRule.freeTextValue,
        key: key,
        detail: 'contains whitespace — ids and enum tokens do not',
      );
    }
    return null;
  }

  /// True when [props] may be delivered.
  static bool isClean(Map<String, Object?> props) => inspect(props).isEmpty;

  /// Throws on the first violating payload. Used at seams that would rather
  /// fail loudly than silently drop; the recorder deliberately does not.
  static void enforce(Map<String, Object?> props) {
    final violations = inspect(props);
    if (violations.isNotEmpty) throw AnalyticsPrivacyException(violations);
  }
}
