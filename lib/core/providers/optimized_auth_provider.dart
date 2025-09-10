import 'dart:developer';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chumbucket/core/providers/providers.dart';

/// Optimized AuthProvider with enhanced state management
class OptimizedAuthProvider extends EnhancedBaseChangeNotifier
    with ProviderPerformanceMixin, ErrorRecoveryMixin {
  @override
  String get providerName => 'OptimizedAuthProvider';

  late final Privy _privy;
  late final SupabaseClient _supabase;
  PrivyUser? _currentUser;
  bool _initialized = false;

  static const String _loggedInKey = 'isLoggedIn';
  static const String _initializeCacheKey = 'auth_initialize';
  static const String _loginCacheKey = 'auth_login';

  OptimizedAuthProvider() {
    _initializePrivy();
  }

  // Getters with performance optimization
  PrivyUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _initialized;
  SupabaseClient get supabase => _supabase;

  void _initializePrivy() {
    _privy = Privy.init(
      config: PrivyConfig(
        appId: dotenv.env['APP_ID'] ?? '',
        appClientId: dotenv.env['APP_CLIENT_ID'] ?? '',
        logLevel: PrivyLogLevel.debug,
      ),
    );

    _validateConfiguration();
  }

  void _validateConfiguration() {
    if ((dotenv.env['APP_ID'] ?? dotenv.env['PRIVY_APP_ID'] ?? '').isEmpty ||
        (dotenv.env['APP_CLIENT_ID'] ?? dotenv.env['PRIVY_CLIENT_ID'] ?? '')
            .isEmpty) {
      log(
        'WARNING: Privy credentials are missing. Check your .env file configuration.',
      );
    }

    if ((dotenv.env['SUPABASE_URL'] ?? '').isEmpty ||
        (dotenv.env['SUPABASE_ANON_KEY'] ?? '').isEmpty) {
      log(
        'WARNING: Supabase credentials are missing. Check your .env file configuration.',
      );
    }
  }

  /// Initialize authentication with enhanced error recovery
  Future<void> initialize() async {
    if (_initialized) {
      log('AuthProvider already initialized, skipping...');
      return;
    }

    await executeWithRecovery(
      operationName: 'initialize',
      operation: () async {
        return await timeOperation('initialize_auth', () async {
          // Initialize Supabase client
          _supabase = Supabase.instance.client;

          // Initialize Privy
          await _privy.awaitReady();
          _currentUser = _privy.user;

          // Check saved login state
          await _restoreSessionIfNeeded();

          _initialized = true;
          log('AuthProvider initialized successfully');
        }, warningThreshold: const Duration(seconds: 5));
      },
      config: ErrorRecoveryConfig(
        strategy: ErrorRecoveryStrategy.retry,
        maxRetries: 2,
        retryDelay: const Duration(seconds: 1),
        refreshAction: () async {
          // Clear cache and retry
          clearCache(_initializeCacheKey);
        },
      ),
    );
  }

  /// Restore session with proper error handling
  Future<void> _restoreSessionIfNeeded() async {
    final wasLoggedIn = await isLoggedIn();
    if (wasLoggedIn && _currentUser == null) {
      log(
        'Found saved login state but no active user, attempting to restore session...',
      );

      try {
        await _privy.awaitReady();
        _currentUser = _privy.user;

        if (_currentUser != null) {
          log('Successfully restored user session after app restart');
        } else {
          log('Failed to restore user session, clearing saved state');
          await clearLoginState();
        }
      } catch (e) {
        log('Session restoration failed: $e');
        await clearLoginState();
      }
    }
  }

  /// Enhanced login with performance monitoring and error recovery
  Future<bool> loginWithEmail(String email) async {
    final result = await executeWithRecovery<bool>(
      operationName: 'login_with_email',
      operation: () async {
        return await timeOperation('email_login', () async {
          final result = await _privy.email.sendCode(email);

          if (result is Success) {
            log('Email code sent successfully for: $email');
            return true;
          } else {
            throw Exception('Failed to send email code: $result');
          }
        }, warningThreshold: const Duration(seconds: 10));
      },
      config: ErrorRecoveryConfig(
        strategy: ErrorRecoveryStrategy.retry,
        maxRetries: 2,
        retryDelay: const Duration(seconds: 3),
        fallbackAction: () async {
          // Clear any cached data that might be causing issues
          clearCache(_loginCacheKey);
        },
      ),
      context: {'email': email},
    );

    return result ?? false;
  }

  /// Enhanced OTP verification
  Future<bool> verifyOtp(String otp, String email) async {
    final result = await executeWithRecovery<bool>(
      operationName: 'verify_otp',
      operation: () async {
        return await timeOperation('otp_verification', () async {
          final loginResult = await _privy.email.loginWithCode(
            code: otp.trim(),
            email: email.trim().toLowerCase(),
          );

          if (loginResult is Success<PrivyUser>) {
            _currentUser = loginResult.value;
            await saveLoginState();
            log('OTP verification successful for email: $email');
            return true;
          } else {
            throw Exception('OTP verification failed: $loginResult');
          }
        }, warningThreshold: const Duration(seconds: 5));
      },
      config: ErrorRecoveryConfig(
        strategy: ErrorRecoveryStrategy.retry,
        maxRetries: 1, // OTP should not be retried too many times
        retryDelay: const Duration(seconds: 2),
      ),
      context: {'email': email, 'otp': otp},
    );

    return result ?? false;
  }

  /// Enhanced logout with cleanup
  Future<void> logout() async {
    await executeWithRecovery(
      operationName: 'logout',
      operation: () async {
        return await timeOperation('logout', () async {
          await _privy.logout();
          _currentUser = null;
          await clearLoginState();

          // Clear all cached data
          clearCache();

          log('Logout successful');
        });
      },
      config: ErrorRecoveryConfig(
        strategy: ErrorRecoveryStrategy.refresh,
        maxRetries: 1,
        refreshAction: () async {
          // Force clear state even if logout fails
          _currentUser = null;
          await clearLoginState();
          clearCache();
        },
      ),
    );
  }

  /// Cached login state management
  Future<void> saveLoginState() async {
    await runAsync(
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_loggedInKey, true);
        log('Login state saved');
      },
      enableCaching: true,
      cacheKey: 'save_login_state',
    );
  }

  Future<void> clearLoginState() async {
    await runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_loggedInKey);
      log('Login state cleared');
    });
  }

  Future<bool> isLoggedIn() async {
    final result = await runAsync(
      () async {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(_loggedInKey) ?? false;
      },
      enableCaching: true,
      cacheKey: 'is_logged_in',
      cacheTtl: const Duration(minutes: 5),
    );

    return result ?? false;
  }

  /// Get user profile with caching
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (_currentUser == null) return null;

    return await runAsync<Map<String, dynamic>?>(
      () async {
        final response =
            await _supabase
                .from('user_profiles')
                .select()
                .eq('privy_id', _currentUser!.id)
                .maybeSingle();

        return response;
      },
      operationName: 'get_user_profile',
      enableCaching: true,
      cacheKey: 'user_profile_${_currentUser!.id}',
      cacheTtl: const Duration(minutes: 15),
    );
  }

  /// Create user profile
  Future<bool> createUserProfile({
    required String username,
    String? displayName,
    String? profilePicture,
  }) async {
    if (_currentUser == null) return false;

    final result = await executeWithRecovery<bool>(
      operationName: 'create_user_profile',
      operation: () async {
        final profileData = {
          'privy_id': _currentUser!.id,
          'username': username,
          'display_name': displayName ?? username,
          'profile_picture': profilePicture,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };

        await _supabase.from('user_profiles').insert(profileData);

        // Clear cached profile data to force refresh
        clearCache('user_profile_${_currentUser!.id}');

        log('User profile created successfully for ${_currentUser!.id}');
        return true;
      },
      config: ErrorRecoveryConfig(
        strategy: ErrorRecoveryStrategy.retry,
        maxRetries: 2,
        retryDelay: const Duration(seconds: 2),
      ),
      context: {
        'username': username,
        'displayName': displayName,
        'profilePicture': profilePicture,
      },
    );

    return result ?? false;
  }

  /// Enhanced error recovery configuration
  @override
  ErrorRecoveryConfig getDefaultErrorRecoveryConfig() {
    return ErrorRecoveryConfig(
      strategy: ErrorRecoveryStrategy.retry,
      maxRetries: 3,
      retryDelay: const Duration(seconds: 2),
      exponentialBackoff: true,
      refreshAction: () async {
        // Re-initialize if needed
        if (!_initialized) {
          await initialize();
        }
      },
      resetAction: () {
        // Reset to clean state
        _currentUser = null;
        _initialized = false;
        clearCache();
      },
    );
  }

  @override
  void dispose() {
    log('OptimizedAuthProvider disposing...');
    super.dispose();
  }
}
