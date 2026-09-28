import 'dart:async';
import 'package:flutter/foundation.dart';

enum AppSignOutState { active, clearing, blocked }

/// Owns the account boundary, not a wallet, identity mapping or navigation route.
/// Every cleanup runs even if another fails. Failed cleanup keeps account UI
/// locked, and retry uses the captured old account rather than a new context.
class AppSignOutController extends ChangeNotifier {
  AppSignOutState _state = AppSignOutState.active;
  AppSignOutState get state => _state;
  int _generation = 0;
  int get generation => _generation;
  Future<void>? _running;
  List<Future<void> Function()> _tasks = const [];
  bool _disposed = false;

  Future<void> signOut(List<Future<void> Function()> tasks) {
    if (_running != null) return _running!;
    if (_state == AppSignOutState.active) _tasks = List.of(tasks);
    _state = AppSignOutState.clearing;
    notifyListeners();
    late final Future<void> attempt;
    attempt = _clear().whenComplete(() {
      if (identical(_running, attempt)) _running = null;
    });
    _running = attempt;
    return attempt;
  }

  Future<void> retry() => signOut(_tasks);

  Future<void> _clear() async {
    final results = await Future.wait(
      _tasks.map((task) async {
        try {
          await task();
          return true;
        } catch (_) {
          // Errors can contain credentials. Neither log nor expose them.
          return false;
        }
      }),
    );
    if (_disposed) return;
    if (results.every((ok) => ok)) {
      _tasks = const [];
      _generation++;
      _state = AppSignOutState.active;
    } else {
      _state = AppSignOutState.blocked;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
