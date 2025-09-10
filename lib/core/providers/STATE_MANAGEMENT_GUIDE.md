# Enhanced State Management Guide

## Overview
This guide demonstrates the new enhanced state management patterns implemented in Phase 4 of the codebase refactoring. These patterns improve performance, error handling, and maintainability.

## Core Components

### 1. ProviderSelectors
Utility class to create optimized selectors that only rebuild when specific values change.

```dart
// Instead of consuming the entire provider
Consumer<AuthProvider>(
  builder: (context, authProvider, _) {
    return MyWidget(isLoading: authProvider.isLoading);
  },
)

// Use selective rebuilding
ProviderSelectors.selectBool<AuthProvider>(
  (provider) => provider.isLoading,
  builder: (context, isLoading, _) {
    return MyWidget(isLoading: isLoading);
  },
)
```

#### Available Selectors
- `selectBool`: For boolean values with automatic equality comparison
- `selectString`: For string values with null-safe comparison  
- `selectDouble`: For numeric values with precision-based comparison
- `selectCombined`: For multiple values with watchKeys optimization

### 2. EnhancedBaseChangeNotifier
Improved base class for providers with caching, performance monitoring, and error recovery.

```dart
class MyProvider extends EnhancedBaseChangeNotifier 
    with ProviderPerformanceMixin, ErrorRecoveryMixin {
  
  @override
  String get providerName => 'MyProvider';
  
  Future<void> performOperation() async {
    // Automatic performance monitoring and error recovery
    await executeWithRecovery(
      operationName: 'my_operation',
      operation: () async {
        // Your async operation here
        return await someAsyncCall();
      },
      config: ErrorRecoveryConfig(
        strategy: ErrorRecoveryStrategy.retry,
        maxRetries: 3,
      ),
    );
  }
}
```

### 3. Performance Monitoring
Automatic performance tracking for provider operations.

```dart
// Operations are automatically timed and logged
final result = await timeOperation(
  'data_fetch',
  () => fetchDataFromAPI(),
  warningThreshold: Duration(seconds: 2),
);

// Get performance statistics
final stats = ProviderPerformanceMonitor.getStatistics();
print('Average fetch time: ${stats['data_fetch']?.averageDuration}');
```

### 4. Error Recovery System
Configurable error recovery strategies for robust error handling.

```dart
// Configure different recovery strategies
ErrorRecoveryConfig(
  strategy: ErrorRecoveryStrategy.retry, // or fallback, refresh, resetState
  maxRetries: 3,
  exponentialBackoff: true,
  fallbackAction: () async {
    // Custom fallback logic
  },
)
```

## Performance Optimization Patterns

### 1. Selective Widget Rebuilding
Only rebuild widgets when specific values change:

```dart
// ❌ Rebuilds on any provider change
Consumer<WalletProvider>(
  builder: (context, wallet, _) => Text('\$${wallet.balance}'),
)

// ✅ Only rebuilds when balance changes
ProviderSelectors.selectDouble<WalletProvider>(
  (provider) => provider.balance,
  builder: (context, balance, _) => Text('\$${balance}'),
  precision: 0.01, // Only rebuild if change > 1 cent
)
```

### 2. Batched Notifications
The enhanced base provider batches notifications to reduce rebuilds:

```dart
// Multiple state changes in sequence only trigger one rebuild
provider.setLoading();
provider.updateValue1(newValue1);
provider.updateValue2(newValue2);
provider.setSuccess();
// Only one notification sent to listeners
```

### 3. Smart Caching
Automatic caching with TTL for expensive operations:

```dart
// Cache API results for 15 minutes
return await runAsync(
  () => expensiveAPICall(),
  enableCaching: true,
  cacheKey: 'user_data_${userId}',
  cacheTtl: Duration(minutes: 15),
);
```

## Error Handling Patterns

