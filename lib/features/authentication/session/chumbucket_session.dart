/// Optional Supabase credential for the call/receipt surface. The existing
/// app entry remains MWA. Settings links Google to that SAME canonical person
/// through a server-verified ownership proof, never through profile creation.
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

import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'app_session_persistence.dart';
import 'existing_account_proof.dart';

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
    LastSignInStore lastSignIn = const PreferencesLastSignInStore(),
  }) : _auth = auth ?? const SupabaseFlutterAuthPort(),
       _bff = bff ?? SessionBffClient(),
       _ownsBff = bff == null,
       _redirectTo = redirectTo,
       _oauthTimeout = oauthTimeout,
       _lastSignIn = lastSignIn;

  final SupabaseAuthPort _auth;
  final LastSignInStore _lastSignIn;
  final SessionBffClient _bff;
  final bool _ownsBff;
  final String _redirectTo;
  final Duration _oauthTimeout;

  StreamSubscription<SupabaseAuthEvent>? _subscription;
  Completer<SupabaseSessionSnapshot?>? _pendingSignIn;
  Future<void>? _resolution;
  int? _resolutionEpoch;
  Future<void>? _signingOut;
  bool _acceptAuthEvents = true;
  bool _disposed = false;
  int _sessionEpoch = 0;
  bool _linkingExistingAccount = false;
  bool _existingLinkOAuthStarted = false;
  bool _existingLinkInvalidated = false;
  SessionError? _existingLinkError;

  bool get isLinkingExistingAccount => _linkingExistingAccount;
  SessionError? get existingLinkError => _existingLinkError;

  SupabaseSessionSnapshot? _session;
  SessionIdentity? _identity;
  SessionStatus _status = SessionStatus.signedOut;
  SessionError? _error;

  // ---------------------------------------------------------------------------
  // What a screen reads
  // ---------------------------------------------------------------------------

  SessionStatus get status => _status;

  /// The account's own @username (lowercase, no `@`), or null — either the
  /// account has none ([needsHandleClaim]) or it is not known yet.
  String? get handle => _identity?.handle;

  /// Signed in to an account the server says has no @username yet: an account
  /// made before usernames, or a wallet profile carried over to wallet sign-in.
  /// The person is asked, once, to claim one.
  bool get needsHandleClaim => isReady && _identity!.needsHandle;

  bool _claimingHandle = false;

  /// True while [claimUsername] is in flight.
  bool get isClaimingHandle => _claimingHandle;

  SignInMethod? _lastMethod;
  bool _lastMethodLoaded = false;
  SignInMethod? _methodInFlight;

  /// How this device last got in (wallet, Google or X), for the front door's
  /// "Last used" badge. Null until [loadLastSignInMethod] has read it, or when
  /// nobody has signed in here.
  SignInMethod? get lastSignInMethod => _lastMethod;

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

  bool _needsProfile = false;

  /// Whether the current session came from a wallet signature (as opposed to
  /// Google or X) — signed here, or restored from storage or a backup.
  bool get isWalletSession =>
      _session != null && (_walletSession || _session!.solanaWallet != null);
  bool _walletSession = false;

  /// The wallet this account signed in with, when it signed in with one: the
  /// address Supabase Auth verified. After a reinstall the session comes back
  /// but the wallet app's authorization does not; this says which wallet to
  /// reconnect. Null for Google and X sessions.
  String? get signInWallet => _session?.solanaWallet;

  /// Signed in (wallet, Google or X), but no Chumbucket account yet: the
  /// person claims a @username next. Survives a refused claim ("taken"), so
  /// the form stays up with the reason beside it.
  bool get needsUsername => _needsProfile && _session != null && !isReady;

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
    if (_linkingExistingAccount) return null;
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
    if (_disposed || !_acceptAuthEvents || _linkingExistingAccount) return;
    _ensureSubscribed();
    final existing = _auth.currentSession;
    if (existing == null) {
      _applySignedOut();
      return;
    }
    if (_session?.authUserId != existing.authUserId) {
      _sessionEpoch++;
      _identity = null;
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
  Future<void> signInWithGoogle() => _signInWithOAuth(
    () => _auth.startGoogleSignIn(redirectTo: _redirectTo),
    SignInMethod.google,
  );

  /// The same flow with X's consent screen (Supabase's "Twitter (X)").
  Future<void> signInWithX() => _signInWithOAuth(
    () => _auth.startXSignIn(redirectTo: _redirectTo),
    SignInMethod.x,
  );

  /// Sign in with a Solana wallet: it signs one message (no transaction),
  /// Supabase Auth verifies it and issues a session, and the canonical person
  /// is resolved exactly as for Google. Never throws; failures land in [error].
  Future<void> signInWithWallet(SolanaSignInWallet wallet) async {
    if (_disposed ||
        _linkingExistingAccount ||
        _signingOut != null ||
        _status == SessionStatus.signingIn) {
      return;
    }
    _acceptAuthEvents = true;
    _ensureSubscribed();
    final pending = Completer<SupabaseSessionSnapshot?>();
    _pendingSignIn = pending;
    _methodInFlight = SignInMethod.wallet;
    _status = SessionStatus.signingIn;
    _error = null;
    _notify();
    try {
      debugPrint('SolanaSignIn: connecting wallet');
      final address = await wallet.connect();
      debugPrint('SolanaSignIn: wallet connected, requesting signature');
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      final message =
          wallet is _PresignedWallet
              ? wallet.signedMessage
              : solanaSignInMessage(address: address, issuedAt: DateTime.now());
      final signature = await wallet.sign(message);
      debugPrint('SolanaSignIn: signed, exchanging with Supabase');
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      final snapshot = await _auth.signInWithSolana(
        message: message,
        signature: signature,
      );
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      // The SDK also announces the new session on the auth stream; whichever
      // arrives first completes the same pending sign-in.
      _completePending(snapshot);
      final adopted = await pending.future;
      if (_disposed || adopted == null) return;
      if (_session?.authUserId != adopted.authUserId) _sessionEpoch++;
      _session = adopted;
      _walletSession = true;
      _identity = null;
      await _resolveIdentity();
    } on SessionException catch (e) {
      debugPrint('SolanaSignIn: refused (${e.error.code})');
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      _applyFailure(e.error);
    } on SolanaSignInException catch (e) {
      debugPrint('SolanaSignIn: Supabase step failed (${e.kind})');
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      _applyFailure(switch (e.kind) {
        SolanaSignInException.disabled => const SessionError.refused(
          'Wallet sign-in isn’t switched on yet. Your wallet and profile are '
          'unchanged.',
          code: 'WALLET_SIGN_IN_DISABLED',
        ),
        SolanaSignInException.network => const SessionError.network(
          'We couldn’t reach sign-in. Check your connection and try again.',
        ),
        _ => const SessionError.refused(
          'That wallet signature wasn’t accepted. Try again.',
          code: 'WALLET_SIGN_IN_REFUSED',
        ),
      });
    } catch (error) {
      debugPrint('SolanaSignIn: failed (${error.runtimeType})');
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      _applyFailure(
        const SessionError.network('We couldn’t finish signing in. Try again.'),
      );
    } finally {
      if (identical(_pendingSignIn, pending)) _pendingSignIn = null;
    }
  }

  /// Finishes a wallet sign-in whose message was already signed (during
  /// Connect Wallet). Same exchange and resolution as [signInWithWallet].
  Future<void> signInWithSignedMessage(String message, String signature) =>
      signInWithWallet(_PresignedWallet(message, signature));

  Set<String>? _providers;

  /// The social sign-ins switched on for this project ("google",
  /// "twitter"), read once from Supabase's public settings. Null until read.
  Set<String>? get enabledProviders => _providers;

  Future<void> loadEnabledProviders() async {
    if (_providers != null) return;
    final providers = await _auth.enabledProviders();
    if (_disposed) return;
    _providers = providers;
    _notify();
  }

  /// Reads the remembered sign-in method once.
  Future<void> loadLastSignInMethod() async {
    if (_lastMethodLoaded) return;
    _lastMethodLoaded = true;
    final method = await _lastSignIn.read();
    if (_disposed || method == null || _lastMethod != null) return;
    _lastMethod = method;
    _notify();
  }

  /// Remembers [method] as the last one that got this device in. Called by
  /// the session itself when an interactive sign-in reaches an account, and by
  /// the wallet door when a wallet connects without an account sign-in.
  Future<void> rememberSignInMethod(SignInMethod method) async {
    _lastMethod = method;
    _lastMethodLoaded = true;
    _notify();
    await _lastSignIn.write(method);
  }

  /// The account claims [handle] as its @username. Only while it has none;
  /// the server re-checks everything. Returns null on success, or why not.
  /// The session stays signed in either way.
  Future<SessionError?> claimUsername(String handle) async {
    final held = _identity;
    if (_disposed || !isReady || held == null || _claimingHandle) {
      return const SessionError.refused(
        'Sign in to claim a username.',
        code: SessionErrorCode.tokenInvalid,
      );
    }
    final epoch = _sessionEpoch;
    _claimingHandle = true;
    _notify();
    String? token;
    try {
      token = await bffAuthToken();
      if (token == null || epoch != _sessionEpoch || _disposed) {
        return const SessionError.refused(
          'Sign in to claim a username.',
          code: SessionErrorCode.tokenInvalid,
        );
      }
      final claimed = await _bff.claimUsername(token, handle: handle);
      if (epoch != _sessionEpoch || _disposed) {
        return const SessionError.refused(
          'Your account changed. Nothing was claimed here.',
          code: 'ACCOUNT_CHANGED',
        );
      }
      if (claimed.userId != held.userId) {
        return const SessionError.network(
          'The server could not confirm your username.',
          code: SessionErrorCode.unreadable,
        );
      }
      _identity = held.withHandle(claimed.handle!);
      return null;
    } on SessionException catch (e) {
      if (e.error.code == 'HANDLE_ALREADY_SET' && token != null) {
        // Claimed since this session read it (another phone): learn the
        // stored one, so the prompt and Profile's row stop asking.
        final stored = await _storedHandle(token, held, epoch);
        if (stored != null) {
          return SessionError.refused(
            'Your account already has a username: @$stored.',
            code: 'HANDLE_ALREADY_SET',
          );
        }
      }
      return e.error;
    } finally {
      _claimingHandle = false;
      _notify();
    }
  }

  /// Re-reads the account's stored @username and adopts it. Null when it
  /// could not be read, or the account changed meanwhile.
  Future<String?> _storedHandle(
    String token,
    SessionIdentity held,
    int epoch,
  ) async {
    try {
      final fresh = await _bff.whoami(token);
      final handle = fresh.handle;
      if (_disposed ||
          epoch != _sessionEpoch ||
          fresh.userId != held.userId ||
          handle == null) {
        return null;
      }
      _identity = held.withHandle(handle);
      return handle;
    } catch (_) {
      return null;
    }
  }

  /// Whether a @username can be claimed. Null when the check could not run.
  Future<UsernameStatus?> usernameStatus(String handle) async {
    try {
      return await _bff.usernameStatus(handle);
    } on SessionException {
      return null;
    }
  }

  Future<void> _signInWithOAuth(
    Future<bool> Function() start,
    SignInMethod method,
  ) async {
    _walletSession = false;
    if (_disposed ||
        _linkingExistingAccount ||
        _signingOut != null ||
        _status == SessionStatus.signingIn) {
      return;
    }
    _acceptAuthEvents = true;
    _ensureSubscribed();

    final pending = Completer<SupabaseSessionSnapshot?>();
    _pendingSignIn = pending;
    _methodInFlight = method;
    _status = SessionStatus.signingIn;
    _error = null;
    _notify();

    try {
      final launched = await start();
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      if (!launched) {
        _applyFailure(
          const SessionError.refused(
            "We couldn't open the sign-in page.",
            code: SessionErrorCode.oauthCancelled,
          ),
        );
        return;
      }
      final snapshot = await pending.future.timeout(_oauthTimeout);
      if (_disposed || !identical(_pendingSignIn, pending)) return;
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
      if (_disposed || !identical(_pendingSignIn, pending)) return;
      _applyFailure(
        const SessionError.refused(
          "Sign-in didn't finish. Try again.",
          code: SessionErrorCode.oauthCancelled,
        ),
      );
    } catch (_) {
      if (_disposed || !identical(_pendingSignIn, pending)) return;
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
    if (_linkingExistingAccount) return;
    if (_session == null) {
      _applySignedOut();
      return;
    }
    await _resolveIdentity();
  }

  /// Creates a new social profile only after the person explicitly chooses a
  /// public name. Existing wallet accounts are not claimed or merged here.
  Future<void> completeProfile(String displayName, {String? handle}) async {
    if (_linkingExistingAccount) return;
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
      final identity = await _bff.completeProfile(
        token,
        displayName: name,
        handle: handle,
      );
      if (epoch != _sessionEpoch || _disposed) return;
      if (identity.authUserId != held.authUserId) {
        throw const SessionException(
          SessionError.network(
            'The server could not confirm your profile.',
            code: SessionErrorCode.unreadable,
          ),
        );
      }
      // A new account's handle is the one just claimed.
      _identity =
          handle != null && identity.handle == null
              ? identity.withHandle(handle.trim().toLowerCase())
              : identity;
      _needsProfile = false;
      _status = SessionStatus.ready;
      _error = null;
      _recordSignInMethod();
      _notify();
    } on SessionException catch (e) {
      if (epoch == _sessionEpoch && !_disposed) _applyFailure(e.error);
    }
  }

  /// An interactive sign-in reached an account: remember how, for "Last used".
  void _recordSignInMethod() {
    final method = _methodInFlight;
    if (method == null) return;
    _methodInFlight = null;
    _lastMethod = method;
    _lastMethodLoaded = true;
    unawaited(_lastSignIn.write(method));
  }

  SessionIdentityStatus? _identityStatus;
  Future<void>? _identityStatusLoad;

  /// Whether an existing (wallet) profile can be linked to Google right now:
  /// null until [loadIdentityStatus] has answered, false while the server's
  /// existing-account claims are switched off. Lets an entry point say so
  /// instead of offering a button that can only be refused.
  bool? get existingAccountClaimsOpen =>
      _identityStatus == null
          ? null
          : _identityStatus!.enabled &&
              _identityStatus!.existingAccountClaimsEnabled;

  /// Reads `auth.identityStatus` once (public, no credential) and keeps it.
  /// Concurrent callers share one request; a failure leaves it unknown and the
  /// next caller retries. The link flow still re-checks before it acts.
  Future<void> loadIdentityStatus({bool force = false}) {
    if (!force && _identityStatus != null) return Future.value();
    return _identityStatusLoad ??= () async {
      try {
        final status = await _bff.identityStatus();
        if (_disposed) return;
        _identityStatus = status;
        _notify();
      } on SessionException {
        // Unknown stays unknown; nothing is assumed either way.
      } finally {
        _identityStatusLoad = null;
      }
    }();
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

  /// Settings-only account continuity flow. Never creates a profile, changes
  /// the connected wallet, or publishes a different Google's canonical id.
  Future<bool> linkExistingAccount(ExistingAccountWallet wallet) async {
    if (_disposed || _signingOut != null || isBusy || _linkingExistingAccount) {
      return false;
    }
    _linkingExistingAccount = true;
    _existingLinkInvalidated = false;
    _existingLinkError = null;
    final epoch = ++_sessionEpoch;
    final address = wallet.address;
    final network = wallet.network;
    final persistence = AppSessionPersistence.current;
    void checkCurrent() {
      if (_disposed ||
          epoch != _sessionEpoch ||
          _existingLinkInvalidated ||
          !wallet.isCurrent ||
          wallet.address != address ||
          wallet.network != network) {
        throw accountChangedError;
      }
    }

    _notify();
    var openedOAuth = false;
    try {
      checkCurrent();
      final capability = await _bff.identityStatus();
      checkCurrent();
      if (!capability.enabled || !capability.existingAccountClaimsEnabled) {
        throw SessionException(
          sessionErrorForTrpcError(
            statusCode: 412,
            message: 'ACCOUNT_CLAIMS_DISABLED',
          ),
        );
      }
      if (capability.proofVersion != 1 ||
          capability.network != network ||
          !capability.allowedDomains.contains(accountClaimDomain) ||
          !capability.allowedUris.contains(accountClaimUri)) {
        throw accountClaimUnreadable;
      }
      final expectedUserId = await wallet.expectedUserId();
      checkCurrent();
      if (expectedUserId == null || expectedUserId.isEmpty) {
        throw SessionException(
          sessionErrorForTrpcError(
            statusCode: 412,
            message: 'ACCOUNT_CLAIM_UNAVAILABLE',
          ),
        );
      }

      // Do not let the general OAuth listener resolve an unrelated Google
      // account into the Calls viewer while this wallet's claim is pending.
      _acceptAuthEvents = true;
      _ensureSubscribed();
      _identity = null;
      _session = null;
      _status = SessionStatus.signingIn;
      _error = null;
      final pending = Completer<SupabaseSessionSnapshot?>();
      _pendingSignIn = pending;
      openedOAuth = true;
      await persistence?.beginAccountLink();
      checkCurrent();
      _existingLinkOAuthStarted = true;
      _notify();
      final launched = await _auth.startGoogleSignIn(redirectTo: _redirectTo);
      checkCurrent();
      if (!launched) {
        throw const SessionException(
          SessionError.refused(
            'Google sign-in did not open. Try again.',
            code: SessionErrorCode.oauthCancelled,
          ),
        );
      }
      final candidate = await pending.future.timeout(_oauthTimeout);
      checkCurrent();
      if (candidate == null) throw accountChangedError;
      _status = SessionStatus.identityPending;
      _notify();

      // Stop a known conflict before asking the wallet to sign anything.
      try {
        final existing = await _bff.whoami(candidate.accessToken);
        checkCurrent();
        _requireExistingPerson(existing, expectedUserId, candidate.authUserId);
      } on SessionException catch (e) {
        if (!e.error.isUnlinked) rethrow;
      }
      checkCurrent();
      final proof = await _bff.requestExistingAccountProof(
        candidate.accessToken,
        address: address,
        network: network,
      );
      checkCurrent();
      proof.checkFresh();
      final signature = await wallet
          .signClaim(proof.message)
          .timeout(_oauthTimeout);
      checkCurrent();
      proof.checkFresh();
      final claimed = await _bff.claimExistingAccount(
        candidate.accessToken,
        address: address,
        proof: proof,
        signature: signature,
      );
      checkCurrent();
      _requireExistingPerson(claimed, expectedUserId, candidate.authUserId);
      final confirmed = await _bff.whoami(candidate.accessToken);
      checkCurrent();
      _requireExistingPerson(confirmed, expectedUserId, candidate.authUserId);
      await persistence?.completeAccountLink(candidate.authUserId);
      checkCurrent();
      _identity = confirmed;
      _status = SessionStatus.ready;
      _error = null;
      return true;
    } catch (error) {
      if (!_disposed && epoch == _sessionEpoch) {
        _existingLinkError =
            error is SessionException
                ? error.error
                : const SessionError.refused(
                  'Linking did not finish. Reopen Settings to try again.',
                  code: 'ACCOUNT_LINK_CANCELLED',
                );
      }
      // A rejected/cancelled candidate must not be restored into this wallet's
      // account tree on a later token refresh or browser callback. This clears
      // Google only, never the old wallet/profile/history. Logout owns cleanup
      // if it already changed the epoch (do not clear a newer account).
      if (openedOAuth && !_disposed && epoch == _sessionEpoch) {
        _acceptAuthEvents = false;
        _session = null;
        _identity = null;
        _status = SessionStatus.signedOut;
        _error = null;
        try {
          await persistence?.clearForSignOut();
          if (!_disposed && epoch == _sessionEpoch) await _endAuthSession();
        } catch (_) {
          // Storage errors never expose a credential; the listener stays locked.
        }
      }
      return false;
    } finally {
      _completePending(null);
      _pendingSignIn = null;
      _existingLinkOAuthStarted = false;
      _linkingExistingAccount = false;
      _notify();
    }
  }

  static void _requireExistingPerson(
    SessionIdentity identity,
    String person,
    String subject,
  ) {
    if (identity.userId != person || identity.authUserId != subject) {
      throw SessionException(
        sessionErrorForTrpcError(
          statusCode: 409,
          message: 'ACCOUNT_CLAIM_CONFLICT',
        ),
      );
    }
  }

  /// The Settings sheet was dismissed. Invalidate synchronously; its pending
  /// operation performs Google cleanup and cannot submit a late wallet reply.
  void cancelExistingAccountLink() {
    if (!_linkingExistingAccount) return;
    _existingLinkInvalidated = true;
    _acceptAuthEvents = false;
    _completePending(null);
  }

  /// End the session. Local state is cleared even if the provider call fails —
  /// a person who asked to sign out is signed out.
  Future<void> signOut() {
    final running = _signingOut;
    if (running != null) return running;
    // Hide identity immediately, not after a network or browser round trip.
    _acceptAuthEvents = false;
    _completePending(null);
    _pendingSignIn = null;
    _applySignedOut();
    late final Future<void> attempt;
    attempt = _endAuthSession().whenComplete(() {
      if (identical(_signingOut, attempt)) _signingOut = null;
    });
    _signingOut = attempt;
    return attempt;
  }

  Future<void> _endAuthSession() async {
    try {
      await _auth.signOut().timeout(const Duration(seconds: 10));
    } catch (_) {
      // The local identity stays cleared; no provider error/credential escapes.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _completePending(null);
    _pendingSignIn = null;
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
    if (_disposed || !_acceptAuthEvents) return;
    if (_linkingExistingAccount) {
      if (!_existingLinkOAuthStarted) return;
      if (event.kind == SupabaseAuthEventKind.signedOut) {
        _completePending(null);
        _applySignedOut();
        _acceptAuthEvents = false;
      } else if (event.kind == SupabaseAuthEventKind.signedIn ||
          event.kind == SupabaseAuthEventKind.tokenRefreshed) {
        final incoming = event.session;
        if (incoming == null) return;
        final held = _session;
        if (held != null && held.authUserId != incoming.authUserId) {
          // Includes A -> B -> A: the original operation never becomes current again.
          _completePending(null);
          _existingLinkInvalidated = true;
          _session = null;
          _identity = null;
          _acceptAuthEvents = false;
          return;
        }
        if (held == null && event.kind != SupabaseAuthEventKind.signedIn) {
          return;
        }
        _session = incoming;
        _completePending(incoming);
      }
      return;
    }
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
    if (running != null && _resolutionEpoch == _sessionEpoch) return running;
    final epoch = _sessionEpoch;
    late final Future<void> attempt;
    attempt = _runResolve().whenComplete(() {
      if (identical(_resolution, attempt)) {
        _resolution = null;
        _resolutionEpoch = null;
      }
    });
    _resolution = attempt;
    _resolutionEpoch = epoch;
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
        if (identity.authUserId != session.authUserId) {
          throw const SessionException(
            SessionError.network(
              'The server could not confirm your profile.',
              code: SessionErrorCode.unreadable,
            ),
          );
        }
        _identity = identity;
        _needsProfile = false;
        _status = SessionStatus.ready;
        _error = null;
        _recordSignInMethod();
        _notify();
        return;
      } on SessionException catch (e) {
        if (_disposed || epoch != _sessionEpoch) return;
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
    _needsProfile = failure?.isUnlinked == true;
    _error = failure;
    _status = SessionStatus.failed;
    _notify();
  }

  Future<SupabaseSessionSnapshot?> _tryRefresh() async {
    final epoch = _sessionEpoch;
    final authUserId = _session?.authUserId;
    try {
      final refreshed = await _auth.refreshSession();
      if (_disposed || epoch != _sessionEpoch) return null;
      if (refreshed != null && refreshed.authUserId != authUserId) return null;
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
    _needsProfile = false;
    _methodInFlight = null;
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

/// A wallet whose one signature is already in hand.
class _PresignedWallet implements SolanaSignInWallet {
  _PresignedWallet(this._message, this._signature);
  final String _message;
  final String _signature;

  @override
  Future<String> connect() async {
    final address = _message.split('\n').elementAtOrNull(1) ?? '';
    return address;
  }

  @override
  Future<String> sign(String message) async => _signature;

  /// The message that was signed, used verbatim.
  String get signedMessage => _message;
}
