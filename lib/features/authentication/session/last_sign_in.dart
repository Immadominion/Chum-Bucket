/// Which way a person last got into Chumbucket — wallet, Google or X — so the
/// front door can mark that option "Last used", the way web sign-in pages do.
///
/// It is a convenience, not a credential: it names a sign-in method and
/// nothing else (no account, address, email or token). It survives restarts in
/// SharedPreferences, and a reinstall through the Block Store session backup
/// (`SessionContinuity`), which carries it alongside the session.
library;

import 'package:shared_preferences/shared_preferences.dart';

enum SignInMethod {
  wallet,
  google,
  x;

  /// The stored spelling. Never renamed: an old value must keep reading back.
  String get wire => name;

  static SignInMethod? fromWire(Object? value) => switch (value) {
    'wallet' => SignInMethod.wallet,
    'google' => SignInMethod.google,
    'x' => SignInMethod.x,
    _ => null,
  };
}

abstract interface class LastSignInStore {
  Future<SignInMethod?> read();
  Future<void> write(SignInMethod method);
}

/// The device store. Failures are swallowed: a missing badge is the worst case.
class PreferencesLastSignInStore implements LastSignInStore {
  const PreferencesLastSignInStore();

  static const key = 'chumbucket_last_sign_in_method_v1';

  @override
  Future<SignInMethod?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SignInMethod.fromWire(prefs.getString(key));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SignInMethod method) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, method.wire);
    } catch (_) {
      // Never blocks a sign-in.
    }
  }
}

/// In-memory, for tests and previews.
class MemoryLastSignInStore implements LastSignInStore {
  MemoryLastSignInStore([this.value]);
  SignInMethod? value;
  int writes = 0;

  @override
  Future<SignInMethod?> read() async => value;

  @override
  Future<void> write(SignInMethod method) async {
    writes++;
    value = method;
  }
}
