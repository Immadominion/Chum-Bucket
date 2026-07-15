import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// Global navigation key for accessing navigator context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Service to handle app lifecycle events and trigger data refreshes
/// Ensures data stays fresh when app comes to foreground
class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService._();
  static final AppLifecycleService _instance = AppLifecycleService._();
  static AppLifecycleService get instance => _instance;

  bool _isInitialized = false;
  String? _currentUserId;
  DateTime? _lastBackgroundTime;

  // Callback for when we need to trigger a data refresh
  VoidCallback? _onShouldRefresh;

  // Callback for navigation from notifications
  static void Function(String challengeId)? onNavigateToChallenge;

  /// Initialize the lifecycle service
  void initialize({String? userId, VoidCallback? onShouldRefresh}) {
    if (_isInitialized) {
      // Just update user if already initialized
      _currentUserId = userId;
      _onShouldRefresh = onShouldRefresh;
      return;
    }

    _currentUserId = userId;
    _onShouldRefresh = onShouldRefresh;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    AppLogger.info('AppLifecycleService initialized');
  }

  /// Update the current user ID
  void setCurrentUser(String? userId) {
    _currentUserId = userId;
  }

  /// Set refresh callback
  void setRefreshCallback(VoidCallback callback) {
    _onShouldRefresh = callback;
  }

  /// Dispose the service
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
    _currentUserId = null;
    _onShouldRefresh = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _onAppPaused() {
    _lastBackgroundTime = DateTime.now();
    AppLogger.debug('App paused at $_lastBackgroundTime');
  }

  void _onAppResumed() {
    AppLogger.debug('App resumed');

    if (_currentUserId == null) {
      AppLogger.debug('No user logged in, skipping refresh');
      return;
    }

    // Check if we were in background for more than 10 seconds
    // This prevents unnecessary refreshes during quick app switches
    if (_lastBackgroundTime != null) {
      final backgroundDuration = DateTime.now().difference(
        _lastBackgroundTime!,
      );
      if (backgroundDuration.inSeconds > 10) {
        AppLogger.info(
          'App was in background for ${backgroundDuration.inSeconds}s - triggering refresh',
        );
        _triggerRefresh();
      } else {
        AppLogger.debug(
          'App was in background for ${backgroundDuration.inSeconds}s - no refresh needed',
        );
      }
    } else {
      // First resume after launch - do a soft refresh
      _triggerRefresh();
    }
  }

  void _triggerRefresh() {
    // Notify callback if set
    _onShouldRefresh?.call();

    // Also do a soft refresh of challenge state
    if (_currentUserId != null) {
      ChallengeStateProvider.instance.softRefresh(_currentUserId!).catchError((
        e,
      ) {
        AppLogger.error('Lifecycle refresh error: $e');
      });
    }
  }

  /// Force a refresh (called when notification is tapped)
  Future<void> forceRefresh() async {
    AppLogger.info('Force refresh triggered (notification tap)');
    if (_currentUserId != null) {
      await ChallengeStateProvider.instance.softRefresh(_currentUserId!);
    }
    _onShouldRefresh?.call();
  }

  /// Navigate to a specific challenge (called from notification tap)
  static void navigateToChallenge(String challengeId) {
    AppLogger.info('Navigating to challenge: $challengeId');
    onNavigateToChallenge?.call(challengeId);
  }
}
