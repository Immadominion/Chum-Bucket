/// Application-wide logging utility
import 'dart:developer' as developer;

class AppLogger {
  static void info(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 800, // Info level
    );
  }

  static void debug(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 700, // Debug level
    );
  }

  static void warning(String message, {String? tag}) {
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
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 1000, // Error level
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void verbose(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? 'ChumbucketApp',
      level: 500, // Verbose level
    );
  }
}
