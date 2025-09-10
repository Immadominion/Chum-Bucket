import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Enhanced logging system with structured logging and different outputs
class EnhancedLogger {
  static final EnhancedLogger _instance = EnhancedLogger._internal();
  factory EnhancedLogger() => _instance;
  EnhancedLogger._internal();

  final List<LogEntry> _logHistory = [];
  final StreamController<LogEntry> _logStream = StreamController.broadcast();
  File? _logFile;
  bool _initialized = false;

  /// Initialize the logger
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (!kIsWeb) {
        final directory = await getApplicationDocumentsDirectory();
        _logFile = File('${directory.path}/app_logs.txt');
      }
      _initialized = true;
    } catch (e) {
      developer.log('Failed to initialize logger: $e', name: 'EnhancedLogger');
    }
  }

  /// Stream of all log entries
  Stream<LogEntry> get logStream => _logStream.stream;

  /// Get log history (last 1000 entries)
  List<LogEntry> get logHistory =>
      List.unmodifiable(_logHistory.take(1000).toList());

  /// Log a message with specified level
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? tag,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      message: message,
      level: level,
      tag: tag ?? 'App',
      timestamp: DateTime.now(),
      metadata: metadata,
      error: error,
      stackTrace: stackTrace,
    );

    _addLogEntry(entry);
    _outputToConsole(entry);
    _outputToFile(entry);
  }

  /// Convenience methods for different log levels
  void verbose(String message, {String? tag, Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.verbose, tag: tag, metadata: metadata);
  }

  void debug(String message, {String? tag, Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.debug, tag: tag, metadata: metadata);
  }

  void info(String message, {String? tag, Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.info, tag: tag, metadata: metadata);
  }

  void warning(String message, {String? tag, Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.warning, tag: tag, metadata: metadata);
  }

  void error(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      level: LogLevel.error,
      tag: tag,
      metadata: metadata,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void critical(
    String message, {
    String? tag,
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      level: LogLevel.critical,
      tag: tag,
      metadata: metadata,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Add log entry to history and stream
  void _addLogEntry(LogEntry entry) {
    _logHistory.insert(0, entry);
    if (_logHistory.length > 2000) {
      _logHistory.removeLast();
    }
    _logStream.add(entry);
  }

  /// Output to Flutter's developer console
  void _outputToConsole(LogEntry entry) {
    final int level = switch (entry.level) {
      LogLevel.verbose => 500,
      LogLevel.debug => 700,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
      LogLevel.critical => 1200,
    };

    developer.log(
      entry.message,
      name: entry.tag,
      level: level,
      error: entry.error,
      stackTrace: entry.stackTrace,
    );
  }

  /// Output to file (if available)
  void _outputToFile(LogEntry entry) {
    if (_logFile == null || !_initialized) return;

    try {
      final logLine =
          '${entry.timestamp.toIso8601String()} '
          '[${entry.level.name.toUpperCase()}] '
          '${entry.tag}: ${entry.message}';

      _logFile!.writeAsStringSync('$logLine\n', mode: FileMode.append);
    } catch (e) {
      developer.log('Failed to write to log file: $e', name: 'EnhancedLogger');
    }
  }

  /// Clear log history
  void clearHistory() {
    _logHistory.clear();
  }

  /// Export logs as JSON string
  String exportLogsAsJson() {
    final logs = _logHistory.map((entry) => entry.toMap()).toList();
    return jsonEncode(logs);
  }

  /// Get logs filtered by level
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logHistory.where((entry) => entry.level == level).toList();
  }

  /// Get logs filtered by tag
  List<LogEntry> getLogsByTag(String tag) {
    return _logHistory.where((entry) => entry.tag == tag).toList();
  }

  /// Get logs within time range
  List<LogEntry> getLogsByTimeRange(DateTime start, DateTime end) {
    return _logHistory
        .where(
          (entry) =>
              entry.timestamp.isAfter(start) && entry.timestamp.isBefore(end),
        )
        .toList();
  }

  /// Dispose of resources
  void dispose() {
    _logStream.close();
    _logHistory.clear();
  }
}

/// Represents a log entry
class LogEntry {
  final String message;
  final LogLevel level;
  final String tag;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final Object? error;
  final StackTrace? stackTrace;

  const LogEntry({
    required this.message,
    required this.level,
    required this.tag,
    required this.timestamp,
    this.metadata,
    this.error,
    this.stackTrace,
  });

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'message': message,
      'level': level.name,
      'tag': tag,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
    };
  }

  @override
  String toString() {
    return '${timestamp.toIso8601String()} [$tag] ${level.name.toUpperCase()}: $message';
  }
}

/// Log levels in order of severity
enum LogLevel { verbose, debug, info, warning, error, critical }

/// User action tracking for analytics
class UserActionTracker {
  static final UserActionTracker _instance = UserActionTracker._internal();
  factory UserActionTracker() => _instance;
  UserActionTracker._internal();

  final List<UserAction> _actionHistory = [];
  final StreamController<UserAction> _actionStream =
      StreamController.broadcast();

  /// Stream of all user actions
  Stream<UserAction> get actionStream => _actionStream.stream;

  /// Get action history (last 500 actions)
  List<UserAction> get actionHistory =>
      List.unmodifiable(_actionHistory.take(500).toList());

