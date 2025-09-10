import 'dart:async';
import '../utils/app_logger.dart';

/// Comprehensive error handling system for the application
class ErrorHandler {
  static final ErrorHandler _instance = ErrorHandler._internal();
  factory ErrorHandler() => _instance;
  ErrorHandler._internal();

  final List<AppError> _errorHistory = [];
  final StreamController<AppError> _errorStream = StreamController.broadcast();

  /// Stream of all application errors
  Stream<AppError> get errorStream => _errorStream.stream;

  /// Get error history (last 50 errors)
  List<AppError> get errorHistory =>
      List.unmodifiable(_errorHistory.take(50).toList());

  /// Handle an error with optional user notification
  void handleError(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    ErrorSeverity severity = ErrorSeverity.medium,
    bool notifyUser = false,
    String? userMessage,
    Map<String, dynamic>? metadata,
  }) {
    final appError = AppError(
      error: error,
      stackTrace: stackTrace ?? StackTrace.current,
      context: context,
      severity: severity,
      timestamp: DateTime.now(),
      userMessage: userMessage,
      metadata: metadata,
    );

    _addError(appError);
    _logError(appError);

    if (notifyUser) {
      _notifyUser(appError);
    }

    // Critical errors should be handled immediately
    if (severity == ErrorSeverity.critical) {
      _handleCriticalError(appError);
    }
  }

  /// Handle async operation errors with proper logging
  static Future<T?> handleAsync<T>(
    Future<T> future, {
    String? context,
    T? fallback,
    bool notifyUser = false,
    String? userMessage,
  }) async {
    try {
      return await future;
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: context,
        notifyUser: notifyUser,
        userMessage: userMessage,
      );
      return fallback;
    }
  }

  /// Safe execution of synchronous operations
  static T? handleSync<T>(
    T Function() operation, {
    String? context,
    T? fallback,
    bool notifyUser = false,
    String? userMessage,
  }) {
    try {
      return operation();
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: context,
        notifyUser: notifyUser,
        userMessage: userMessage,
      );
      return fallback;
    }
  }

  /// Add error to history and stream
  void _addError(AppError error) {
    _errorHistory.insert(0, error);
    if (_errorHistory.length > 100) {
      _errorHistory.removeLast();
    }
    _errorStream.add(error);
  }

  /// Log error with appropriate level
  void _logError(AppError error) {
    final message = 'Error in ${error.context ?? 'Unknown'}: ${error.message}';

    switch (error.severity) {
      case ErrorSeverity.low:
        AppLogger.debug(message, tag: 'ErrorHandler');
        break;
      case ErrorSeverity.medium:
        AppLogger.warning(message, tag: 'ErrorHandler');
        break;
      case ErrorSeverity.high:
        AppLogger.error(
          message,
          tag: 'ErrorHandler',
          error: error.error,
          stackTrace: error.stackTrace,
        );
        break;
      case ErrorSeverity.critical:
        AppLogger.error(
          'CRITICAL: $message',
          tag: 'ErrorHandler',
          error: error.error,
          stackTrace: error.stackTrace,
        );
        break;
    }
  }

  /// Notify user of error (would integrate with UI notification system)
  void _notifyUser(AppError error) {
    // This would integrate with your notification system
    // For now, just log the user message
    final message = error.userMessage ?? _getDefaultUserMessage(error);
    AppLogger.info('User notification: $message', tag: 'ErrorHandler');

    // In a real implementation, you might:
    // - Show a SnackBar
    // - Display an error dialog
    // - Send to notification service
  }

  /// Handle critical errors that might require immediate action
  void _handleCriticalError(AppError error) {
    AppLogger.error(
      'CRITICAL ERROR DETECTED: ${error.message}',
      tag: 'ErrorHandler',
      error: error.error,
      stackTrace: error.stackTrace,
    );

    // In a production app, you might:
    // - Send crash report to analytics
    // - Show emergency UI
    // - Attempt data recovery
    // - Force app restart in extreme cases
  }

  /// Get default user-friendly message for error
  String _getDefaultUserMessage(AppError error) {
    switch (error.severity) {
      case ErrorSeverity.low:
        return 'A minor issue occurred, but everything should continue working normally.';
      case ErrorSeverity.medium:
        return 'Something went wrong. Please try again.';
      case ErrorSeverity.high:
        return 'An error occurred. If this persists, please contact support.';
      case ErrorSeverity.critical:
        return 'A serious error occurred. The app may need to restart.';
    }
  }

  /// Clear error history
  void clearHistory() {
    _errorHistory.clear();
  }

  /// Dispose of resources
  void dispose() {
    _errorStream.close();
    _errorHistory.clear();
  }
}

