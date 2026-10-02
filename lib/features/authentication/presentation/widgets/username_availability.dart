/// Live "is this @username free?" for a text field: format first, then a
/// debounced, credential-free `auth.usernameStatus`. The server decides at
/// claim time; this only saves a round trip and says why up front.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';

class UsernameAvailability extends ChangeNotifier {
  UsernameAvailability(
    this._check, {
    this.debounce = const Duration(milliseconds: 350),
  });

  /// `handle_status_v1`'s format: 3–20 of a-z, 0-9 and underscore.
  static final format = RegExp(r'^[a-z0-9_]{3,20}$');

  final Future<UsernameStatus?> Function(String handle) _check;
  final Duration debounce;

  String _handle = '';
  String _checked = '';
  UsernameStatus? _status;
  bool _checking = false;
  Timer? _timer;
  bool _disposed = false;

  /// What was typed, trimmed and lowercased.
  String get handle => _handle;
  bool get formatOk => format.hasMatch(_handle);

  /// Checked and refused (taken or reserved) — the claim button stays off.
  bool get unavailable =>
      _checked == _handle &&
      (_status == UsernameStatus.taken || _status == UsernameStatus.reserved);

  /// The line under the field, and its colour. Null when there is nothing to
  /// say yet.
  (String?, Color?) get hint {
    if (_handle.isEmpty) return (null, null);
    if (!formatOk) {
      return ('3–20 letters, numbers or _', AppColors.textSecondary);
    }
    final status = _checked == _handle ? _status : null;
    return switch (status) {
      UsernameStatus.available => (
        '@$_handle is yours to claim',
        AppColors.success,
      ),
      UsernameStatus.taken => ('@$_handle is taken', AppColors.error),
      UsernameStatus.reserved => ('@$_handle is reserved', AppColors.error),
      UsernameStatus.invalid => ('3–20 letters, numbers or _', AppColors.error),
      null => (
        _checking ? 'Checking @$_handle…' : null,
        AppColors.textSecondary,
      ),
    };
  }

  void update(String value) {
    _timer?.cancel();
    _handle = value.trim().toLowerCase();
    _status = null;
    _checking = formatOk;
    _notify();
    if (!formatOk) return;
    final asked = _handle;
    _timer = Timer(debounce, () async {
      final status = await _check(asked);
      if (_disposed || _handle != asked) return;
      _checked = asked;
      _status = status;
      _checking = false;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
