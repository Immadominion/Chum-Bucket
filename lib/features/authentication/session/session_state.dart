/// The observable shape of a Chumbucket sign-in.
///
/// This file holds only value types — no Supabase, no HTTP, no Flutter. It is
/// the vocabulary `ChumbucketSession` publishes and the UI switches on.
///
/// The single rule it exists to enforce (contract §0 invariant 3): the thing a
/// screen may act on as *identity* is [SessionIdentity.userId], the canonical
/// `public.users.id`. A wallet is a linked credential and never appears here.
/// [SessionIdentity.authUserId] is the caller's own `auth.uid()` — it is
/// carried for diagnostics and for linking flows, and must never be handed to
/// `CallsProvider.setViewer`.
library;

/// Where a person stands with respect to signing in.
///
/// Five states, each separately reachable and separately renderable. They are
/// deliberately not collapsed: "we are asking the BFF who you are" and "the BFF
/// told us you have no account" need different words on screen.
enum SessionStatus {
  /// No Supabase session at all.
  ///
  /// Reading **still works** in this state — the feed, a market, a person, a
  /// shared call. Only writing needs a session, and the repository refuses
  /// those locally before a request is sent.
  signedOut,

  /// The Google OAuth round trip is in flight: the browser is open, or the
  /// callback has not come back yet.
  signingIn,

  /// A verified Supabase session exists, but no canonical `public.users.id`
  /// has been resolved for it yet — `auth.whoami` is in flight.
  ///
  /// The access token is already usable as a bearer in this state; the
  /// *viewer* is not yet known, so `setViewer` must not be called.
  identityPending,

  /// A verified Supabase session **and** a canonical `public.users.id`.
  /// This is the only state in which a person may make a call.
  ready,

  /// The last attempt failed. [SessionError.kind] says whether that was the
  /// network or a refusal, which is the difference between "try again" and
  /// "this will keep failing until something changes".
  failed,
}

/// Why a session attempt failed, at the only granularity the UI can act on.
///
/// `network` means the round trip never completed — retrying later is
/// reasonable. `refused` means the server answered and said no — retrying the
/// same thing will fail the same way.
enum SessionErrorKind { network, refused }

/// Machine-readable reasons, so a screen can say something specific without
/// parsing prose. These mirror the BFF's own `AuthIdentityErrorCode` values
/// (`src/auth/AuthIdentityError.ts`), which arrive as the tRPC error *message*.
abstract final class SessionErrorCode {
  /// The browser closed, or the callback never arrived, before a session did.
  static const String oauthCancelled = 'OAUTH_CANCELLED';

  /// No credential reached the BFF.
  static const String tokenMissing = 'AUTH_TOKEN_MISSING';

  /// The BFF could not verify the access token against the issuer.
  static const String tokenInvalid = 'AUTH_TOKEN_INVALID';

  /// The token verified, but no `public.users` row points at that `auth.uid()`.
  /// The person has a credential and no account behind it yet.
  static const String userUnlinked = 'AUTH_USER_UNLINKED';

  /// More than one canonical user claims that `auth.uid()`. Server-side bug.
  static const String userAmbiguous = 'AUTH_USER_AMBIGUOUS';

  /// Identity is not switched on for this deployment at all.
  static const String identityNotConfigured = 'IDENTITY_NOT_CONFIGURED';

  /// The deployed `auth.whoami` is still declared a tRPC **query**, so it can
  /// only be reached by a GET that carries the access token in the URL.
  ///
  /// This client will not do that — a credential never goes in a query string
  /// — so it POSTs the token in the body and surfaces this instead. The
  /// one-word server change that clears it is filed in
  /// `docs/contracts/integration-requests/packet-session.md`.
  static const String whoamiMethodNotSupported = 'WHOAMI_METHOD_NOT_SUPPORTED';

  /// The BFF answered with something this client could not read.
  static const String unreadable = 'BFF_UNREADABLE';

  /// The round trip never completed.
  static const String unreachable = 'BFF_UNREACHABLE';
}

/// A failure a screen can render without knowing anything about tRPC.
class SessionError {
  const SessionError({
    required this.kind,
    required this.message,
    required this.code,
  });

  /// The round trip never completed. Offer a retry.
  const SessionError.network(
    this.message, {
    this.code = SessionErrorCode.unreachable,
  }) : kind = SessionErrorKind.network;

  /// The server answered and said no. Retrying the same thing will not help.
  const SessionError.refused(this.message, {required this.code})
    : kind = SessionErrorKind.refused;

  final SessionErrorKind kind;

  /// Already human-readable. Never contains a token — the BFF's identity
  /// errors are bare codes by construction (`authRoutes.ts`: "the TRPCError
  /// message is always the bare code ... structurally incapable of carrying a
  /// nonce, a signature, a token or a key").
  final String message;

  /// One of [SessionErrorCode].
  final String code;

  bool get isNetwork => kind == SessionErrorKind.network;
  bool get isRefused => kind == SessionErrorKind.refused;

  /// True when the person has a valid credential but no canonical account yet
  /// — the one refusal whose remedy is *not* "sign in again".
  bool get isUnlinked => code == SessionErrorCode.userUnlinked;

  @override
  String toString() => 'SessionError($code, ${kind.name}): $message';
}

/// What `auth.whoami` answers with.
///
/// [userId] is the canonical `public.users.id` and the **only** value that may
/// reach `CallsProvider.setViewer`. [authUserId] is the caller's own
/// `auth.uid()`; the BFF returns it deliberately because the client already
/// holds it, and it is not another user's identifier.
class SessionIdentity {
  const SessionIdentity({required this.userId, required this.authUserId});

  final String userId;
  final String authUserId;

  @override
  bool operator ==(Object other) =>
      other is SessionIdentity &&
      other.userId == userId &&
      other.authUserId == authUserId;

  @override
  int get hashCode => Object.hash(userId, authUserId);

  @override
  String toString() =>
      'SessionIdentity(userId: $userId, authUserId: $authUserId)';
}

/// What `auth.identityStatus` answers with — public, credential-free, and
/// useful for telling "this build has identity switched off" apart from "your
/// account is not linked".
class SessionIdentityStatus {
  const SessionIdentityStatus({
    required this.enabled,
    required this.network,
    required this.proofVersion,
  });

  final bool enabled;
  final String network;
  final int proofVersion;

  @override
  String toString() =>
      'SessionIdentityStatus(enabled: $enabled, network: $network, '
      'proofVersion: $proofVersion)';
}
