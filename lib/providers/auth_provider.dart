import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/providers/base_change_notifier.dart'
    show BaseChangeNotifier, LoadingState;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chumbucket/providers/profile_provider.dart';
import 'package:chumbucket/providers/wallet_provider.dart';

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

  final String _loggedInKey = 'isLoggedIn';

  Future<void> saveLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, true);
  }

  /// Clears the saved login state
  Future<void> clearLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loggedInKey);
    log('Cleared saved login state');
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  Future<void> initialize() async {
    if (_initialized) {
      log('AuthProvider already initialized, skipping...');
      return;
    }

    return runAsync(() async {
      try {
        // Supabase already initialized in main.dart, just assign client
        _supabase = Supabase.instance.client;

        // Then initialize Privy
        await _privy.awaitReady();
        _currentUser = _privy.user;

        // Check if we have saved login state but no current user
        // This can happen if the app was closed and reopened
        final wasLoggedIn = await isLoggedIn();
        if (wasLoggedIn && _currentUser == null) {
          log(
            'Found saved login state but no active user, attempting to restore session...',
          );
          try {
            // Try to refresh the authentication session
            // The SDK might not have a direct refresh method, so we use what's available
            await _privy.awaitReady(); // Re-initialize the SDK
            _currentUser = _privy.user; // Check if user is still authenticated

            if (_currentUser != null) {
              log('Successfully restored user session after app restart');
            } else {
              log('Failed to restore user session, will need to login again');
              // Clear the saved login state since it's invalid
              await clearLoginState();
            }
          } catch (e) {
            log('Error restoring authentication session: $e');
            // Clear the saved login state since it's invalid
            await clearLoginState();
          }
        }

        // If user is already logged in, sync with Supabase
        if (_currentUser != null) {
          await _syncUserWithSupabase(_currentUser!);
        }

        _initialized = true;
        log('AuthProvider initialized successfully');
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

  Future<bool> _syncUserWithSupabase(PrivyUser privyUser) async {
    try {
      final emailAccount =
          privyUser.linkedAccounts.firstWhere(
                (account) => account is EmailAccount && account.type == 'email',
                orElse:
                    () => throw Exception('No email account found for user'),
              )
              as EmailAccount;
      if (emailAccount.emailAddress.isEmpty) {
        throw Exception('Email address is empty');
      }
      final email = emailAccount.emailAddress;

      log('Syncing user with privy_id: ${privyUser.id}, email: $email');

      // Call the stored procedure
      await _supabase.rpc(
        'sync_user',
        params: {'p_privy_id': privyUser.id, 'p_email': email},
      );

      log('User synced successfully');
      return true;
    } catch (e) {
      log('Error syncing user with Supabase: $e');
      if (e is PostgrestException) {
        log(
          'Postgrest details: code=${e.code}, message=${e.message}, details=${e.details}',
        );
      }
      throw Exception('Failed to sync user: $e');
    }
  }

  Future<bool> sendEmailCode(String email) async {
    if (!await hasInternetConnection()) {
      setError(
        "No internet connection. Please check your network and try again.",
      );
      return false;
    }

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
    if (!await hasInternetConnection()) {
      setError(
        "No internet connection. Please check your network and try again.",
      );
      return false;
    }

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

        // Assign and persist a profile picture for the user
        final profileProvider = ProfileProvider();
        final pfpPath = await profileProvider.getUserPfp(_currentUser!.id);

        // Optionally update the profile in the database with the PFP
        // This would require your database to have a column for storing the PFP path
        // If you want to store it in the database, you can call:
        // await profileProvider.updateUserProfileWithPfp(userId, {'full_name': name, 'bio': ''}, pfpPath);

        // Fetch user profile and ensure it has the PFP included
        await profileProvider.fetchUserProfileWithPfp(_currentUser!.id);

        // Create wallet for the user immediately after successful login
        // This ensures they have a wallet ready to use when they enter the app
        try {
          final walletProvider = WalletProvider();
          await walletProvider.ensureWalletExists(this);
          log('Wallet initialized during authentication');
        } catch (e) {
          log('Warning: Failed to initialize wallet during login: $e');
          // Continue with login even if wallet fails
        }

        // Save login state
        await saveLoginState();

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

        // Clear login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_loggedInKey);

        log('User logged out successfully');
      } catch (e) {
        log('Error during logout: ${e.toString()}');
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

  @override
  Future<void> clearUserData() async {
    await super.clearUserData();
    _currentUser = null;
    _initialized = false;
    notifyListeners();
  }
}
