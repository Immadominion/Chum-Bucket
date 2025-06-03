import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/providers/base_change_notifier.dart'
    show BaseChangeNotifier, LoadingState;

class AuthProvider extends BaseChangeNotifier {
  late final Privy _privy;
  late final SupabaseClient _supabase;
  PrivyUser? _currentUser;
  bool _initialized = false;

  AuthProvider() {
    _privy = Privy.init(
      config: PrivyConfig(
        appId: dotenv.env['APP_ID'] ?? '',
        appClientId: dotenv.env['APP_CLIENT_ID'] ?? '',
        logLevel: PrivyLogLevel.debug,
      ),
    );

    // Log warning if env variables are missing
    if ((dotenv.env['APP_ID'] ?? dotenv.env['PRIVY_APP_ID'] ?? '').isEmpty ||
        (dotenv.env['APP_CLIENT_ID'] ?? dotenv.env['PRIVY_CLIENT_ID'] ?? '')
            .isEmpty) {
      log(
        'WARNING: Privy credentials are missing. Check your .env file configuration. ',
      );
    }

    if ((dotenv.env['SUPABASE_URL'] ?? '').isEmpty ||
        (dotenv.env['SUPABASE_ANON_KEY'] ?? '').isEmpty) {
      log(
        'WARNING: Supabase credentials are missing. Check your .env file configuration.',
      );
    }
  }

  PrivyUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _initialized;
  SupabaseClient get supabase => _supabase;

  Future<void> initialize() async {
    if (_initialized) return;

    return runAsync(() async {
      try {
        // Initialize Supabase first
        await Supabase.initialize(
          url: dotenv.env['SUPABASE_URL'] ?? '',
          anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
        );

        print(
          "===> ${dotenv.env['APP_CLIENT_ID']} and ${dotenv.env['APP_ID']} Secrets",
        );

        // Now it's safe to get the instance
        _supabase = Supabase.instance.client;

        // Then initialize Privy
        await _privy.awaitReady();
        _currentUser = _privy.user;

        // If user is already logged in, sync with Supabase
        if (_currentUser != null) {
          await _syncUserWithSupabase(_currentUser!);
        }

        _initialized = true;
      } catch (e) {
        log('Failed to initialize Auth services: ${e.toString()}');
        rethrow;
      }
    }, resetToIdle: true);
  }

  // Helper method to safely extract error message from Failure objects
  String _extractErrorMessage(dynamic failure) {
    if (failure == null) return "Unknown error";

    log('Failure object structure: ${failure.runtimeType} - ${failure}');

    try {
      if (failure is Failure) {
        // Try to access the error property in multiple ways
        dynamic error;

        try {
          // Method 1: Direct property access
          error = failure.error;
          log('Direct error access: $error');
        } catch (e) {
          log('Direct error access failed: $e');
        }

        try {
          // Method 2: Try to access via reflection or toString parsing
          final failureStr = failure.toString();
          log('Failure toString: $failureStr');

          // Look for common error patterns
          if (failureStr.contains('PrivyException')) {
            final regex = RegExp(r'PrivyException:\s*(.+)');
            final match = regex.firstMatch(failureStr);
            if (match != null) {
              error = match.group(1);
            }
          }
        } catch (e) {
          log('String parsing failed: $e');
        }

        if (error != null) {
          final errorStr = error.toString();
          log('Extracted error: $errorStr');

          // Check for specific error messages and provide helpful responses
          if (errorStr.toLowerCase().contains('invalid app') ||
              errorStr.toLowerCase().contains('unauthorized')) {
            return "Invalid Privy credentials. Please check your APP_ID and APP_SECRET in .env file.";
          }
          if (errorStr.toLowerCase().contains('network') ||
              errorStr.toLowerCase().contains('connection')) {
            return "Network error. Please check your internet connection.";
          }
          if (errorStr.toLowerCase().contains('rate limit')) {
            return "Too many requests. Please wait a moment before trying again.";
          }
          if (errorStr.toLowerCase().contains('invalid email')) {
            return "Invalid email format. Please enter a valid email address.";
          }

          return errorStr;
        }
      }

      // Fallback to toString
      final str = failure.toString();
      return str.isEmpty ? "Unknown authentication error" : str;
    } catch (e) {
      log('Error extracting failure message: $e');
      return "Authentication service error";
    }
  }

