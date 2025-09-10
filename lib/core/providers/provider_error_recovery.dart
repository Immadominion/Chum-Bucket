import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// Error recovery strategies for providers
enum ErrorRecoveryStrategy { none, retry, fallback, refresh, resetState }

/// Error recovery configuration
class ErrorRecoveryConfig {
  final ErrorRecoveryStrategy strategy;
  final int maxRetries;
  final Duration retryDelay;
  final bool exponentialBackoff;
  final Future<void> Function()? fallbackAction;
  final Future<void> Function()? refreshAction;
  final VoidCallback? resetAction;

  const ErrorRecoveryConfig({
    this.strategy = ErrorRecoveryStrategy.retry,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.exponentialBackoff = true,
    this.fallbackAction,
    this.refreshAction,
    this.resetAction,
  });

  ErrorRecoveryConfig copyWith({
    ErrorRecoveryStrategy? strategy,
    int? maxRetries,
    Duration? retryDelay,
    bool? exponentialBackoff,
    Future<void> Function()? fallbackAction,
    Future<void> Function()? refreshAction,
    VoidCallback? resetAction,
  }) {
    return ErrorRecoveryConfig(
      strategy: strategy ?? this.strategy,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      exponentialBackoff: exponentialBackoff ?? this.exponentialBackoff,
      fallbackAction: fallbackAction ?? this.fallbackAction,
      refreshAction: refreshAction ?? this.refreshAction,
      resetAction: resetAction ?? this.resetAction,
    );
  }
}

/// Error information with context
class ProviderError {
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;
  final String? operation;
  final DateTime timestamp;
  final Map<String, dynamic>? context;

  ProviderError({
    required this.message,
    this.originalError,
    this.stackTrace,
    this.operation,
    DateTime? timestamp,
    this.context,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    final buffer = StringBuffer('ProviderError: $message');
    if (operation != null) {
      buffer.write(' (Operation: $operation)');
    }
    buffer.write(' at ${timestamp.toIso8601String()}');
    return buffer.toString();
  }
}

/// Error recovery manager for providers
class ProviderErrorRecovery {
  static final Map<String, List<ProviderError>> _errorHistory = {};
  static final Map<String, int> _retryAttempts = {};
  static final Map<String, DateTime> _lastRetryTimes = {};

  /// Execute an operation with error recovery
  static Future<T?> executeWithRecovery<T>({
    required String operationKey,
    required Future<T> Function() operation,
    required ErrorRecoveryConfig config,
    String? operationName,
    Map<String, dynamic>? context,
  }) async {
    final opName = operationName ?? operationKey;
    int currentAttempt = 0;

    while (currentAttempt <= config.maxRetries) {
      try {
        final result = await operation();

        // Success - reset retry attempts
        _retryAttempts.remove(operationKey);
        _lastRetryTimes.remove(operationKey);

        AppLogger.debug(
          'Operation $opName succeeded after ${currentAttempt + 1} attempt(s)',
        );
        return result;
      } catch (error, stackTrace) {
        final providerError = ProviderError(
          message: error.toString(),
          originalError: error,
          stackTrace: stackTrace,
          operation: opName,
          context: context,
        );

        // Record error in history
        _recordError(operationKey, providerError);

        currentAttempt++;
        _retryAttempts[operationKey] = currentAttempt;
        _lastRetryTimes[operationKey] = DateTime.now();

        // If this was the last attempt, handle final error
        if (currentAttempt > config.maxRetries) {
          AppLogger.error(
            'Operation $opName failed after ${config.maxRetries + 1} attempts',
          );
          await _handleFinalError(operationKey, providerError, config);
          return null;
        }

        // Calculate delay for next retry
        Duration delay = config.retryDelay;
        if (config.exponentialBackoff) {
          delay = Duration(
            milliseconds:
                (config.retryDelay.inMilliseconds *
                        (currentAttempt * currentAttempt))
                    .toInt(),
          );
        }

        AppLogger.warning(
          'Operation $opName failed (attempt $currentAttempt/${config.maxRetries + 1}), '
          'retrying in ${delay.inSeconds}s: ${error.toString()}',
        );

        await Future.delayed(delay);
      }
    }

    return null;
  }

  /// Record error in history
  static void _recordError(String operationKey, ProviderError error) {
    _errorHistory.putIfAbsent(operationKey, () => []).add(error);

    // Keep only last 10 errors per operation
    final errors = _errorHistory[operationKey]!;
    if (errors.length > 10) {
      errors.removeRange(0, errors.length - 10);
    }
  }

  /// Handle final error based on recovery strategy
  static Future<void> _handleFinalError(
    String operationKey,
    ProviderError error,
    ErrorRecoveryConfig config,
  ) async {
    switch (config.strategy) {
      case ErrorRecoveryStrategy.fallback:
        if (config.fallbackAction != null) {
          try {
            await config.fallbackAction!();
            AppLogger.info('Fallback action executed for $operationKey');
          } catch (fallbackError) {
            AppLogger.error(
              'Fallback action failed for $operationKey: $fallbackError',
            );
          }
        }
        break;

      case ErrorRecoveryStrategy.refresh:
        if (config.refreshAction != null) {
          try {
            await config.refreshAction!();
            AppLogger.info('Refresh action executed for $operationKey');
          } catch (refreshError) {
            AppLogger.error(
              'Refresh action failed for $operationKey: $refreshError',
            );
          }
        }
        break;

      case ErrorRecoveryStrategy.resetState:
        if (config.resetAction != null) {
          config.resetAction!();
          AppLogger.info('State reset action executed for $operationKey');
        }
        break;

      case ErrorRecoveryStrategy.none:
      case ErrorRecoveryStrategy.retry:
        // No additional action needed
        break;
    }
  }

