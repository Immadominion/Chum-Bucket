/// Staying signed in across an uninstall/reinstall, the way iOS apps do with
/// iCloud Keychain — on Android, through Google's Block Store.
///
/// ## What is kept, and where
///
/// * **The session.** Every time the Supabase SDK saves a session (sign-in,
///   and every token refresh after it), its *refresh token* — and nothing else
///   from the session — is mirrored into Block Store under [sessionKey], with
///   the account's auth id and the "Last used" sign-in method. The access token
///   is never stored there. On the first launch with no local session (a fresh
///   install), [restoreOnLaunch] hands that refresh token back to the SDK, which
///   exchanges it for a new session exactly as a normal refresh would.
/// * **On-phone wallet keys** (see `EmbeddedWalletVault`), under [walletsKey],
///   keyed by account — but only when Block Store reports the backup would be
///   end-to-end encrypted. A key that controls funds never leaves the phone
///   unencrypted.
///
/// ## When it is cleared
///
/// Explicit sign-out deletes the session entry ([clearSession], a sign-out
/// task). So does the SDK dropping its session for any reason once launch has
/// settled (a refresh token the server refused is dead anyway). Wallet keys
/// are NOT deleted on sign-out: deleting the only copy of a key can destroy the
/// funds it holds. They are keyed by account and only ever used by that
/// account after it signs in again.
///
/// ## Degrading
///
/// No Play services, no Backup, iOS, a test: [BlockStoreUnavailable]. Nothing
/// is backed up, nothing is restored, and the app behaves as it did before —
/// sign in again after a reinstall. Nothing here ever blocks a sign-in.
///
/// A restore can fail if the backed-up refresh token was already used (for
/// example, restored onto a second phone while the first is still signed in);
/// the backup is then deleted and the person signs in normally.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/authentication/session/last_sign_in.dart';

import 'block_store.dart';

/// What adopting a backed-up refresh token came to.
enum SessionAdoption {
  /// The SDK now holds a fresh session for it.
  adopted,

  /// The server refused it (revoked, already used, expired). It is dead.
  rejected,

  /// The server could not be reached. The backup is kept for next launch.
  unreachable,
}

typedef SessionAdopter = Future<SessionAdoption> Function(String refreshToken);

/// How a wallet-key backup went, so the wallet screen can say so honestly.
enum WalletBackupOutcome {
  /// Stored in Block Store, end-to-end encrypted in the person's Google backup.
  backedUp,

  /// Block Store is there, but a cloud copy would not be end-to-end encrypted
  /// (no screen lock). Not stored: the recovery phrase is the only backup.
  notEncrypted,

  /// No Block Store on this device.
  unavailable,

  /// Block Store refused the write.
  failed,
}

/// The one session entry. [toString] is redacted: it carries a credential.
class SessionBackup {
  const SessionBackup({
    required this.refreshToken,
    required this.authUserId,
    this.method,
  });

