/// Widget Documentation
/// 
/// This file contains comprehensive documentation for all reusable widgets
/// in the Chumbucket application. Each widget is documented with:
/// - Purpose and use cases
/// - Parameters and their descriptions
/// - Usage examples
/// - Best practices and considerations

## Error Handling Widgets

### ErrorBoundary

**Purpose**: Catches and handles errors that occur within its child widget tree, providing graceful error recovery and user-friendly error displays.

**Use Cases**:
- Wrapping entire screens to catch unexpected errors
- Protecting critical UI components from crashing the app
- Providing fallback UI when child widgets encounter errors
- Logging errors for debugging and analytics

**Parameters**:
```dart
class ErrorBoundary extends StatefulWidget {
  /// The child widget to wrap and protect from errors
  final Widget child;
  
  /// Optional callback when an error occurs
  /// Receives the error and stack trace
  final void Function(AppError error)? onError;
  
  /// Optional custom error widget to display
  /// If null, uses DefaultErrorWidget
  final Widget Function(AppError error)? errorBuilder;
  
  /// Whether to show detailed error information
  /// Should be false in production builds
  final bool showDetails;
}
```

**Usage Examples**:
```dart
// Basic usage - wraps entire screen
ErrorBoundary(
  child: MyScreen(),
)

// With custom error handler
ErrorBoundary(
  onError: (error) {
    // Log to analytics
    analytics.logError(error);
    
    // Show user notification
    showErrorSnackBar(error.message);
  },
  child: CriticalWidget(),
)

// With custom error UI
ErrorBoundary(
  errorBuilder: (error) => CustomErrorWidget(error: error),
  child: FeatureWidget(),
)
```

**Best Practices**:
- Place at screen level for broad error protection
- Use custom error builders for feature-specific error handling
- Always handle errors gracefully without exposing technical details
- Log errors for debugging but show user-friendly messages

---

### DefaultErrorWidget

**Purpose**: Provides a user-friendly error display with retry functionality and optional error details.

**Use Cases**:
- Displaying errors caught by ErrorBoundary
- Showing network or API errors to users
- Providing retry mechanisms for failed operations
- Debug error information in development builds

**Parameters**:
```dart
class DefaultErrorWidget extends StatelessWidget {
  /// The error to display
  final AppError error;
  
  /// Callback when retry button is pressed
  final VoidCallback? onRetry;
  
  /// Whether to show detailed error information
  final bool showDetails;
  
  /// Custom title for the error display
  final String? title;
  
  /// Custom message to show instead of error message
  final String? customMessage;
}
```

**Usage Examples**:
```dart
// Basic error display
DefaultErrorWidget(
  error: appError,
  onRetry: () => refetchData(),
)

// Custom error message
DefaultErrorWidget(
  error: appError,
  title: 'Connection Failed',
  customMessage: 'Please check your internet connection',
  onRetry: () => retryConnection(),
)

// Development error with details
DefaultErrorWidget(
  error: appError,
  showDetails: kDebugMode,
  onRetry: () => debugRetry(),
)
```

---

### NetworkErrorWidget

**Purpose**: Specialized error widget for network-related failures with connection-specific messaging and recovery options.

**Parameters**:
```dart
class NetworkErrorWidget extends StatelessWidget {
  /// The network error that occurred
  final Object error;
  
  /// Callback when retry button is pressed
  final VoidCallback? onRetry;
  
  /// Custom message for the network error
  final String? message;
  
  /// Whether to show connection troubleshooting tips
  final bool showTroubleshooting;
}
```

**Usage Examples**:
```dart
// Basic network error
NetworkErrorWidget(
  error: networkError,
  onRetry: () => refetchNetworkData(),
)

// With troubleshooting tips
NetworkErrorWidget(
  error: networkError,
  showTroubleshooting: true,
  onRetry: () => retryNetworkCall(),
)
```

---

### AsyncErrorHandler

**Purpose**: Handles errors from asynchronous operations (Futures) with loading states and error recovery.

**Parameters**:
```dart
class AsyncErrorHandler<T> extends StatefulWidget {
  /// The future to execute and handle
  final Future<T> Function()? future;
  
  /// Builder function that receives the async snapshot
  final Widget Function(BuildContext context, T data) builder;
  
  /// Widget to show while loading
  final Widget? loadingWidget;
  
  /// Custom error widget builder
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  
  /// Whether to automatically execute the future on build
  final bool autoExecute;
}
```

**Usage Examples**:
```dart
// Handle async API call
AsyncErrorHandler<List<User>>(
  future: () => userService.getUsers(),
  builder: (context, users) => UserList(users: users),
  loadingWidget: CircularProgressIndicator(),
)

// Manual execution control
AsyncErrorHandler<String>(
  future: () => apiService.getData(),
  autoExecute: false,
  builder: (context, data) => Text(data),
  errorBuilder: (context, error) => CustomErrorWidget(error),
)
```

---

## Performance Widgets

### MemoryEfficientWidget

**Purpose**: Abstract base class for widgets that need efficient memory management with automatic resource cleanup.

**Use Cases**:
- Heavy widgets with expensive resources (images, animations)
- Widgets that manage subscriptions or listeners
- Components that need lifecycle-aware cleanup
- Performance-critical UI components

