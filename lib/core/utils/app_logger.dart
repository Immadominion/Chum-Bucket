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

  /// Print-style logging that respects debug mode
  /// Use this instead of print() or debugPrint()
  static void print(String message, {String? tag}) {
    if (!_shouldLogDebug) return;
    debugPrint('[${tag ?? 'ChumbucketApp'}] $message');
  }
}
