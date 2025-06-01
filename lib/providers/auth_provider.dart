import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:recess/providers/base_change_notifier.dart'
    show BaseChangeNotifier, LoadingState;

class AuthProvider extends BaseChangeNotifier {
  final Privy _privy;
  PrivyUser? _currentUser;
  bool _initialized = false;

  AuthProvider()
    : _privy = Privy.init(
        config: PrivyConfig(
          appId: dotenv.env['APP_ID'] ?? dotenv.env['PRIVY_APP_ID'] ?? '',
          appClientId:
              dotenv.env['APP_SECRET'] ?? dotenv.env['PRIVY_CLIENT_ID'] ?? '',
        ),
      ) {
    // Log warning if env variables are missing
    if ((dotenv.env['APP_ID'] ?? dotenv.env['PRIVY_APP_ID'] ?? '').isEmpty ||
        (dotenv.env['APP_SECRET'] ?? dotenv.env['PRIVY_CLIENT_ID'] ?? '')
            .isEmpty) {
      log(
        'WARNING: Privy credentials are missing. Check your .env file configuration.',
      );
      log(
        'Make sure your .env file exists and contains APP_ID and APP_SECRET or PRIVY_APP_ID and PRIVY_CLIENT_ID.',
      );
    }
  }

  PrivyUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    return runAsync(() async {
      try {
        await _privy.awaitReady();
        _currentUser = _privy.user;
        _initialized = true;
      } catch (e) {
        log('Failed to initialize Privy: ${e.toString()}');
        rethrow;
      }
    }, resetToIdle: true);
  }

  // Helper method to safely extract error message from Failure objects
  String _extractErrorMessage(dynamic failure) {
    if (failure == null) return "Unknown error";

    // Log the raw failure object to understand its structure
    log('Failure object structure: ${failure.runtimeType} - ${failure}');

    try {
      // Try to access known properties that might contain error information
      if (failure is Failure) {
        // Try to access error
        dynamic error;
        try {
          error = failure.error;
        } catch (_) {}

        // Return the first0available error information
        if (error != null) return error.toString();
      }

      // Check for common error patterns in toString()
      final str = failure.toString();
      if (str.contains("Invalid app client ID")) {
        return "Invalid API credentials. Please check your .env configuration.";
      }

      return str;
    } catch (e) {
      log('Error extracting failure message: $e');
      return "Unknown error occurred";
    }
  }

  Future<bool> sendEmailCode(String email) async {
    // Ensure the SDK is initialized first
    if (!_initialized) {
      try {
        await initialize();
      } catch (e) {
        setError("Failed to initialize authentication: ${e.toString()}");
        return false;
      }
    }

    try {
      setLoading();

      final result = await _privy.email.sendCode(email);

      // Log the raw result type for debugging
      log('sendEmailCode result type: ${result.runtimeType}');

      if (result is Success) {
        setSuccess();
        return true;
      } else if (result is Failure) {
        final errorMessage = _extractErrorMessage(result);
        final errorMsg = "Failed to send code: $errorMessage";
        log("Error: $errorMsg");
        setError(errorMsg);
        return false;
      } else {
        // Unknown result type
        log("Unknown result type: ${result.runtimeType}");
        setError("Unknown response from authentication service");
        return false;
      }
    } catch (e) {
      final errorMsg = "Error sending verification code: ${e.toString()}";
      log("Exception: $errorMsg");
      setError(errorMsg);
      return false;
    } finally {
      // Ensure we're not stuck in loading state if something unexpected happens
      if (loadingState == LoadingState.loading) {
        setIdle();
      }
    }
  }

  Future<bool> verifyEmailCode(String email, String code) async {
    // Ensure the SDK is initialized first
    if (!_initialized) {
      try {
        await initialize();
      } catch (e) {
        setError("Failed to initialize authentication: ${e.toString()}");
        return false;
      }
    }

    try {
      setLoading();

      final loginResult = await _privy.email.loginWithCode(
        code: code,
        email: email,
      );

      // Log the raw result type for debugging
      log('verifyEmailCode result type: ${loginResult.runtimeType}');

      if (loginResult is Success<PrivyUser>) {
        _currentUser = loginResult.value;
        setSuccess();
        return true;
      } else if (loginResult is Failure) {
        final errorMessage = _extractErrorMessage(loginResult);
        final errorMsg = "Verification failed: $errorMessage";
        log("Error: $errorMsg");
        setError(errorMsg);
        return false;
      } else {
        // Unknown result type
        log("Unknown result type: ${loginResult.runtimeType}");
        setError("Unknown response from authentication service");
        return false;
      }
    } catch (e) {
      final errorMsg = "Error verifying code: ${e.toString()}";
      log("Exception: $errorMsg");
      setError(errorMsg);
      return false;
    } finally {
      // Ensure we're not stuck in loading state if something unexpected happens
      if (loadingState == LoadingState.loading) {
        setIdle();
      }
    }
  }

  Future<void> logout() async {
    return runAsync(() async {
      await _privy.logout();
      _currentUser = null;
    });
  }
}
