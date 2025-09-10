import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// Performance monitoring utility for providers
class ProviderPerformanceMonitor {
  static final Map<String, List<Duration>> _operationDurations = {};
  static final Map<String, int> _operationCounts = {};
  static final Map<String, DateTime> _lastOperationTimes = {};
  static bool _monitoringEnabled = kDebugMode;

  /// Enable or disable performance monitoring
  static void setMonitoring(bool enabled) {
    _monitoringEnabled = enabled;
  }

  /// Time an operation and log performance metrics
  static Future<T> timeOperation<T>(
    String operationName,
    Future<T> Function() operation, {
    Duration? warningThreshold,
    bool logResult = false,
  }) async {
    if (!_monitoringEnabled) {
      return await operation();
    }

    final stopwatch = Stopwatch()..start();
    final startTime = DateTime.now();
    T result;

    try {
      result = await operation();
      if (logResult) {
        AppLogger.debug('Operation $operationName completed successfully');
      }
    } catch (error) {
      AppLogger.warning('Operation $operationName failed: $error');
      rethrow;
    } finally {
      stopwatch.stop();
      _recordOperation(
        operationName,
        stopwatch.elapsed,
        startTime,
        warningThreshold,
      );
    }

    return result;
  }

  /// Record operation metrics
  static void _recordOperation(
    String operationName,
    Duration duration,
    DateTime startTime,
    Duration? warningThreshold,
  ) {
    // Update operation statistics
    _operationDurations.putIfAbsent(operationName, () => []).add(duration);
    _operationCounts[operationName] =
        (_operationCounts[operationName] ?? 0) + 1;
    _lastOperationTimes[operationName] = startTime;

    // Log warning if operation exceeded threshold
    if (warningThreshold != null && duration > warningThreshold) {
      AppLogger.warning(
        'Operation $operationName took ${duration.inMilliseconds}ms '
        '(threshold: ${warningThreshold.inMilliseconds}ms)',
      );
    }

    // Periodic performance summary (every 10 operations)
    final count = _operationCounts[operationName]!;
    if (count % 10 == 0) {
      _logPerformanceSummary(operationName);
    }
  }

  /// Log performance summary for an operation
  static void _logPerformanceSummary(String operationName) {
    final durations = _operationDurations[operationName];
    if (durations == null || durations.isEmpty) return;

    final totalMs = durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    final avgMs = totalMs / durations.length;
    final maxMs = durations.fold<int>(
      0,
      (max, d) => d.inMilliseconds > max ? d.inMilliseconds : max,
    );
    final minMs = durations.fold<int>(
      durations.first.inMilliseconds,
      (min, d) => d.inMilliseconds < min ? d.inMilliseconds : min,
    );

    AppLogger.debug(
      'Performance Summary for $operationName:\n'
      '  Count: ${durations.length}\n'
      '  Average: ${avgMs.toStringAsFixed(1)}ms\n'
      '  Min: ${minMs}ms\n'
      '  Max: ${maxMs}ms\n'
      '  Total: ${totalMs}ms',
    );
  }

  /// Get performance statistics for all operations
  static Map<String, PerformanceStats> getStatistics() {
    final stats = <String, PerformanceStats>{};

    for (final operationName in _operationDurations.keys) {
      final durations = _operationDurations[operationName]!;
      final totalMs = durations.fold<int>(
        0,
        (sum, d) => sum + d.inMilliseconds,
      );

      stats[operationName] = PerformanceStats(
        operationName: operationName,
        count: _operationCounts[operationName] ?? 0,
        averageDuration: Duration(
          milliseconds: (totalMs / durations.length).round(),
        ),
        minDuration: durations.reduce((a, b) => a < b ? a : b),
        maxDuration: durations.reduce((a, b) => a > b ? a : b),
        totalDuration: Duration(milliseconds: totalMs),
        lastExecuted: _lastOperationTimes[operationName],
      );
    }

    return stats;
  }

