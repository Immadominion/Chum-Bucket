import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chumbucket/core/error_system.dart';

/// Enhanced AuthProvider with comprehensive error handling and logging
class EnhancedAuthProvider extends ChangeNotifier {
  late final Privy _privy;
  late final SupabaseClient _supabase;
  PrivyUser? _currentUser;
  bool _initialized = false;
  String? _lastError;
  bool _isLoading = false;

  EnhancedAuthProvider() {
    _initializeServices();
    _setupErrorLogging();
  }

  // Getters
  PrivyUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitialized => _initialized;
  bool get isLoading => _isLoading;
  SupabaseClient get supabase => _supabase;
  String? get lastError => _lastError;

  final String _loggedInKey = 'isLoggedIn';

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Initialize Privy and Supabase with error handling
  void _initializeServices() {
    try {
      _privy = Privy.init(
        config: PrivyConfig(
          appId: dotenv.env['APP_ID'] ?? '',
          appClientId: dotenv.env['APP_CLIENT_ID'] ?? '',
          logLevel: PrivyLogLevel.debug,
        ),
      );

      _validateConfiguration();

      EnhancedLogger().info('Authentication services initialized', tag: 'Auth');
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Auth Service Initialization',
        severity: ErrorSeverity.critical,
        notifyUser: true,
        userMessage:
            'Failed to initialize authentication. Please restart the app.',
      );
    }
  }

  /// Setup error logging for this provider
  void _setupErrorLogging() {
    // Log provider creation
    EnhancedLogger().debug('EnhancedAuthProvider created', tag: 'Auth');

    // Track provider initialization
    UserActionTracker().trackAction(
      'auth_provider_initialized',
      category: 'System',
    );
  }

  /// Validate environment configuration
  void _validateConfiguration() {
    final issues = <String>[];

    if ((dotenv.env['APP_ID'] ?? dotenv.env['PRIVY_APP_ID'] ?? '').isEmpty) {
      issues.add('APP_ID/PRIVY_APP_ID is missing');
    }

    if ((dotenv.env['APP_CLIENT_ID'] ?? dotenv.env['PRIVY_CLIENT_ID'] ?? '')
        .isEmpty) {
      issues.add('APP_CLIENT_ID/PRIVY_CLIENT_ID is missing');
    }

    if ((dotenv.env['SUPABASE_URL'] ?? '').isEmpty) {
      issues.add('SUPABASE_URL is missing');
    }

    if ((dotenv.env['SUPABASE_ANON_KEY'] ?? '').isEmpty) {
      issues.add('SUPABASE_ANON_KEY is missing');
    }

    if (issues.isNotEmpty) {
      final message = 'Configuration issues: ${issues.join(', ')}';
      EnhancedLogger().warning(message, tag: 'Auth');

      ErrorHandler().handleError(
        Exception('Configuration validation failed'),
        context: 'Auth Configuration',
        severity: ErrorSeverity.high,
        metadata: {'issues': issues},
      );
    }
  }

  /// Enhanced login with comprehensive error handling
  Future<void> login() async {
    PerformanceLogger().startTimer('auth_login');

    try {
      _setLoading(true);
      _clearError();

      // Track login attempt
      UserActionTracker().trackAction(
        'login_attempt',
        category: 'Authentication',
      );

      EnhancedLogger().info('Starting login process', tag: 'Auth');

      // Perform login with error handling
      final result = await ErrorHandler.handleAsync(
        _performPrivyLogin(),
        context: 'Privy Login',
        fallback: null,
        notifyUser: false, // We handle user notification manually
      );

      if (result != null) {
        _currentUser = result;
        await _handleSuccessfulLogin();
      } else {
        await _handleLoginFailure('Login was cancelled or failed');
      }
    } catch (error, stackTrace) {
      await _handleLoginError(error, stackTrace);
    } finally {
      _setLoading(false);
      PerformanceLogger().stopTimer('auth_login');
    }
  }

  /// Perform the actual Privy login
  Future<PrivyUser> _performPrivyLogin() async {
    try {
      // Initialize Privy and get current user
      await _privy.awaitReady();
      final user = _privy.user;

      if (user == null) {
        throw Exception('Login returned null user');
      }
      return user;
    } catch (error) {
      // Convert Privy errors to more specific types
      if (error.toString().contains('cancelled') ||
          error.toString().contains('user_cancelled')) {
        throw AuthCancelledException('User cancelled login');
      } else if (error.toString().contains('network') ||
          error.toString().contains('connection')) {
        throw AuthNetworkException('Network error during login');
      } else {
        throw AuthException('Login failed: ${error.toString()}');
      }
    }
  }

  /// Handle successful login
  Future<void> _handleSuccessfulLogin() async {
    try {
      await saveLoginState();

      // Track successful login
      UserActionTracker().trackAction(
        'login_success',
        category: 'Authentication',
        properties: {'user_id': _currentUser?.id, 'login_method': 'privy'},
      );

      EnhancedLogger().info('User login successful', tag: 'Auth');

      notifyListeners();
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Post-Login Processing',
        severity: ErrorSeverity.medium,
        notifyUser: true,
        userMessage:
            'Login succeeded but some setup failed. Please try refreshing.',
      );
    }
  }

  /// Handle login failure
  Future<void> _handleLoginFailure(String message) async {
    _setError(message);

    UserActionTracker().trackAction(
      'login_failed',
      category: 'Authentication',
      properties: {'reason': 'null_result'},
    );

    EnhancedLogger().warning('Login failed: $message', tag: 'Auth');
    notifyListeners();
  }

  /// Handle login error
  Future<void> _handleLoginError(dynamic error, StackTrace stackTrace) async {
    String userMessage;
    ErrorSeverity severity;

    if (error is AuthCancelledException) {
      userMessage = 'Login was cancelled';
      severity = ErrorSeverity.low;
    } else if (error is AuthNetworkException) {
      userMessage =
          'Network error. Please check your connection and try again.';
      severity = ErrorSeverity.medium;
    } else if (error is AuthException) {
      userMessage = 'Login failed. Please try again.';
      severity = ErrorSeverity.medium;
    } else {
      userMessage = 'An unexpected error occurred during login.';
      severity = ErrorSeverity.high;
    }

    _setError(userMessage);

    ErrorHandler().handleError(
      error,
      stackTrace: stackTrace,
      context: 'User Login',
      severity: severity,
      notifyUser: severity != ErrorSeverity.low,
      userMessage: userMessage,
      metadata: {
        'error_type': error.runtimeType.toString(),
        'login_method': 'privy',
      },
    );

    UserActionTracker().trackAction(
      'login_error',
      category: 'Authentication',
      properties: {
        'error_type': error.runtimeType.toString(),
        'error_message': error.toString(),
      },
    );

    notifyListeners();
  }

  /// Enhanced logout with error handling
  Future<void> logout() async {
    PerformanceLogger().startTimer('auth_logout');

    try {
      _setLoading(true);
      _clearError();

      UserActionTracker().trackAction(
        'logout_attempt',
        category: 'Authentication',
      );

      EnhancedLogger().info('Starting logout process', tag: 'Auth');

      await ErrorHandler.handleAsync(
        _performLogout(),
        context: 'User Logout',
        notifyUser: true,
        userMessage: 'Logout failed. Please try again.',
      );

      _currentUser = null;
      await clearLoginState();

      UserActionTracker().trackAction(
        'logout_success',
        category: 'Authentication',
      );
      EnhancedLogger().info('User logout successful', tag: 'Auth');

      notifyListeners();
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'User Logout',
        severity: ErrorSeverity.medium,
        notifyUser: true,
        userMessage: 'Logout failed. You may need to restart the app.',
      );
    } finally {
      _setLoading(false);
      PerformanceLogger().stopTimer('auth_logout');
    }
  }

  /// Perform the actual logout operation
  Future<void> _performLogout() async {
    await _privy.logout();
  }

  /// Save login state with error handling
  Future<void> saveLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loggedInKey, true);

      EnhancedLogger().debug('Login state saved', tag: 'Auth');
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Save Login State',
        severity: ErrorSeverity.low,
        metadata: {'operation': 'save_login_state'},
      );
    }
  }

  /// Clear login state with error handling
  Future<void> clearLoginState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_loggedInKey);

      EnhancedLogger().debug('Login state cleared', tag: 'Auth');
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Clear Login State',
        severity: ErrorSeverity.low,
        metadata: {'operation': 'clear_login_state'},
      );
    }
  }

  /// Initialize authentication state with error handling
  Future<void> initialize() async {
    if (_initialized) return;

    PerformanceLogger().startTimer('auth_initialize');

    try {
      _setLoading(true);

      EnhancedLogger().info('Initializing authentication', tag: 'Auth');

      // Initialize Supabase
      _supabase = Supabase.instance.client;

      // Check for existing session
      await _restoreAuthenticationSession();

      _initialized = true;

      UserActionTracker().trackAction(
        'auth_initialized',
        category: 'System',
        properties: {'has_user': _currentUser != null},
      );

      EnhancedLogger().info(
        'Authentication initialized successfully',
        tag: 'Auth',
      );
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Auth Initialization',
        severity: ErrorSeverity.high,
        notifyUser: true,
        userMessage:
            'Failed to initialize authentication. Some features may not work.',
      );
    } finally {
      _setLoading(false);
      PerformanceLogger().stopTimer('auth_initialize');
      notifyListeners();
    }
  }

  /// Restore authentication session
  Future<void> _restoreAuthenticationSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool(_loggedInKey) ?? false;

      if (isLoggedIn) {
        try {
          await _privy.awaitReady();
          final user = _privy.user;
          if (user != null) {
            _currentUser = user;
            EnhancedLogger().info(
              'Authentication session restored',
              tag: 'Auth',
            );
          } else {
            await clearLoginState();
            EnhancedLogger().info(
              'No valid session found, cleared state',
              tag: 'Auth',
            );
          }
        } catch (e) {
          EnhancedLogger().warning(
            'Error restoring authentication session: $e',
            tag: 'Auth',
          );
          await clearLoginState();
        }
      }
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Restore Auth Session',
        severity: ErrorSeverity.medium,
        metadata: {'operation': 'restore_session'},
      );
    }
  }

  /// Set error state
  void _setError(String? error) {
    _lastError = error;
  }

  /// Clear error state
  void _clearError() {
    _lastError = null;
  }

  /// Clear error manually
  void clearError() {
    _clearError();
    notifyListeners();
  }

  @override
  void dispose() {
    EnhancedLogger().debug('EnhancedAuthProvider disposing', tag: 'Auth');
    super.dispose();
  }
}

/// Custom authentication exceptions
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

class AuthCancelledException extends AuthException {
  const AuthCancelledException(super.message);
}

class AuthNetworkException extends AuthException {
  const AuthNetworkException(super.message);
}
