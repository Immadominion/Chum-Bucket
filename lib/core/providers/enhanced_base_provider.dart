import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'dart:io';

enum LoadingState { idle, loading, success, error }

/// Enhanced base class for providers with improved error handling,
/// caching, and performance optimizations
class EnhancedBaseChangeNotifier extends ChangeNotifier {
  LoadingState _loadingState = LoadingState.idle;
  String? _errorMessage;
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  // Performance optimization - batch notifications
  Timer? _notifyTimer;
  bool _hasPendingNotification = false;

  // Error recovery
  int _retryCount = 0;
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  LoadingState get loadingState => _loadingState;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _loadingState == LoadingState.loading;
  bool get hasError => _loadingState == LoadingState.error;
  bool get isSuccess => _loadingState == LoadingState.success;
  bool get isIdle => _loadingState == LoadingState.idle;
  int get retryCount => _retryCount;

  /// Set loading state with optional operation identifier for better debugging
  void setLoading([String? operation]) {
    _loadingState = LoadingState.loading;
    _errorMessage = null;
    _batchedNotifyListeners();

    if (operation != null) {
      AppLogger.debug('Starting operation: $operation');
    }
  }

  /// Set success state and reset retry count
  void setSuccess([String? operation]) {
    _loadingState = LoadingState.success;
    _errorMessage = null;
    _retryCount = 0;
    _batchedNotifyListeners();

    if (operation != null) {
      AppLogger.debug('Completed operation: $operation');
    }
  }

  /// Set error state with enhanced error handling
  void setError(
    String message, [
    String? operation,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    _loadingState = LoadingState.error;
    _errorMessage = message;
    _batchedNotifyListeners();

    // Enhanced error logging
    if (operation != null) {
      AppLogger.error(
        'Error in operation: $operation - $message',
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      AppLogger.error('Error: $message', error: error, stackTrace: stackTrace);
    }
  }

  /// Set idle state
  void setIdle() {
    _loadingState = LoadingState.idle;
    _errorMessage = null;
    _retryCount = 0;
    _batchedNotifyListeners();
  }

  /// Enhanced async operation runner with retry logic and better error handling
  Future<T?> runAsync<T>(
    Future<T> Function() operation, {
    String? operationName,
    bool resetToIdle = false,
    bool enableRetry = false,
    bool enableCaching = false,
    String? cacheKey,
    Duration? cacheTtl,
  }) async {
    final opName = operationName ?? 'async_operation';

    // Check cache first if enabled
    if (enableCaching && cacheKey != null) {
      final cachedResult = _getCachedResult<T>(cacheKey, cacheTtl);
      if (cachedResult != null) {
        AppLogger.debug('Returning cached result for: $opName');
        return cachedResult;
      }
    }

    setLoading(opName);

    for (
      int attempt = 0;
      attempt <= (enableRetry ? maxRetries : 0);
      attempt++
    ) {
      try {
        final result = await operation();

        // Cache the result if enabled
        if (enableCaching && cacheKey != null) {
          _setCachedResult(cacheKey, result);
        }

        if (resetToIdle) {
          setIdle();
        } else {
          setSuccess(opName);
        }

        return result;
      } catch (error, stackTrace) {
        _retryCount = attempt;

        if (attempt < (enableRetry ? maxRetries : 0)) {
          AppLogger.warning(
            'Attempt ${attempt + 1} failed for $opName, retrying in ${retryDelay.inSeconds}s...',
          );
          await Future.delayed(retryDelay);
          continue;
        }

        // Final attempt failed
        String errorMessage = _getErrorMessage(error);
        setError(errorMessage, opName, error, stackTrace);
        return null;
      }
    }

    return null;
  }

  /// Cache management methods
  T? _getCachedResult<T>(String key, Duration? ttl) {
    if (!_cache.containsKey(key)) return null;

    final timestamp = _cacheTimestamps[key];
    if (timestamp != null && ttl != null) {
      if (DateTime.now().difference(timestamp) > ttl) {
        _cache.remove(key);
        _cacheTimestamps.remove(key);
        return null;
      }
    }

    return _cache[key] as T?;
  }

  void _setCachedResult<T>(String key, T value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
  }

  /// Clear cache for a specific key or all cache
  void clearCache([String? key]) {
    if (key != null) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    } else {
      _cache.clear();
      _cacheTimestamps.clear();
    }
    AppLogger.debug('Cache cleared${key != null ? ' for key: $key' : ''}');
  }

  /// Batched notification system to improve performance
  void _batchedNotifyListeners() {
    if (_notifyTimer != null) {
      // Already have a pending notification
      _hasPendingNotification = true;
      return;
    }

    // Schedule notification for next frame
    _notifyTimer = Timer(const Duration(milliseconds: 16), () {
      _notifyTimer = null;
      if (_hasPendingNotification) {
        _hasPendingNotification = false;
        _batchedNotifyListeners();
      } else {
        notifyListeners();
      }
    });
  }

  /// Force immediate notification (use sparingly)
  void forceNotify() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _hasPendingNotification = false;
    notifyListeners();
  }

  /// Enhanced internet connectivity check
  Future<bool> hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Double-check with actual internet access
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      AppLogger.warning('Internet connectivity check failed: $e');
      return false;
    }
  }

  /// Retry the last failed operation
  Future<void> retry() async {
    if (_loadingState == LoadingState.error) {
      _retryCount = 0;
      // Note: Subclasses should override this to implement specific retry logic
      AppLogger.info('Retry requested but no retry logic implemented');
    }
  }

  /// Get user-friendly error message
  String _getErrorMessage(dynamic error) {
    if (error is TimeoutException) {
      return 'The operation timed out. Please check your internet connection and try again.';
    } else if (error is SocketException) {
      return 'Network error. Please check your internet connection.';
    } else if (error is FormatException) {
      return 'Data format error. Please try again.';
    } else if (error.toString().toLowerCase().contains('permission')) {
      return 'Permission denied. Please check your app permissions.';
    } else if (error.toString().toLowerCase().contains('unauthorized')) {
      return 'Authentication required. Please sign in again.';
    } else {
      return error.toString();
    }
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'totalKeys': _cache.length,
      'keys': _cache.keys.toList(),
      'timestamps': _cacheTimestamps.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
    };
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _cache.clear();
    _cacheTimestamps.clear();
    super.dispose();
  }
}
