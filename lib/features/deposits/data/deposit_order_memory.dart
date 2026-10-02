import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last unfinished payment per account, so closing the sheet
/// mid-checkout never loses track of money in flight. Stores only Crossmint's
/// order id and when it started — no amount, address, email or secret.
abstract interface class DepositOrderMemory {
  Future<String?> pending(String accountId);
  Future<void> remember(String accountId, String orderId);
  Future<void> forget(String accountId);
}

class SharedPrefsDepositOrderMemory implements DepositOrderMemory {
  const SharedPrefsDepositOrderMemory({this.maxAge = const Duration(days: 2)});

  /// Crossmint quotes expire within the hour; two days covers identity review.
  final Duration maxAge;

  static String _key(String accountId) => 'deposits.pending.$accountId';

  @override
  Future<String?> pending(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(accountId));
      if (raw == null) return null;
      final parts = raw.split('|');
      if (parts.length != 2) return null;
      final at = int.tryParse(parts[1]);
      if (at == null ||
          DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds ||
          !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(parts[0])) {
        await prefs.remove(_key(accountId));
        return null;
      }
      return parts[0];
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remember(String accountId, String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(accountId),
        '$orderId|${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {
      /* Best effort: losing this only loses the resume shortcut. */
    }
  }

  @override
  Future<void> forget(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(accountId));
    } catch (_) {
      /* Best effort. */
    }
  }
}

class InMemoryDepositOrderMemory implements DepositOrderMemory {
  final Map<String, String> _orders = {};

  @override
  Future<String?> pending(String accountId) async => _orders[accountId];

  @override
  Future<void> remember(String accountId, String orderId) async =>
      _orders[accountId] = orderId;

  @override
  Future<void> forget(String accountId) async => _orders.remove(accountId);
}
