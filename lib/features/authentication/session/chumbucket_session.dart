/// `ChumbucketSession` — the app's primary identity.
///
/// Before this existed the mobile app had no primary auth at all: the only
/// Supabase sign-in in the codebase is `ArenaProvider.linkOAuthIdentity`, which
/// *links* a Google account onto a wallet that is already connected. That is a
/// linking flow, not a way in. `calls.create` needs a verified Supabase
/// session, so with no primary auth nobody could make a call.
///
/// ## The chain this class owns
///
/// ```text
///   Google (Supabase OAuth)
///        │  SupabaseAuthPort.startGoogleSignIn  →  login-callback deep link
///        ▼
///   access token  ──────────────►  bffAuthToken()  ──►  BffCallsRepository
///        │                                              (Authorization: Bearer)
///        │  SessionBffClient.whoami(token)
///        ▼
///   { userId, authUserId }
///        │  userId = canonical public.users.id  (contract §0 invariant 3)
///        ▼
///   CallsProvider.setViewer(userId)
/// ```
///
/// `setViewer` is **not** called from here. This class publishes [userId] and
/// notifies; `main.dart` binds the two with a `ChangeNotifierProxyProvider`.
/// The exact patch is filed at
/// `docs/contracts/integration-requests/packet-session.md`, because `main.dart`
/// is integration-owned (contract §6).
///
/// ## Two rules that are not negotiable
///
/// 1. **Reading never requires a session.** [SessionStatus.signedOut] is a
///    perfectly good state to browse the feed in. Nothing here blocks a read,
///    and `bffAuthToken()` returning null is a normal answer, not an error.
/// 2. **Identity is the canonical `public.users.id`.** [userId] is the only
///    value that may reach `setViewer`. Never [authUserId], never a wallet.
///
/// ## The credential
///
/// The access token is never logged, never written to a file, never put in a
/// URL or a query string, and never included in [toString]. It leaves this
/// object through exactly two doors: the `Authorization: Bearer` header, and
/// the POST body of `auth.whoami` (which is what that procedure takes as its
/// input).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';

/// How long to wait for the OAuth callback before giving up.
///
/// Two minutes, matching `ArenaProvider.linkOAuthIdentity`. Long enough to
/// pick an account and type a password; short enough that a person who
/// abandoned the browser is not stuck on a spinner forever.
const Duration kSessionOAuthTimeout = Duration(minutes: 2);

/// The primary sign-in, as a [ChangeNotifier].
///
/// Every state change notifies exactly once. The five states of
/// [SessionStatus] are each separately reachable — see
/// `test/session_chumbucket_session_test.dart`, which drives all five through
/// an injected fake with no network and no Supabase.
class ChumbucketSession extends ChangeNotifier {
  ChumbucketSession({
    SupabaseAuthPort? auth,
    SessionBffClient? bff,
    String redirectTo = kChumbucketOAuthRedirect,
    Duration oauthTimeout = kSessionOAuthTimeout,
  }) : _auth = auth ?? const SupabaseFlutterAuthPort(),
       _bff = bff ?? SessionBffClient(),
       _ownsBff = bff == null,
       _redirectTo = redirectTo,
       _oauthTimeout = oauthTimeout;

  final SupabaseAuthPort _auth;
  final SessionBffClient _bff;
  final bool _ownsBff;
  final String _redirectTo;
  final Duration _oauthTimeout;

  StreamSubscription<SupabaseAuthEvent>? _subscription;
  Completer<SupabaseSessionSnapshot?>? _pendingSignIn;
  Future<void>? _resolution;
  bool _disposed = false;
  int _sessionEpoch = 0;

  SupabaseSessionSnapshot? _session;
  SessionIdentity? _identity;
  SessionStatus _status = SessionStatus.signedOut;
  SessionError? _error;

  // ---------------------------------------------------------------------------
  // What a screen reads
  // ---------------------------------------------------------------------------

  SessionStatus get status => _status;

  /// Non-null exactly when [status] is [SessionStatus.failed].
  SessionError? get error => _error;

  /// The canonical `public.users.id`.
  ///
  /// **This — and only this — is what `CallsProvider.setViewer` takes.** It is
  /// null until `auth.whoami` has answered, which is why
  /// [SessionStatus.identityPending] exists as its own state: a Supabase
  /// session is not yet an identity.
  String? get userId => _identity?.userId;

  /// The caller's own `auth.uid()`. Diagnostics and linking flows only.
  /// Passing this to `setViewer` would violate contract §0 invariant 3.
  String? get authUserId => _identity?.authUserId ?? _session?.authUserId;

  /// The bearer the BFF verifies, or null when signed out.
  ///
  /// Prefer [bffAuthToken] for anything that makes a request: it refreshes a
  /// token that is about to expire, where this getter is a plain read of what
  /// is currently held.
  String? get accessToken => _session?.accessToken;

  /// True when there is a verified Supabase session, resolved or not. A write
  /// still needs [isReady]; this only says a credential exists.
  bool get hasSupabaseSession => _session != null;