**Implementation Pattern**:
```dart
class MyWidget extends MemoryEfficientWidget {
  @override
  MemoryEfficientState<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends MemoryEfficientState<MyWidget> {
  late StreamSubscription subscription;
  
  @override
  void initState() {
    super.initState();
    subscription = someStream.listen(onData);
  }
  
  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return MyWidgetUI();
  }
}
```

---

### LazyLoadingListView

**Purpose**: Efficiently renders large lists by loading items on demand with pagination support.

**Parameters**:
```dart
class LazyLoadingListView<T> extends StatefulWidget {
  /// Function to load more items when needed
  final Future<List<T>> Function(int offset, int limit) loadMore;
  
  /// Builder for individual list items
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  
  /// Number of items to load per page
  final int pageSize;
  
  /// Initial items to display
  final List<T> initialItems;
  
  /// Loading indicator widget
  final Widget? loadingIndicator;
  
  /// Whether there are more items to load
  final bool hasMore;
  
  /// Callback when loading state changes
  final void Function(bool isLoading)? onLoadingChanged;
}
```

**Usage Examples**:
```dart
// Basic lazy loading list
LazyLoadingListView<User>(
  loadMore: (offset, limit) => userService.getUsers(offset, limit),
  itemBuilder: (context, user, index) => UserTile(user: user),
  pageSize: 20,
)

// With custom loading indicator
LazyLoadingListView<Post>(
  loadMore: (offset, limit) => postService.getPosts(offset, limit),
  itemBuilder: (context, post, index) => PostCard(post: post),
  loadingIndicator: CustomLoadingSpinner(),
  onLoadingChanged: (isLoading) => setState(() => _isLoading = isLoading),
)
```

---

### PerformanceMonitor

**Purpose**: Monitors widget performance metrics including build time, frame rate, and memory usage.

**Parameters**:
```dart
class PerformanceMonitor extends StatefulWidget {
  /// Child widget to monitor
  final Widget child;
  
  /// Name identifier for this monitor
  final String name;
  
  /// Whether to log performance metrics
  final bool enableLogging;
  
  /// Whether to show performance overlay in debug mode
  final bool showOverlay;
  
  /// Callback when performance issues are detected
  final void Function(PerformanceMetrics metrics)? onPerformanceIssue;
}
```

**Usage Examples**:
```dart
// Monitor expensive widget
PerformanceMonitor(
  name: 'ExpensiveWidget',
  enableLogging: kDebugMode,
  showOverlay: true,
  child: ExpensiveAnimationWidget(),
)

// Production monitoring
PerformanceMonitor(
  name: 'CriticalFeature',
  onPerformanceIssue: (metrics) {
    analytics.reportPerformance(metrics);
  },
  child: CriticalFeatureWidget(),
)
```

---

## Loading and State Widgets

### OptimizedShimmerPlaceholder

**Purpose**: Efficient shimmer loading placeholder with reduced GPU usage and smooth animations.

**Parameters**:
```dart
class OptimizedShimmerPlaceholder extends StatefulWidget {
  /// Width of the shimmer placeholder
  final double width;
  
  /// Height of the shimmer placeholder
  final double height;
  
  /// Border radius for rounded corners
  final double borderRadius;
  
  /// Base color of the shimmer
  final Color baseColor;
  
  /// Highlight color of the shimmer animation
  final Color highlightColor;
  
  /// Animation duration
  final Duration duration;
  
  /// Whether the shimmer animation is enabled
  final bool enabled;
}
```

**Usage Examples**:
```dart
// Basic shimmer placeholder
OptimizedShimmerPlaceholder(
  width: 200,
  height: 20,
  borderRadius: 4,
)

// Custom colors and timing
OptimizedShimmerPlaceholder(
  width: double.infinity,
  height: 100,
  baseColor: Colors.grey[300]!,
  highlightColor: Colors.grey[100]!,
  duration: Duration(milliseconds: 1500),
)

// Conditional shimmer
OptimizedShimmerPlaceholder(
  width: 150,
  height: 50,
  enabled: isLoading,
)
```

---

## Usage Guidelines

### Error Handling Best Practices

1. **Always wrap screens with ErrorBoundary**
   ```dart
   ErrorBoundary(
     child: MyScreen(),
   )
   ```

2. **Use specific error widgets for different error types**
   ```dart
   // For network errors
   NetworkErrorWidget(error: error, onRetry: retry)
   
   // For general errors
   DefaultErrorWidget(error: error, onRetry: retry)
   ```

3. **Provide meaningful retry mechanisms**
   ```dart
   onRetry: () {
     setState(() => _error = null);
     _fetchData();
   }
   ```

### Performance Guidelines

1. **Use lazy loading for large lists**
   ```dart
   LazyLoadingListView<Item>(
     loadMore: _loadMoreItems,
     itemBuilder: _buildItem,
   )
   ```

2. **Monitor performance-critical widgets**
   ```dart
   PerformanceMonitor(
     name: 'CriticalWidget',
     child: ExpensiveWidget(),
   )
   ```

3. **Prefer memory-efficient widgets for heavy components**
   ```dart
   class HeavyWidget extends MemoryEfficientWidget {
     // Implementation with automatic cleanup
   }
   ```

### Development vs Production

- **Development**: Enable detailed error information and performance overlays
- **Production**: Use user-friendly error messages and disable debug features

```dart
ErrorBoundary(
  showDetails: kDebugMode,
  child: PerformanceMonitor(
    showOverlay: kDebugMode,
    child: MyWidget(),
  ),
)
```
