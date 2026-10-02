/// Application-wide logging utility
///
/// In release builds, only errors and warnings are logged.
/// In debug builds, all log levels are available.
///
/// Usage:
///   AppLogger.debug('Debug message');
///   AppLogger.info('Info message');
///   AppLogger.warning('Warning message');
///   AppLogger.error('Error message', error: e, stackTrace: stack);
library;

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class AppLogger {
  /// Controls whether debug/verbose/info logs are emitted
  /// In release mode, only warnings and errors are logged
  static bool get _shouldLogDebug => kDebugMode;

  static void info(String message, {String? tag}) {
    if (!_shouldLogDebug) return;
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 800, // Info level
    );
  }

  static void debug(String message, {String? tag}) {
    if (!_shouldLogDebug) return;
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 700, // Debug level
    );
  }

  static void warning(String message, {String? tag}) {
    // Warnings are always logged
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 900, // Warning level
    );
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Errors are always logged
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 1000, // Error level
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void verbose(String message, {String? tag}) {
    if (!_shouldLogDebug) return;
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 500, // Verbose level
    );
  }

  /// Routes Flutter's global `debugPrint` through this logger's release rule.
  ///
  /// `debugPrint` is NOT stripped from release builds: every call reaches
  /// logcat, where any app with log access, a bug report or a USB cable can
  /// read it. Many call sites print wallet addresses and challenge data, so in
  /// a release build the hook drops the line. Debug and profile builds are
  /// unchanged. Call once, first thing in `main()`.
  static void installReleaseLogPolicy({bool releaseMode = kReleaseMode}) {
    if (!releaseMode) return;
    debugPrint = _dropDebugPrint;
  }

  static void _dropDebugPrint(String? message, {int? wrapWidth}) {}

  /// Print-style logging that respects debug mode
  /// Use this instead of print() or debugPrint()
  static void print(String message, {String? tag}) {
    if (!_shouldLogDebug) return;
    debugPrint('[${tag ?? 'ChumbucketApp'}] $message');
  }
}
