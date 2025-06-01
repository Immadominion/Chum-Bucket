import 'package:flutter/foundation.dart';

enum LoadingState { idle, loading, success, error }

class BaseChangeNotifier extends ChangeNotifier {
  LoadingState _loadingState = LoadingState.idle;
  String? _errorMessage;

  LoadingState get loadingState => _loadingState;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _loadingState == LoadingState.loading;
  bool get hasError => _loadingState == LoadingState.error;
  bool get isSuccess => _loadingState == LoadingState.success;
  bool get isIdle => _loadingState == LoadingState.idle;

  void setLoading() {
    _loadingState = LoadingState.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void setSuccess() {
    _loadingState = LoadingState.success;
    _errorMessage = null;
    notifyListeners();
  }

  void setError(String message) {
    _loadingState = LoadingState.error;
    _errorMessage = message;
    notifyListeners();
  }

  void setIdle() {
    _loadingState = LoadingState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  /// Helper method to run async operations with state management
  /// 
  /// Automatically sets loading state before execution and 
  /// error state if an exception occurs.
  /// 
  /// If [resetToIdle] is true, state will be set to idle after successful execution.
  /// Otherwise, state will be set to success.
  Future<T> runAsync<T>(
    Future<T> Function() asyncFunction, {
    bool resetToIdle = true,
    Duration resetDelay = const Duration(seconds: 2),
  }) async {
    try {
      setLoading();
      final result = await asyncFunction();
      setSuccess();

      // Optionally reset back to idle state after success
      if (resetToIdle) {
        await Future.delayed(resetDelay);
        setIdle();
      }

      return result;
    } catch (e) {
      setError(e.toString());
      rethrow;
    }
  }
}