  Future<void> _syncUserWithSupabase(PrivyUser privyUser) async {
    try {
      // Set the current_privy_id in the database session
      await _supabase.rpc(
        'set_current_privy_id',
        params: {'privy_id': privyUser.id},
      );

      // Upsert user in Supabase
      final response =
          await _supabase
              .from('users')
              .upsert({
                'privy_id': privyUser.id,
                'email':
                    privyUser.id, // Assuming email is stored in privyUser.id
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
              })
              .select()
              .single();

      log('User synced with Supabase: $response');
    } catch (e) {
      log('Error syncing user with Supabase: ${e.toString()}');
      // Don't throw here - we don't want to break auth flow if DB sync fails
    }
  }

  Future<bool> sendEmailCode(String email) async {
    // Validate email format
    if (!_isValidEmail(email)) {
      setError("Please enter a valid email address");
      return false;
    }

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
      if (loadingState == LoadingState.loading) {
        setIdle();
      }
    }
  }

  Future<bool> verifyEmailCode(String email, String code) async {
    // Validate inputs
    if (!_isValidEmail(email)) {
      setError("Please enter a valid email address");
      return false;
    }

    if (code.trim().isEmpty) {
      setError("Please enter the verification code");
      return false;
    }

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
        code: code.trim(),
        email: email.trim().toLowerCase(),
      );

      log('verifyEmailCode result type: ${loginResult.runtimeType}');
      log('verifyEmailCode full result: $loginResult');

      if (loginResult is Success<PrivyUser>) {
        _currentUser = loginResult.value;

        // Sync with Supabase after successful login
        await _syncUserWithSupabase(_currentUser!);

        setSuccess();
        return true;
      } else if (loginResult is Failure) {
        final errorMessage = _extractErrorMessage(loginResult);
        final errorMsg = "Verification failed: $errorMessage";
        log("Error: $errorMsg");
        setError(errorMsg);
        return false;
      } else {
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
      if (loadingState == LoadingState.loading) {
        setIdle();
      }
    }
  }

  Future<void> logout() async {
    return runAsync(() async {
      try {
        await _privy.logout();
        _currentUser = null;
        // Note: We don't sign out from Supabase as it's just used for data storage
        log('User logged out successfully');
      } catch (e) {
        log('Error during logout: ${e.toString()}');
        // Clear user anyway to prevent stuck state
        _currentUser = null;
        rethrow;
      }
    });
  }

  // Helper method to test Privy configuration
  Future<bool> testConfiguration() async {
    try {
      log('Testing Privy configuration...');

      if (!_initialized) {
        await initialize();
      }

      // Try to get Privy status/info without triggering actual auth
      log('Privy initialization successful');
      return true;
    } catch (e) {
      log('Configuration test failed: ${e.toString()}');
      return false;
    }
  }

  // Helper method to validate email format
  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // Helper method to get user data from Supabase
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (_currentUser == null) return null;

    try {
      final response =
          await _supabase
              .from('users')
              .select()
              .eq('privy_id', _currentUser!.id)
              .single();

      return response;
    } catch (e) {
      log('Error fetching user profile: ${e.toString()}');
      return null;
    }
  }

  // Helper method to update user profile in Supabase
  Future<bool> updateUserProfile(Map<String, dynamic> updates) async {
    if (_currentUser == null) return false;

    try {
      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('users')
          .update(updates)
          .eq('privy_id', _currentUser!.id);

      return true;
    } catch (e) {
      log('Error updating user profile: ${e.toString()}');
      return false;
    }
  }
}