  /// Track a user action
  void trackAction(
    String action, {
    String? category,
    Map<String, dynamic>? properties,
    String? screen,
    String? userId,
  }) {
    final userAction = UserAction(
      action: action,
      category: category ?? 'General',
      properties: properties,
      screen: screen,
      userId: userId,
      timestamp: DateTime.now(),
    );

    _addAction(userAction);

    // Log the action
    EnhancedLogger().info(
      'User action: $action',
      tag: 'UserAction',
      metadata: userAction.toMap(),
    );
  }

  /// Track navigation events
  void trackNavigation(
    String from,
    String to, {
    Map<String, dynamic>? properties,
  }) {
    trackAction(
      'navigation',
      category: 'Navigation',
      properties: {'from': from, 'to': to, ...?properties},
    );
  }

  /// Track button taps
  void trackButtonTap(
    String buttonName, {
    String? screen,
    Map<String, dynamic>? properties,
  }) {
    trackAction(
      'button_tap',
      category: 'Interaction',
      screen: screen,
      properties: {'button_name': buttonName, ...?properties},
    );
  }

  /// Track form submissions
  void trackFormSubmission(
    String formName, {
    bool success = true,
    Map<String, dynamic>? properties,
  }) {
    trackAction(
      'form_submission',
      category: 'Form',
      properties: {'form_name': formName, 'success': success, ...?properties},
    );
  }

  /// Track errors from user perspective
  void trackUserError(
    String error, {
    String? screen,
    Map<String, dynamic>? properties,
  }) {
    trackAction(
      'user_error',
      category: 'Error',
      screen: screen,
      properties: {'error': error, ...?properties},
    );
  }

  /// Add action to history and stream
  void _addAction(UserAction action) {
    _actionHistory.insert(0, action);
    if (_actionHistory.length > 1000) {
      _actionHistory.removeLast();
    }
    _actionStream.add(action);
  }

  /// Export actions as JSON
  String exportActionsAsJson() {
    final actions = _actionHistory.map((action) => action.toMap()).toList();
    return jsonEncode(actions);
  }

  /// Get actions by category
  List<UserAction> getActionsByCategory(String category) {
    return _actionHistory
        .where((action) => action.category == category)
        .toList();
  }

  /// Clear action history
  void clearHistory() {
    _actionHistory.clear();
  }

  /// Dispose of resources
  void dispose() {
    _actionStream.close();
    _actionHistory.clear();
  }
}

/// Represents a user action
class UserAction {
  final String action;
  final String category;
  final Map<String, dynamic>? properties;
  final String? screen;
  final String? userId;
  final DateTime timestamp;

  const UserAction({
    required this.action,
    required this.category,
    this.properties,
    this.screen,
    this.userId,
    required this.timestamp,
  });

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'action': action,
      'category': category,
      'properties': properties,
      'screen': screen,
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return '${timestamp.toIso8601String()} [$category] $action';
  }
}

/// Performance metrics logging
class PerformanceLogger {
  static final PerformanceLogger _instance = PerformanceLogger._internal();
  factory PerformanceLogger() => _instance;
  PerformanceLogger._internal();

  final Map<String, DateTime> _timers = {};
  final List<PerformanceMetric> _metrics = [];

  /// Start timing an operation
  void startTimer(String name) {
    _timers[name] = DateTime.now();
  }

  /// Stop timing and log the duration
  void stopTimer(String name, {Map<String, dynamic>? metadata}) {
    final startTime = _timers.remove(name);
    if (startTime == null) {
      EnhancedLogger().warning(
        'Timer "$name" was not started',
        tag: 'PerformanceLogger',
      );
      return;
    }

    final duration = DateTime.now().difference(startTime);
    final metric = PerformanceMetric(
      name: name,
      duration: duration,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _metrics.add(metric);

    EnhancedLogger().info(
      'Performance: $name took ${duration.inMilliseconds}ms',
      tag: 'Performance',
      metadata: metric.toMap(),
    );
  }

  /// Log a custom performance metric
  void logMetric(
    String name,
    double value, {
    String unit = 'ms',
    Map<String, dynamic>? metadata,
  }) {
    final metric = PerformanceMetric(
      name: name,
      value: value,
      unit: unit,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _metrics.add(metric);

    EnhancedLogger().info(
      'Metric: $name = $value$unit',
      tag: 'Performance',
      metadata: metric.toMap(),
    );
  }

  /// Get performance metrics
  List<PerformanceMetric> get metrics => List.unmodifiable(_metrics);

  /// Clear metrics
  void clearMetrics() {
    _metrics.clear();
    _timers.clear();
  }
}

/// Represents a performance metric
class PerformanceMetric {
  final String name;
  final Duration? duration;
  final double? value;
  final String? unit;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const PerformanceMetric({
    required this.name,
    this.duration,
    this.value,
    this.unit,
    required this.timestamp,
    this.metadata,
  });

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'duration_ms': duration?.inMilliseconds,
      'value': value,
      'unit': unit,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Wrapper around the original AppLogger to maintain compatibility
class AppLogger {
  static void info(String message, {String? tag}) {
    EnhancedLogger().info(message, tag: tag);
  }

  static void debug(String message, {String? tag}) {
    EnhancedLogger().debug(message, tag: tag);
  }

  static void warning(String message, {String? tag}) {
    EnhancedLogger().warning(message, tag: tag);
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    EnhancedLogger().error(
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void verbose(String message, {String? tag}) {
    EnhancedLogger().verbose(message, tag: tag);
  }
}
