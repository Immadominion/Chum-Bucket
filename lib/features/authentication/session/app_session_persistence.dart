import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the SDK's existing storage key. No account migration or bulk preference
/// deletion. Serializing writes with removal prevents a delayed save undoing
/// logout; writes stay blocked until a new interactive sign-in begins.
class AppSessionPersistence extends LocalStorage {
  AppSessionPersistence(this.delegate);
  final LocalStorage delegate;
  static AppSessionPersistence? current;

  /// Supabase is process-wide, unlike the disposed account tree. A browser
  /// callback after logout must be removed from its memory as well as disk.
  Future<void> Function()? discardLateAuthSession;
  bool _acceptWrites = true;
  bool _accountLinkPending = false;
  String? _pendingAccountSession;
  int _epoch = 0;
  bool get isLocked => !_acceptWrites;
  Future<void> _tail = Future.value();

  factory AppSessionPersistence.forProject(String url) => AppSessionPersistence(
    _CheckedPreferences(
      'sb-${Uri.parse(url).host.split('.').first}-auth-token',
    ),
  );

  Future<void> _enqueue(Future<void> Function() operation) {
    final pending = _tail.then((_) => operation());
    _tail = pending.catchError((Object _) {});
    return pending;
  }

  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<bool> hasAccessToken() async {
    final epoch = _epoch;
    if (!_acceptWrites) return false;
    final found = await delegate.hasAccessToken();
    return _acceptWrites && epoch == _epoch && found;
  }

  @override
  Future<String?> accessToken() async {
    final epoch = _epoch;
    if (!_acceptWrites) return null;
    final value = await delegate.accessToken();
    return _acceptWrites && epoch == _epoch ? value : null;
  }

  @override
  Future<void> persistSession(String value) {
    if (!_acceptWrites) return _discardLateSession();
    final epoch = _epoch;
    return _enqueue(() async {
      if (_acceptWrites && epoch == _epoch) {
        if (_accountLinkPending) {
          // OAuth candidates remain only in memory until the old canonical
          // person has been proven. Killing the app cannot restore a candidate.
          _pendingAccountSession = value;
        } else {
          await delegate.persistSession(value);
        }
      }
    });
  }

  Future<void> _discardLateSession() async {
    try {
      await discardLateAuthSession?.call();
    } catch (_) {
      // Persistence remains locked even if provider revocation is unavailable.
      // Never expose the SDK's error or the rejected credential.
    }
  }

  @override
  Future<void> removePersistedSession() =>
      _enqueue(delegate.removePersistedSession);

  Future<void> clearForSignOut() {
    _epoch++;
    _acceptWrites = false;
    _accountLinkPending = false;
    _pendingAccountSession = null;
    return removePersistedSession();
  }

  void beginInteractiveSignIn() {
    _epoch++;
    _acceptWrites = true;
  }

  /// Clear only this project's old Google credential. Wallet/profile/history
  /// are untouched. Must finish before opening the browser.
  Future<void> beginAccountLink() {
    _epoch++;
    _acceptWrites = true;
    _accountLinkPending = true;
    _pendingAccountSession = null;
    return removePersistedSession();
  }

  /// Called after claim AND whoami agree on the expected existing person.
  /// An SDK session for another subject, or a missing SDK save, fails closed.
  Future<void> completeAccountLink(String authUserId) {
    final epoch = _epoch;
    return _enqueue(() async {
      if (!_acceptWrites || epoch != _epoch || !_accountLinkPending) {
        throw StateError('Account linking was cancelled');
      }
      final value = _pendingAccountSession;
      try {
        final parsed = value == null ? null : jsonDecode(value);
        if (parsed is! Map ||
            parsed['user'] is! Map ||
            (parsed['user'] as Map)['id'] != authUserId) {
          throw const FormatException();
        }
      } catch (_) {
        throw StateError('Account session could not be confirmed');
      }
      await delegate.persistSession(value!);
      if (_acceptWrites && epoch == _epoch) {
        _accountLinkPending = false;
        _pendingAccountSession = null;
      }
    });
  }
}

class _CheckedPreferences extends LocalStorage {
  _CheckedPreferences(this.key);
  final String key;
  late SharedPreferences _prefs;
  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  Future<bool> hasAccessToken() async => _prefs.containsKey(key);
  @override
  Future<String?> accessToken() async => _prefs.getString(key);
  @override
  Future<void> persistSession(String value) async {
    if (!await _prefs.setString(key, value)) {
      throw StateError('Session storage failed');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    if (!await _prefs.remove(key)) throw StateError('Session removal failed');
  }
}