  /// True when a person can make a call: a session **and** a canonical user.
  bool get isReady => _status == SessionStatus.ready && userId != null;

  /// True while the OAuth round trip or `auth.whoami` is in flight — the two
  /// states a button should show a spinner for.
  bool get isBusy =>
      _status == SessionStatus.signingIn ||
      _status == SessionStatus.identityPending;

  /// The token provider to hand to `buildCallsRepository(authToken:)`.
  ///
  /// Matches `CallsBffAuthTokenProvider` (`FutureOr<String?> Function()`).
  /// Returning null is not an error — it is what "signed out" looks like to
  /// the repository, and reading keeps working.
  ///
  /// Refreshes first when the held token is inside its expiry skew, so a write
  /// does not fail on a token that went stale while the app sat in the
  /// background. If the refresh fails, the held token is returned anyway: the
  /// server is the authority on whether it is still good, and a local guess
  /// that says "signed out" would be a worse lie than a 401.
  Future<String?> bffAuthToken() async {
    final epoch = _sessionEpoch;
    final held = _session;
    if (held == null) return null;
    if (!held.isExpiring()) return held.accessToken;
    final refreshed = await _tryRefresh();
    // A failed refresh may fall back to this session's held token, but never
    // to a credential belonging to an account that signed out in the meantime.
    if (_disposed || epoch != _sessionEpoch) return null;
    if (refreshed == null) return held.accessToken;
    _notify();
    return refreshed.accessToken;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Call once at startup, after `Supabase.initialize()`.
  ///
  /// Subscribes to auth changes for the life of the app, adopts a session
  /// already restored from storage, and resolves it to a canonical user. Safe
  /// to call more than once; the subscription is made exactly once.
  Future<void> restore() async {
    _ensureSubscribed();
    final existing = _auth.currentSession;
    if (existing == null) {
      _applySignedOut();
      return;
    }
    _session = existing;
    await _resolveIdentity();
  }

  /// Open Google, wait for the callback, then resolve the canonical user.
  ///
  /// Mirrors the approach already proven in `ArenaProvider.linkOAuthIdentity`:
  /// listen to the auth stream first, launch the consent screen in the system
  /// browser, and let the `dev.cleva.chumbucket://login-callback` deep link
  /// deliver the session. The difference is what it is for — this is the
  /// primary identity, not a credential linked onto an existing account.
  ///
  /// Never throws. Every failure lands in [error] with [status] =
  /// [SessionStatus.failed].
  Future<void> signInWithGoogle() async {
    if (_status == SessionStatus.signingIn) return;
    _ensureSubscribed();

    final pending = Completer<SupabaseSessionSnapshot?>();
    _pendingSignIn = pending;
    _status = SessionStatus.signingIn;
    _error = null;
    _notify();

    try {
      final launched = await _auth.startGoogleSignIn(redirectTo: _redirectTo);
      if (!launched) {
        _applyFailure(
          const SessionError.refused(
            "We couldn't open the Google sign-in page.",
            code: SessionErrorCode.oauthCancelled,
          ),
        );
        return;
      }
      final snapshot = await pending.future.timeout(_oauthTimeout);
      if (snapshot == null) {
        _applyFailure(
          const SessionError.refused(
            'Sign-in was cancelled.',
            code: SessionErrorCode.oauthCancelled,
          ),
        );
        return;
      }
      _session = snapshot;
      _identity = null;
      await _resolveIdentity();
    } on TimeoutException {
      _applyFailure(
        const SessionError.refused(
          "Sign-in didn't finish. Try again.",
          code: SessionErrorCode.oauthCancelled,
        ),
      );
    } catch (_) {
      // Whatever the platform threw stays here: an OAuth error object can
      // carry the redirect URL and its fragment, and a fragment can carry a
      // token. Nothing from it is logged or re-thrown.
      _applyFailure(
        const SessionError.network(
          "We couldn't start sign-in. Check your connection and try again.",
        ),
      );
    } finally {
      if (identical(_pendingSignIn, pending)) _pendingSignIn = null;
    }
  }

  /// Re-run `auth.whoami` for the session already held.
  ///
  /// The remedy for [SessionStatus.failed] when the cause was the network, and
  /// the remedy for [SessionErrorCode.userUnlinked] once the account has been
  /// set up elsewhere. A no-op when signed out.
  Future<void> retryIdentity() async {
    if (_session == null) {
      _applySignedOut();
      return;
    }
    await _resolveIdentity();
  }

  /// Creates a new social profile only after the person explicitly chooses a
  /// public name. Existing wallet accounts are not claimed or merged here.
  Future<void> completeProfile(String displayName) async {
    final held = _session;
    if (held == null || isBusy || isReady) return;
    final name = displayName.trim();
    if (name.isEmpty ||
        name.length > 60 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      return;
    }
    final epoch = _sessionEpoch;
    _status = SessionStatus.identityPending;
    _error = null;
    _notify();
    try {
      final token = await bffAuthToken();
      if (token == null || epoch != _sessionEpoch || _disposed) return;
      final identity = await _bff.completeProfile(token, displayName: name);
      if (epoch != _sessionEpoch || _disposed) return;
      if (identity.authUserId != held.authUserId) {
        throw const SessionException(
          SessionError.network(
            'The server could not confirm your profile.',
            code: SessionErrorCode.unreadable,
          ),
        );
      }
      _identity = identity;
      _status = SessionStatus.ready;
      _error = null;
      _notify();
    } on SessionException catch (e) {
      if (epoch == _sessionEpoch && !_disposed) _applyFailure(e.error);
    }
  }

  /// Whether identity is switched on for this deployment.
  ///
  /// No credential is sent. Exists so a diagnostics surface can tell "sign-in
  /// is off for this build" apart from "your account is not linked", which
  /// look identical from a failed sign-in.
  Future<SessionIdentityStatus?> checkIdentityStatus() async {
    try {
      return await _bff.identityStatus();
    } on SessionException {
      return null;
    }
  }

  /// End the session. Local state is cleared even if the provider call fails —
  /// a person who asked to sign out is signed out.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Swallowed on purpose: see above.
    } finally {
      _applySignedOut();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    if (_ownsBff) _bff.close();
    super.dispose();
  }