  final String refreshToken;
  final String authUserId;
  final SignInMethod? method;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'rt': refreshToken,
        'sub': authUserId,
        if (method != null) 'm': method!.wire,
      }),
    ),
  );

  static SessionBackup? decode(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map || value['v'] != 1) return null;
      final token = value['rt'];
      final sub = value['sub'];
      if (token is! String || token.isEmpty || sub is! String || sub.isEmpty) {
        return null;
      }
      return SessionBackup(
        refreshToken: token,
        authUserId: sub,
        method: SignInMethod.fromWire(value['m']),
      );
    } catch (_) {
      return null;
    }
  }

  /// From the JSON the Supabase SDK persists (`Session.toJson()`): its
  /// `refresh_token` and `user.id`, nothing else.
  static SessionBackup? fromPersistedSession(
    String sessionJson, {
    SignInMethod? method,
  }) {
    try {
      final value = jsonDecode(sessionJson);
      if (value is! Map) return null;
      final token = value['refresh_token'];
      final user = value['user'];
      final sub = user is Map ? user['id'] : null;
      if (token is! String || token.isEmpty || sub is! String || sub.isEmpty) {
        return null;
      }
      return SessionBackup(
        refreshToken: token,
        authUserId: sub,
        method: method,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'SessionBackup(authUserId: $authUserId, refreshToken: <redacted>, '
      'method: ${method?.wire})';
}

class SessionContinuity {
  SessionContinuity({
    BlockStorePort store = const MethodChannelBlockStore(),
    required SessionAdopter adopt,
    required Future<String?> Function() localSession,
    LastSignInStore lastSignIn = const PreferencesLastSignInStore(),
    Duration restoreTimeout = const Duration(seconds: 15),
  }) : _store = store,
       _adopt = adopt,
       _localSession = localSession,
       _lastSignIn = lastSignIn,
       _restoreTimeout = restoreTimeout;

  /// Block Store keys: fixed names, never derived from a person.
  static const sessionKey = 'chumbucket.session.v1';
  static const walletsKey = 'chumbucket.wallets.v1';

  /// Block Store's per-entry ceiling.
  static const maxEntryBytes = 4096;

  final BlockStorePort _store;
  final SessionAdopter _adopt;
  final Future<String?> Function() _localSession;
  final LastSignInStore _lastSignIn;
  final Duration _restoreTimeout;

  Future<bool>? _launch;
  bool _settled = false;
  Future<void> _tail = Future.value();
  String? _mirroredToken;
  SignInMethod? _mirroredMethod;

  /// True once [restoreOnLaunch] has finished, whatever it found.
  bool get settled => _settled;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Once per process. True when a backed-up session was adopted — the caller
  /// should then treat the person as signed in. Never throws.
  Future<bool> restoreOnLaunch() => _launch ??= _restore();

  Future<bool> _restore() async {
    try {
      final local = await _localSession();
      if (local != null) {
        // Already signed in here. Make sure the backup is current (an app
        // updated from a build without continuity has none yet).
        await _enqueue(() => _mirror(local));
        return false;
      }
      final backup = SessionBackup.decode(await _store.read(sessionKey));
      if (backup == null) return false;
      final SessionAdoption outcome;
      try {
        outcome = await _adopt(backup.refreshToken).timeout(_restoreTimeout);
      } on TimeoutException {
        return false;
      }
      switch (outcome) {
        case SessionAdoption.adopted:
          final method = backup.method;
          if (method != null) await _lastSignIn.write(method);
          return true;
        case SessionAdoption.rejected:
          await _enqueue(_deleteSessionQuietly);
          return false;
        case SessionAdoption.unreachable:
          return false;
      }
    } catch (_) {
      // Unavailable, unreadable, or a failure: sign in as usual.
      return false;
    } finally {
      _settled = true;
    }
  }

  /// `AppSessionPersistence.onPersisted`: the SDK just saved [sessionJson].
  void sessionPersisted(String sessionJson) {
    unawaited(_enqueue(() => _mirror(sessionJson)).catchError((Object _) {}));
  }

  /// `AppSessionPersistence.onRemoved`: the SDK dropped its session. Ignored
  /// until launch has settled, so nothing can delete the backup before it has
  /// had its chance to restore.
  void sessionRemoved() {
    if (!_settled) return;
    unawaited(_enqueue(_deleteSessionQuietly).catchError((Object _) {}));
  }

  /// Explicit sign-out. Throws only when Block Store is there and refused the
  /// delete, so the sign-out can be retried rather than leave a session behind.
  Future<void> clearSession() => _enqueue(() async {
    _mirroredToken = null;
    _mirroredMethod = null;
    try {
      await _store.delete(sessionKey);
    } on BlockStoreUnavailable {
      // Nothing can have been stored.
    }
  });

  Future<void> _deleteSessionQuietly() async {
    _mirroredToken = null;
    _mirroredMethod = null;
    try {
      await _store.delete(sessionKey);
    } catch (_) {}
  }

  Future<void> _mirror(String sessionJson) async {
    final method = await _lastSignIn.read();
    final backup = SessionBackup.fromPersistedSession(
      sessionJson,
      method: method,
    );
    if (backup == null) return;
    if (backup.refreshToken == _mirroredToken && method == _mirroredMethod) {
      return;
    }
    try {
      final availability = await _store.availability();
      if (!availability.available) return;
      final bytes = backup.encode();
      if (bytes.length > maxEntryBytes) return;
      await _store.write(
        sessionKey,
        bytes,
        backupToCloud: availability.endToEndEncrypted,
      );
      _mirroredToken = backup.refreshToken;
      _mirroredMethod = method;
    } catch (_) {
      // A missed mirror only means a reinstall asks for sign-in again.
    }
  }

  // ---------------------------------------------------------------------------
  // On-phone wallet keys
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _readWallets() async {
    final bytes = await _store.read(walletsKey);
    if (bytes == null || bytes.isEmpty) return {};
    try {
      final value = jsonDecode(utf8.decode(bytes));
      final wallets = value is Map && value['v'] == 1 ? value['w'] : null;
      if (wallets is! Map) return {};
      return {
        for (final entry in wallets.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Uint8List _encodeWallets(Map<String, String> wallets) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'w': wallets})));

  /// Backs up the on-phone wallet [secret] for [userId] — only when the
  /// backup would be end-to-end encrypted.
  Future<WalletBackupOutcome> backupWalletSecret(
    String userId,
    String secret,
  ) => _enqueue(() async {
    try {
      final availability = await _store.availability();
      if (!availability.available) return WalletBackupOutcome.unavailable;
      if (!availability.endToEndEncrypted) {
        return WalletBackupOutcome.notEncrypted;
      }
      final wallets = await _readWallets();
      if (wallets[userId] == secret) return WalletBackupOutcome.backedUp;
      wallets[userId] = secret;
      final bytes = _encodeWallets(wallets);
      if (bytes.length > maxEntryBytes) return WalletBackupOutcome.failed;
      await _store.write(walletsKey, bytes, backupToCloud: true);
      return WalletBackupOutcome.backedUp;
    } on BlockStoreUnavailable {
      return WalletBackupOutcome.unavailable;
    } catch (_) {
      return WalletBackupOutcome.failed;
    }
  });

  /// The backed-up wallet secret for [userId], or null.
  Future<String?> restoreWalletSecret(String userId) => _enqueue(() async {
    try {
      return (await _readWallets())[userId];
    } catch (_) {
      return null;
    }
  });
}