  /// Get error history for an operation
  static List<ProviderError> getErrorHistory(String operationKey) {
    return List.from(_errorHistory[operationKey] ?? []);
  }

  /// Get current retry attempt count
  static int getRetryAttempts(String operationKey) {
    return _retryAttempts[operationKey] ?? 0;
  }

  /// Get last retry time
  static DateTime? getLastRetryTime(String operationKey) {
    return _lastRetryTimes[operationKey];
  }

  /// Clear error history for an operation or all operations
  static void clearErrorHistory([String? operationKey]) {
    if (operationKey != null) {
      _errorHistory.remove(operationKey);
      _retryAttempts.remove(operationKey);
      _lastRetryTimes.remove(operationKey);
    } else {
      _errorHistory.clear();
      _retryAttempts.clear();
      _lastRetryTimes.clear();
    }
  }

  /// Get error recovery statistics
  static Map<String, ErrorRecoveryStats> getRecoveryStats() {
    final stats = <String, ErrorRecoveryStats>{};

    for (final entry in _errorHistory.entries) {
      final operationKey = entry.key;
      final errors = entry.value;
      final retryAttempts = _retryAttempts[operationKey] ?? 0;
      final lastRetry = _lastRetryTimes[operationKey];

      stats[operationKey] = ErrorRecoveryStats(
        operationKey: operationKey,
        totalErrors: errors.length,
        currentRetryAttempts: retryAttempts,
        lastErrorTime: errors.isNotEmpty ? errors.last.timestamp : null,
        lastRetryTime: lastRetry,
        errorTypes: _getErrorTypes(errors),
      );
    }

    return stats;
  }

  /// Get unique error types from error list
  static Map<String, int> _getErrorTypes(List<ProviderError> errors) {
    final types = <String, int>{};
    for (final error in errors) {
      final type = error.originalError.runtimeType.toString();
      types[type] = (types[type] ?? 0) + 1;
    }
    return types;
  }

  /// Check if an operation should be retried based on recent failures
  static bool shouldAllowRetry(
    String operationKey, {
    Duration cooldownPeriod = const Duration(minutes: 5),
  }) {
    final lastRetry = _lastRetryTimes[operationKey];
    if (lastRetry == null) return true;

    final timeSinceLastRetry = DateTime.now().difference(lastRetry);
    return timeSinceLastRetry > cooldownPeriod;
  }
}

/// Error recovery statistics
class ErrorRecoveryStats {
  final String operationKey;
  final int totalErrors;
  final int currentRetryAttempts;
  final DateTime? lastErrorTime;
  final DateTime? lastRetryTime;
  final Map<String, int> errorTypes;

  const ErrorRecoveryStats({
    required this.operationKey,
    required this.totalErrors,
    required this.currentRetryAttempts,
    this.lastErrorTime,
    this.lastRetryTime,
    required this.errorTypes,
  });

  @override
  String toString() {
    return 'ErrorRecoveryStats{'
        'operationKey: $operationKey, '
        'totalErrors: $totalErrors, '
        'currentRetryAttempts: $currentRetryAttempts, '
        'lastErrorTime: $lastErrorTime, '
        'lastRetryTime: $lastRetryTime, '
        'errorTypes: $errorTypes'
        '}';
  }
}

/// Mixin to add error recovery capabilities to providers
mixin ErrorRecoveryMixin on ChangeNotifier {
  String get providerName;

  /// Execute operation with error recovery
  Future<T?> executeWithRecovery<T>({
    required String operationName,
    required Future<T> Function() operation,
    ErrorRecoveryConfig? config,
    Map<String, dynamic>? context,
  }) {
    final operationKey = '${providerName}_$operationName';
    return ProviderErrorRecovery.executeWithRecovery(
      operationKey: operationKey,
      operation: operation,
      config: config ?? getDefaultErrorRecoveryConfig(),
      operationName: operationName,
      context: context,
    );
  }

  /// Get default error recovery configuration
  /// Subclasses can override this to provide custom configs
  ErrorRecoveryConfig getDefaultErrorRecoveryConfig() {
    return const ErrorRecoveryConfig(
      strategy: ErrorRecoveryStrategy.retry,
      maxRetries: 3,
      retryDelay: Duration(seconds: 2),
      exponentialBackoff: true,
    );
  }

  /// Get error history for this provider
  List<ProviderError> getErrorHistory(String operationName) {
    return ProviderErrorRecovery.getErrorHistory(
      '${providerName}_$operationName',
    );
  }

  /// Clear error history for this provider
  void clearErrorHistory([String? operationName]) {
    if (operationName != null) {
      ProviderErrorRecovery.clearErrorHistory('${providerName}_$operationName');
    } else {
      // Clear all errors for this provider
      final stats = ProviderErrorRecovery.getRecoveryStats();
      for (final key in stats.keys) {
        if (key.startsWith('${providerName}_')) {
          ProviderErrorRecovery.clearErrorHistory(key);
        }
      }
    }
  }
}
