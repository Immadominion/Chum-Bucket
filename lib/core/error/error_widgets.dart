import 'package:flutter/material.dart';

import 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';
import '../error/error_handler.dart';

/// Error boundary widget that catches and handles widget tree errors
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, AppError error)? errorBuilder;
  final void Function(AppError error)? onError;
  final String? context;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onError,
    this.context,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  AppError? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          _buildDefaultErrorWidget(context, _error!);
    }

    return ErrorCatcher(onError: _handleError, child: widget.child);
  }

  void _handleError(dynamic error, StackTrace stackTrace) {
    final appError = AppError(
      error: error,
      stackTrace: stackTrace,
      context: widget.context ?? 'Widget Tree',
      severity: ErrorSeverity.high,
      timestamp: DateTime.now(),
    );

    setState(() {
      _error = appError;
    });

    // Log the error
    ErrorHandler().handleError(
      error,
      stackTrace: stackTrace,
      context: widget.context,
      severity: ErrorSeverity.high,
    );

    // Call custom error handler
    widget.onError?.call(appError);
  }

  Widget _buildDefaultErrorWidget(BuildContext context, AppError error) {
    return DefaultErrorWidget(
      error: error,
      onRetry: () => setState(() => _error = null),
    );
  }
}

/// Widget that catches Flutter framework errors
class ErrorCatcher extends StatefulWidget {
  final Widget child;
  final void Function(dynamic error, StackTrace stackTrace) onError;

  const ErrorCatcher({super.key, required this.child, required this.onError});

  @override
  State<ErrorCatcher> createState() => _ErrorCatcherState();
}

class _ErrorCatcherState extends State<ErrorCatcher> {
  @override
  void initState() {
    super.initState();

    // Set up Flutter error handler
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      widget.onError(details.exception, details.stack ?? StackTrace.current);
      originalOnError?.call(details);
    };
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Default error widget: the brand error scene, one line, one action.
class DefaultErrorWidget extends StatelessWidget {
  final AppError error;
  final VoidCallback? onRetry;
  final String? customMessage;

  const DefaultErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ChumbucketStateView(
          artwork: ChumbucketStateArtwork.error,
          message: 'Something went wrong',
          // Only a caller's own sentence is read out; the raw error is
          // for logs, never for people.
          semanticsHint: customMessage,
          actionLabel: onRetry == null ? null : 'Try again',
          onAction: onRetry,
        ),
      ),
    );
  }
}

/// Network error: the brand offline scene, one line, one action.
class NetworkErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const NetworkErrorWidget({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ChumbucketStateView(
          artwork: ChumbucketStateArtwork.offline,
          message: 'You’re offline',
          semanticsHint: message,
          actionLabel: onRetry == null ? null : 'Try again',
          onAction: onRetry,
        ),
      ),
    );
  }
}

/// A failed async load: the brand error scene, one line, one action.
class LoadingErrorWidget extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final bool showDetails;

  const LoadingErrorWidget({
    super.key,
    this.message,
    this.onRetry,
    this.showDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ChumbucketStateView(
          artwork: ChumbucketStateArtwork.error,
          message: 'Couldn’t load this',
          semanticsHint: message,
          actionLabel: onRetry == null ? null : 'Try again',
          onAction: onRetry,
          compact: true,
        ),
      ),
    );
  }
}

/// Async operation wrapper with error handling
class AsyncErrorHandler<T> extends StatefulWidget {
  final Future<T> Function() future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, dynamic error)? errorBuilder;
  final String? context;

  const AsyncErrorHandler({
    super.key,
    required this.future,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.context,
  });

  @override
  State<AsyncErrorHandler<T>> createState() => _AsyncErrorHandlerState<T>();
}

class _AsyncErrorHandlerState<T> extends State<AsyncErrorHandler<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = _executeFuture();
  }

  Future<T> _executeFuture() async {
    try {
      return await widget.future();
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: widget.context ?? 'Async Operation',
        severity: ErrorSeverity.medium,
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _future = _executeFuture();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.loadingBuilder?.call(context) ??
              const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error) ??
              LoadingErrorWidget(
                message: 'Failed to load data',
                onRetry: _retry,
              );
        }

        if (snapshot.hasData) {
          return widget.builder(context, snapshot.data as T);
        }

        return LoadingErrorWidget(
          message: 'No data available',
          onRetry: _retry,
        );
      },
    );
  }
}

/// Stream error handler widget
class StreamErrorHandler<T> extends StatefulWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, dynamic error)? errorBuilder;
  final String? context;

  const StreamErrorHandler({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.context,
  });

  @override
  State<StreamErrorHandler<T>> createState() => _StreamErrorHandlerState<T>();
}

class _StreamErrorHandlerState<T> extends State<StreamErrorHandler<T>> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.loadingBuilder?.call(context) ??
              const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          ErrorHandler().handleError(
            snapshot.error,
            context: widget.context ?? 'Stream Operation',
            severity: ErrorSeverity.medium,
          );

          return widget.errorBuilder?.call(context, snapshot.error) ??
              LoadingErrorWidget(message: 'Stream error occurred');
        }

        if (snapshot.hasData) {
          return widget.builder(context, snapshot.data as T);
        }

        return widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator());
      },
    );
  }
}
