import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io'; // Add this import for InternetAddress

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

  Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }

  /// Checks if the device has an active internet connection.
  ///
  /// First checks network interface status using connectivity_plus, then
  /// performs a lightweight lookup to confirm actual internet access.
  /// Returns true if a connection is available and functional, false otherwise.
  ///
  /// Note: This method does not guarantee a specific network request will succeed,
  /// but provides a reliable indication of internet availability.
  Future<bool> hasInternetConnection() async {
    try {
      // Step 1: Check network interface status
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false; // No network interface available
      }

      // Step 2: Perform a lightweight network test
      final result = await InternetAddress.lookup('8.8.8.8').timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Internet check timed out'),
      );

      // Check if the lookup succeeded and has valid results
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true; // Internet is accessible
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking internet connection: $e');
      }
      return false; // Assume no connection on any error
    }
  }
}
