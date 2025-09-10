/// API Documentation
/// 
/// This file contains comprehensive documentation for all core services
/// and APIs used in the Chumbucket application.

## Error Handling System

### ErrorHandler

**Purpose**: Central error handling service that provides consistent error management across the application.

**Key Features**:
- Error severity classification
- Centralized error logging
- User notification management
- Error analytics and reporting
- Stream-based error communication

#### Methods

##### handleError
```dart
void handleError(
  dynamic error, {
  StackTrace? stackTrace,
  String? context,
  ErrorSeverity severity = ErrorSeverity.medium,
  bool notifyUser = false,
  String? userMessage,
  Map<String, dynamic>? metadata,
})
```

**Parameters**:
- `error`: The error object to handle
- `stackTrace`: Optional stack trace for debugging
- `context`: Context where the error occurred (e.g., 'User Login', 'Data Fetch')
- `severity`: Error severity level (low, medium, high, critical)
- `notifyUser`: Whether to show user notification
- `userMessage`: User-friendly error message
- `metadata`: Additional error context data

**Usage Examples**:
```dart
// Basic error handling
ErrorHandler().handleError(
  exception,
  context: 'User Authentication',
  severity: ErrorSeverity.high,
);

// With user notification
ErrorHandler().handleError(
  networkError,
  context: 'Data Sync',
  severity: ErrorSeverity.medium,
  notifyUser: true,
  userMessage: 'Failed to sync data. Please try again.',
);

// With metadata for analytics
ErrorHandler().handleError(
  apiError,
  context: 'API Call',
  metadata: {
    'endpoint': '/api/users',
    'method': 'GET',
    'status_code': 500,
  },
);
```

##### handleAsync
```dart
static Future<T?> handleAsync<T>(
  Future<T> future, {
  String? context,
  T? fallback,
  bool notifyUser = false,
  String? userMessage,
})
```

**Purpose**: Handles errors from async operations with optional fallback values.

**Usage Examples**:
```dart
// With fallback value
final users = await ErrorHandler.handleAsync(
  userService.getUsers(),
  context: 'Load Users',
  fallback: <User>[],
);

// With user notification
final result = await ErrorHandler.handleAsync(
  apiCall(),
  context: 'API Request',
  notifyUser: true,
  userMessage: 'Failed to load data',
);
```

#### Properties

##### errorStream
```dart
Stream<AppError> get errorStream
```

**Purpose**: Stream of all errors handled by the ErrorHandler for real-time error monitoring.

**Usage**:
```dart
// Listen to all errors
ErrorHandler().errorStream.listen((error) {
  print('Error occurred: ${error.message}');
  analytics.reportError(error);
});

// Filter by severity
ErrorHandler().errorStream
  .where((error) => error.severity == ErrorSeverity.critical)
  .listen((criticalError) {
    // Handle critical errors immediately
    notifyAdministrators(criticalError);
  });
```

---

## Logging System

### EnhancedLogger

**Purpose**: Advanced logging system with structured output, multiple targets, and performance tracking.

#### Methods

##### Log Level Methods
```dart
void debug(String message, {String? tag, Map<String, dynamic>? metadata})
void info(String message, {String? tag, Map<String, dynamic>? metadata})
void warning(String message, {String? tag, Map<String, dynamic>? metadata})
void error(String message, {String? tag, Map<String, dynamic>? metadata})
void critical(String message, {String? tag, Map<String, dynamic>? metadata})
```

**Parameters**:
- `message`: The log message
- `tag`: Optional tag for categorization (e.g., 'Auth', 'Network', 'UI')
- `metadata`: Additional structured data

**Usage Examples**:
```dart
// Basic logging
EnhancedLogger().info('User logged in successfully', tag: 'Auth');

// With metadata
EnhancedLogger().debug(
  'API request completed',
  tag: 'Network',
  metadata: {
    'endpoint': '/api/users',
    'duration_ms': 250,
    'status': 200,
  },
);

// Error logging
EnhancedLogger().error(
  'Database connection failed',
  tag: 'Database',
  metadata: {
    'error_code': 'CONN_TIMEOUT',
    'retry_count': 3,
  },
);
```

### UserActionTracker

**Purpose**: Tracks user actions and interactions for analytics and debugging.

#### Methods

##### trackAction
```dart
void trackAction(
  String action, {
  String? category,
  Map<String, dynamic>? properties,
})
```

**Parameters**:
- `action`: Name of the action (e.g., 'login_attempt', 'button_pressed')
- `category`: Action category (e.g., 'Authentication', 'Navigation')
- `properties`: Additional action properties

**Usage Examples**:
```dart
// Basic action tracking
UserActionTracker().trackAction('login_attempt', category: 'Authentication');

// With properties
UserActionTracker().trackAction(
  'challenge_created',
  category: 'Challenges',
  properties: {
    'challenge_type': 'fitness',
    'participant_count': 5,
    'duration_days': 30,
  },
);

// UI interaction tracking
UserActionTracker().trackAction(
  'tab_switched',
  category: 'Navigation',
  properties: {
    'from_tab': 'home',
    'to_tab': 'challenges',
  },
);
```

### PerformanceLogger

**Purpose**: Tracks performance metrics and timing information.

#### Methods

##### startTimer / stopTimer
```dart
void startTimer(String operation)
void stopTimer(String operation)
```

**Usage**:
```dart
// Track operation performance
PerformanceLogger().startTimer('data_load');
await loadData();
PerformanceLogger().stopTimer('data_load');

// Track UI performance
PerformanceLogger().startTimer('screen_build');
// ... build expensive UI
PerformanceLogger().stopTimer('screen_build');
```