  @override
  String toString() =>
      'ChumbucketSession(${_status.name}, userId: $userId, '
      'hasToken: ${_session != null})';

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _ensureSubscribed() {
    _subscription ??= _auth.authEvents.listen(
      _onAuthEvent,
      // A dead auth stream must not take the app down, and it must not look
      // like a sign-in either.
      onError: (Object _) {},
    );
  }

  void _onAuthEvent(SupabaseAuthEvent event) {
    if (_disposed) return;
    switch (event.kind) {
      case SupabaseAuthEventKind.signedOut:
        _completePending(null);
        _applySignedOut();
      case SupabaseAuthEventKind.signedIn:
      case SupabaseAuthEventKind.initialSession:
      case SupabaseAuthEventKind.tokenRefreshed:
        final snapshot = event.session;
        if (snapshot == null) return;
        final changedPerson = _session?.authUserId != snapshot.authUserId;
        if (changedPerson) _sessionEpoch++;
        _session = snapshot;
        if (changedPerson) _identity = null;
        // A sign-in this object started is driven by `signInWithGoogle`; handing
        // the snapshot over stops the two racing to resolve the same token.
        if (_completePending(snapshot)) return;
        if (_identity == null) {
          unawaited(_resolveIdentity());
        } else {
          // Same person, fresher token. Nothing about identity changed, but the
          // bearer did, so listeners still hear about it.
          _notify();
        }
      case SupabaseAuthEventKind.other:
        return;
    }
  }

  /// Hands [snapshot] to an in-flight [signInWithGoogle]. Returns true when
  /// there was one.
  bool _completePending(SupabaseSessionSnapshot? snapshot) {
    final pending = _pendingSignIn;
    if (pending == null || pending.isCompleted) return false;
    pending.complete(snapshot);
    return true;
  }

  /// One resolution at a time; concurrent callers await the same attempt.
  Future<void> _resolveIdentity() {
    final running = _resolution;
    if (running != null) return running;
    final attempt = _runResolve().whenComplete(() => _resolution = null);
    _resolution = attempt;
    return attempt;
  }

  Future<void> _runResolve() async {
    var session = _session;
    if (session == null) {
      _applySignedOut();
      return;
    }
    final epoch = _sessionEpoch;

    _status = SessionStatus.identityPending;
    _error = null;
    _notify();

    SessionError? failure;
    // Two attempts at most: the second only ever happens after a successful
    // token refresh, so it is not a retry loop against a server that is saying
    // no.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final identity = await _bff.whoami(session!.accessToken);
        if (_disposed || epoch != _sessionEpoch) return;
        _identity = identity;
        _status = SessionStatus.ready;
        _error = null;
        _notify();
        return;
      } on SessionException catch (e) {
        failure = e.error;
        final worthRefreshing =
            attempt == 0 && e.error.code == SessionErrorCode.tokenInvalid;
        if (!worthRefreshing) break;
        final refreshed = await _tryRefresh();
        if (refreshed == null) break;
        session = refreshed;
      }
    }

    if (_disposed || epoch != _sessionEpoch) return;
    _identity = null;
    _error = failure;
    _status = SessionStatus.failed;
    _notify();
  }

  Future<SupabaseSessionSnapshot?> _tryRefresh() async {
    final epoch = _sessionEpoch;
    try {
      final refreshed = await _auth.refreshSession();
      if (_disposed || epoch != _sessionEpoch) return null;
      if (refreshed != null) _session = refreshed;
      return refreshed;
    } catch (_) {
      // A refresh that fails is not a distinct state — the caller is already
      // handling a failure, and the exception can carry the old token.
      return null;
    }
  }

  void _applySignedOut() {
    _sessionEpoch++;
    _session = null;
    _identity = null;
    _status = SessionStatus.signedOut;
    _error = null;
    _notify();
  }

  void _applyFailure(SessionError failure) {
    _identity = null;
    _error = failure;
    _status = SessionStatus.failed;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