  /// Get performance statistics for a specific operation
  static PerformanceStats? getOperationStats(String operationName) {
    return getStatistics()[operationName];
  }

  /// Clear performance data
  static void clearStats([String? operationName]) {
    if (operationName != null) {
      _operationDurations.remove(operationName);
      _operationCounts.remove(operationName);
      _lastOperationTimes.remove(operationName);
    } else {
      _operationDurations.clear();
      _operationCounts.clear();
      _lastOperationTimes.clear();
    }
  }

  /// Log current performance report
  static void logPerformanceReport() {
    if (!_monitoringEnabled) return;

    final stats = getStatistics();
    if (stats.isEmpty) {
      AppLogger.debug('No performance data available');
      return;
    }

    final buffer = StringBuffer('Performance Report:\n');
    for (final stat in stats.values) {
      buffer.writeln('${stat.operationName}:');
      buffer.writeln('  Count: ${stat.count}');
      buffer.writeln('  Avg: ${stat.averageDuration.inMilliseconds}ms');
      buffer.writeln(
        '  Min/Max: ${stat.minDuration.inMilliseconds}ms / ${stat.maxDuration.inMilliseconds}ms',
      );
      if (stat.lastExecuted != null) {
        buffer.writeln('  Last: ${stat.lastExecuted}');
      }
      buffer.writeln('');
    }

    AppLogger.debug(buffer.toString());
  }

  /// Monitor provider rebuild frequency
  static void monitorProviderRebuilds(String providerName) {
    if (!_monitoringEnabled) return;

    final key = '${providerName}_rebuild';
    _operationCounts[key] = (_operationCounts[key] ?? 0) + 1;
    _lastOperationTimes[key] = DateTime.now();

    final count = _operationCounts[key]!;
    if (count % 5 == 0) {
      AppLogger.debug('Provider $providerName has rebuilt $count times');
    }
  }

  /// Get provider rebuild statistics
  static Map<String, int> getProviderRebuildStats() {
    final rebuilds = <String, int>{};
    for (final entry in _operationCounts.entries) {
      if (entry.key.endsWith('_rebuild')) {
        final providerName = entry.key.replaceAll('_rebuild', '');
        rebuilds[providerName] = entry.value;
      }
    }
    return rebuilds;
  }
}

/// Performance statistics for an operation
class PerformanceStats {
  final String operationName;
  final int count;
  final Duration averageDuration;
  final Duration minDuration;
  final Duration maxDuration;
  final Duration totalDuration;
  final DateTime? lastExecuted;

  const PerformanceStats({
    required this.operationName,
    required this.count,
    required this.averageDuration,
    required this.minDuration,
    required this.maxDuration,
    required this.totalDuration,
    this.lastExecuted,
  });

  @override
  String toString() {
    return 'PerformanceStats{'
        'operationName: $operationName, '
        'count: $count, '
        'averageDuration: ${averageDuration.inMilliseconds}ms, '
        'minDuration: ${minDuration.inMilliseconds}ms, '
        'maxDuration: ${maxDuration.inMilliseconds}ms, '
        'totalDuration: ${totalDuration.inMilliseconds}ms, '
        'lastExecuted: $lastExecuted'
        '}';
  }
}

/// Mixin to add performance monitoring to providers
mixin ProviderPerformanceMixin on ChangeNotifier {
  String get providerName;

  @override
  void notifyListeners() {
    ProviderPerformanceMonitor.monitorProviderRebuilds(providerName);
    super.notifyListeners();
  }

  /// Time an async operation with performance monitoring
  Future<T> timeOperation<T>(
    String operationName,
    Future<T> Function() operation, {
    Duration? warningThreshold = const Duration(milliseconds: 500),
  }) {
    return ProviderPerformanceMonitor.timeOperation(
      '${providerName}_$operationName',
      operation,
      warningThreshold: warningThreshold,
    );
  }
}