---

## Authentication System

### EnhancedAuthProvider

**Purpose**: Enhanced authentication provider with comprehensive error handling and logging.

#### Properties

```dart
PrivyUser? get currentUser;          // Currently authenticated user
bool get isAuthenticated;            // Whether user is logged in
bool get isInitialized;              // Whether provider is initialized
bool get isLoading;                  // Current loading state
SupabaseClient get supabase;         // Supabase client instance
String? get lastError;               // Last error message
```

#### Methods

##### initialize
```dart
Future<void> initialize()
```

**Purpose**: Initializes the authentication system and restores user session.

**Usage**:
```dart
final authProvider = EnhancedAuthProvider();
await authProvider.initialize();
```

##### login
```dart
Future<void> login()
```

**Purpose**: Initiates user login process with comprehensive error handling.

**Features**:
- Automatic error classification
- User-friendly error messages
- Retry mechanisms
- Performance tracking
- Analytics integration

**Usage**:
```dart
try {
  await authProvider.login();
  // Login successful
} catch (e) {
  // Error already handled by provider
  // Check authProvider.lastError for details
}
```

##### logout
```dart
Future<void> logout()
```

**Purpose**: Logs out the current user and cleans up session.

**Features**:
- Session cleanup
- State management
- Error handling
- Analytics tracking

**Usage**:
```dart
await authProvider.logout();
```

#### Error Handling

The EnhancedAuthProvider includes specialized error types:

```dart
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
}

class AuthCancelledException extends AuthException {
  const AuthCancelledException(String message);
}

class AuthNetworkException extends AuthException {
  const AuthNetworkException(String message);
}
```

**Integration with Error System**:
```dart
// Provider automatically handles errors
authProvider.login(); // Errors logged and user notified automatically

// Manual error handling
authProvider.errorStream.listen((error) {
  if (error is AuthException) {
    // Handle auth-specific errors
    handleAuthError(error);
  }
});
```

---

## Best Practices

### Error Handling

1. **Use appropriate error severity**:
   ```dart
   // Critical: App-breaking errors
   ErrorHandler().handleError(error, severity: ErrorSeverity.critical);
   
   // High: Feature-breaking errors
   ErrorHandler().handleError(error, severity: ErrorSeverity.high);
   
   // Medium: Recoverable errors
   ErrorHandler().handleError(error, severity: ErrorSeverity.medium);
   
   // Low: Minor issues
   ErrorHandler().handleError(error, severity: ErrorSeverity.low);
   ```

2. **Provide context for debugging**:
   ```dart
   ErrorHandler().handleError(
     error,
     context: 'User Profile Update',
     metadata: {
       'user_id': user.id,
       'field': 'email',
       'new_value': newEmail,
     },
   );
   ```

3. **Use user-friendly messages**:
   ```dart
   ErrorHandler().handleError(
     technicalError,
     notifyUser: true,
     userMessage: 'Failed to update profile. Please try again.',
   );
   ```

### Logging

1. **Use appropriate log levels**:
   - `debug`: Detailed debugging information
   - `info`: General operational information
   - `warning`: Potential issues that don't break functionality
   - `error`: Error conditions that affect functionality
   - `critical`: Critical errors that may crash the app

2. **Include relevant metadata**:
   ```dart
   EnhancedLogger().info(
     'User action completed',
     tag: 'UserActions',
     metadata: {
       'action': 'profile_update',
       'duration_ms': stopwatch.elapsedMilliseconds,
       'success': true,
     },
   );
   ```

3. **Use consistent tagging**:
   - `Auth`: Authentication-related logs
   - `Network`: Network requests and responses
   - `UI`: User interface interactions
   - `Performance`: Performance-related metrics
   - `Database`: Database operations

### Performance Tracking

1. **Track critical operations**:
   ```dart
   PerformanceLogger().startTimer('critical_operation');
   await performCriticalOperation();
   PerformanceLogger().stopTimer('critical_operation');
   ```

2. **Monitor user interactions**:
   ```dart
   UserActionTracker().trackAction(
     'feature_used',
     category: 'Engagement',
     properties: {'feature': 'challenges', 'session_id': sessionId},
   );
   ```

### Integration Examples

#### Provider Setup
```dart
// In main.dart or app initialization
MultiProvider(
  providers: [
    ChangeNotifierProvider<EnhancedAuthProvider>(
      create: (_) => EnhancedAuthProvider()..initialize(),
    ),
    // Other providers...
  ],
  child: MyApp(),
)
```

#### Widget Integration
```dart
// In widget build method
Consumer<EnhancedAuthProvider>(
  builder: (context, auth, child) {
    if (auth.isLoading) return LoadingWidget();
    if (!auth.isAuthenticated) return LoginScreen();
    return AuthenticatedContent();
  },
)
```

#### Error Monitoring
```dart
// Global error monitoring
void setupErrorMonitoring() {
  ErrorHandler().errorStream.listen((error) {
    // Send to analytics
    FirebaseAnalytics.instance.logEvent(
      name: 'app_error',
      parameters: {
        'error_type': error.runtimeType.toString(),
        'error_message': error.message,
        'severity': error.severity.toString(),
      },
    );
    
    // Send to crash reporting
    if (error.severity == ErrorSeverity.critical) {
      FirebaseCrashlytics.instance.recordError(
        error.error,
        error.stackTrace,
        reason: error.context,
      );
    }
  });
}
```