/// Represents an application error with metadata
class AppError {
  final dynamic error;
  final StackTrace stackTrace;
  final String? context;
  final ErrorSeverity severity;
  final DateTime timestamp;
  final String? userMessage;
  final Map<String, dynamic>? metadata;

  const AppError({
    required this.error,
    required this.stackTrace,
    this.context,
    required this.severity,
    required this.timestamp,
    this.userMessage,
    this.metadata,
  });

  /// Get error message from various error types
  String get message {
    if (error is Exception) {
      return error.toString();
    } else if (error is Error) {
      return error.toString();
    } else if (error is String) {
      return error;
    } else {
      return error?.toString() ?? 'Unknown error';
    }
  }

  /// Get error type name
  String get errorType => error.runtimeType.toString();

  /// Convert to map for logging/analytics
  Map<String, dynamic> toMap() {
    return {
      'message': message,
      'errorType': errorType,
      'context': context,
      'severity': severity.name,
      'timestamp': timestamp.toIso8601String(),
      'userMessage': userMessage,
      'stackTrace': stackTrace.toString(),
      'metadata': metadata,
    };
  }

  @override
  String toString() {
    return 'AppError(message: $message, context: $context, severity: $severity)';
  }
}

/// Error severity levels
enum ErrorSeverity { low, medium, high, critical }

/// Network-specific error handling
class NetworkErrorHandler {
  static String getUserFriendlyMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout')) {
      return 'Connection timeout. Please check your internet connection and try again.';
    } else if (errorString.contains('no internet') ||
        errorString.contains('network')) {
      return 'No internet connection. Please check your network settings.';
    } else if (errorString.contains('400')) {
      return 'Invalid request. Please check your input and try again.';
    } else if (errorString.contains('401') ||
        errorString.contains('unauthorized')) {
      return 'Authentication failed. Please log in again.';
    } else if (errorString.contains('403') ||
        errorString.contains('forbidden')) {
      return 'Access denied. You don\'t have permission for this action.';
    } else if (errorString.contains('404') ||
        errorString.contains('not found')) {
      return 'The requested resource was not found.';
    } else if (errorString.contains('500') || errorString.contains('server')) {
      return 'Server error. Please try again later.';
    } else {
      return 'Network error occurred. Please try again.';
    }
  }

  static Future<T?> handleNetworkCall<T>(
    Future<T> networkCall, {
    String? context,
    T? fallback,
    bool notifyUser = true,
  }) async {
    return ErrorHandler.handleAsync(
      networkCall,
      context: context ?? 'Network Call',
      fallback: fallback,
      notifyUser: notifyUser,
      userMessage: 'Network operation failed',
    );
  }
}

/// Authentication-specific error handling
class AuthErrorHandler {
  static String getUserFriendlyMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('invalid credentials') ||
        errorString.contains('wrong password')) {
      return 'Invalid email or password. Please try again.';
    } else if (errorString.contains('user not found')) {
      return 'No account found with this email address.';
    } else if (errorString.contains('email already')) {
      return 'An account with this email already exists.';
    } else if (errorString.contains('weak password')) {
      return 'Password is too weak. Please choose a stronger password.';
    } else if (errorString.contains('too many attempts')) {
      return 'Too many login attempts. Please try again later.';
    } else {
      return 'Authentication error. Please try again.';
    }
  }
}

/// Data validation error handling
class ValidationErrorHandler {
  static String getUserFriendlyMessage(String field, String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('required') || errorLower.contains('empty')) {
      return '$field is required.';
    } else if (errorLower.contains('invalid format') ||
        errorLower.contains('format')) {
      return '$field has an invalid format.';
    } else if (errorLower.contains('too short')) {
      return '$field is too short.';
    } else if (errorLower.contains('too long')) {
      return '$field is too long.';
    } else {
      return '$field is invalid.';
    }
  }
}