### 1. Automatic Retry with Backoff
```dart
await executeWithRecovery(
  operationName: 'network_request',
  operation: () => networkCall(),
  config: ErrorRecoveryConfig(
    strategy: ErrorRecoveryStrategy.retry,
    maxRetries: 3,
    exponentialBackoff: true, // 2s, 4s, 8s delays
  ),
);
```

### 2. Fallback Actions
```dart
ErrorRecoveryConfig(
  strategy: ErrorRecoveryStrategy.fallback,
  fallbackAction: () async {
    // Load from cache or show offline data
    return await loadFromCache();
  },
)
```

### 3. State Reset Recovery
```dart
ErrorRecoveryConfig(
  strategy: ErrorRecoveryStrategy.resetState,
  resetAction: () {
    // Reset provider to clean state
    resetAllData();
    clearCache();
  },
)
```

## Migration Guide

### Migrating Existing Providers

1. **Change base class**:
   ```dart
   // Before
   class MyProvider extends BaseChangeNotifier {
   
   // After  
   class MyProvider extends EnhancedBaseChangeNotifier 
       with ProviderPerformanceMixin, ErrorRecoveryMixin {
   ```

2. **Add provider name**:
   ```dart
   @override
   String get providerName => 'MyProvider';
   ```

3. **Wrap async operations**:
   ```dart
   // Before
   Future<void> fetchData() async {
     setLoading();
     try {
       final data = await api.getData();
       updateData(data);
       setSuccess();
     } catch (e) {
       setError(e.toString());
     }
   }
   
   // After
   Future<void> fetchData() async {
     await executeWithRecovery(
       operationName: 'fetch_data',
       operation: () async {
         final data = await api.getData();
         updateData(data);
       },
     );
   }
   ```

### Migrating Widgets

1. **Replace Consumer with Selectors**:
   ```dart
   // Before - rebuilds on any change
   Consumer<AuthProvider>(
     builder: (context, auth, _) {
       if (auth.isLoading) return LoadingWidget();
       if (auth.hasError) return ErrorWidget(auth.errorMessage);
       return ContentWidget();
     },
   )
   
   // After - selective rebuilding
   ProviderSelectors.selectCombined<AuthProvider>(
     (provider) => {
       'isLoading': provider.isLoading,
       'hasError': provider.hasError,
       'errorMessage': provider.errorMessage,
     },
     builder: (context, state, _) {
       if (state['isLoading']) return LoadingWidget();
       if (state['hasError']) return ErrorWidget(state['errorMessage']);
       return ContentWidget();
     },
     watchKeys: ['isLoading', 'hasError'], // Only rebuild for these
   )
   ```

## Best Practices

### 1. Selector Usage
- Use the most specific selector possible
- Prefer `selectBool`, `selectString` over generic `select`
- Use `watchKeys` in `selectCombined` to limit rebuilds

### 2. Error Recovery Configuration  
- Set appropriate retry counts for different operations
- Use fallback actions for critical user flows
- Configure exponential backoff for network operations

### 3. Performance Monitoring
- Enable monitoring in debug mode
- Set warning thresholds for critical operations
- Review performance reports regularly

### 4. Caching Strategy
- Cache expensive computation results
- Set appropriate TTL values
- Clear cache when data becomes stale

## Performance Monitoring Commands

```dart
// Enable/disable monitoring
ProviderPerformanceMonitor.setMonitoring(true);

// Get statistics
final stats = ProviderPerformanceMonitor.getStatistics();

// Log performance report
ProviderPerformanceMonitor.logPerformanceReport();

// Monitor provider rebuilds
final rebuilds = ProviderPerformanceMonitor.getProviderRebuildStats();
```

## Error Recovery Commands

```dart
// Get error history
final errors = ProviderErrorRecovery.getErrorHistory('operation_key');

// Get recovery statistics
final stats = ProviderErrorRecovery.getRecoveryStats();

// Clear error history
ProviderErrorRecovery.clearErrorHistory('operation_key');
```

This enhanced state management system provides better performance, reliability, and maintainability while preserving the existing UI/UX patterns.
