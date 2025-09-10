/// Usage Patterns and Examples
/// 
/// This document provides comprehensive examples and best practices for using
/// the core systems and widgets in the Chumbucket application.

## Error Handling Patterns

### Pattern 1: Screen-Level Error Protection

**Use Case**: Protect entire screens from unexpected crashes

```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      onError: (error) {
        // Optional: Log error to analytics
        FirebaseAnalytics.instance.logEvent(
          name: 'screen_error',
          parameters: {
            'screen': 'MyScreen',
            'error': error.message,
          },
        );
      },
      child: Scaffold(
        appBar: AppBar(title: Text('My Screen')),
        body: _buildBody(),
      ),
    );
  }
}
```

### Pattern 2: Async Operation with Error Handling

**Use Case**: Handle API calls and network operations

```dart
class DataWidget extends StatefulWidget {
  @override
  _DataWidgetState createState() => _DataWidgetState();
}

class _DataWidgetState extends State<DataWidget> {
  Future<List<User>>? _usersFuture;
  
  @override
  void initState() {
    super.initState();
    _loadUsers();
  }
  
  void _loadUsers() {
    setState(() {
      _usersFuture = ErrorHandler.handleAsync(
        apiService.getUsers(),
        context: 'Load Users',
        fallback: <User>[], // Fallback to empty list
      );
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<User>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return OptimizedShimmerPlaceholder(
            width: double.infinity,
            height: 200,
          );
        }
        
        if (snapshot.hasError) {
          return DefaultErrorWidget(
            error: AppError(
              error: snapshot.error!,
              stackTrace: StackTrace.current,
              context: 'Load Users',
              severity: ErrorSeverity.medium,
              timestamp: DateTime.now(),
            ),
            onRetry: _loadUsers,
          );
        }
        
        final users = snapshot.data ?? [];
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) => UserTile(user: users[index]),
        );
      },
    );
  }
}
```

### Pattern 3: Provider Integration with Error Handling

**Use Case**: Using providers with comprehensive error management

```dart
class AuthenticatedWrapper extends StatelessWidget {
  final Widget child;
  
  const AuthenticatedWrapper({required this.child});
  
  @override
  Widget build(BuildContext context) {
    return Consumer<EnhancedAuthProvider>(
      builder: (context, auth, _) {
        // Handle loading state
        if (auth.isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Authenticating...'),
              ],
            ),
          );
        }
        
        // Handle authentication errors
        if (auth.lastError != null) {
          return DefaultErrorWidget(
            error: AppError(
              error: Exception(auth.lastError!),
              stackTrace: StackTrace.current,
              context: 'Authentication',
              severity: ErrorSeverity.high,
              timestamp: DateTime.now(),
            ),
            title: 'Authentication Error',
            onRetry: () {
              auth.clearError();
              auth.login();
            },
          );
        }
        
        // Handle unauthenticated state
        if (!auth.isAuthenticated) {
          return LoginScreen();
        }
        
        // Return authenticated content
        return child;
      },
    );
  }
}
```

## Performance Optimization Patterns

### Pattern 1: Memory-Efficient Heavy Widget

**Use Case**: Widgets with expensive resources that need proper cleanup

```dart
class ImageGalleryWidget extends MemoryEfficientWidget {
  final List<String> imageUrls;
  
  const ImageGalleryWidget({required this.imageUrls});
  
  @override
  MemoryEfficientState<ImageGalleryWidget> createState() => 
      _ImageGalleryWidgetState();
}

class _ImageGalleryWidgetState extends MemoryEfficientState<ImageGalleryWidget> {
  final List<ImageProvider> _imageProviders = [];
  late PageController _pageController;
  
  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    // Preload images
    for (String url in widget.imageUrls) {
      final provider = NetworkImage(url);
      _imageProviders.add(provider);
      
      // Preload for faster display
      precacheImage(provider, context);
    }
    
    // Track performance
    PerformanceLogger().startTimer('image_gallery_init');
    UserActionTracker().trackAction(
      'image_gallery_opened',
      category: 'Media',
      properties: {'image_count': widget.imageUrls.length},
    );
    PerformanceLogger().stopTimer('image_gallery_init');
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    
    // Clean up image cache
    for (ImageProvider provider in _imageProviders) {
      provider.evict();
    }
    
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return PerformanceMonitor(
      name: 'ImageGallery',
      showOverlay: kDebugMode,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        itemBuilder: (context, index) => Image(
          image: _imageProviders[index],
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
```

### Pattern 2: Optimized List with Lazy Loading

**Use Case**: Efficiently display large datasets with pagination

```dart
class OptimizedUserList extends StatefulWidget {
  @override
  _OptimizedUserListState createState() => _OptimizedUserListState();
}

class _OptimizedUserListState extends State<OptimizedUserList> {
  final List<User> _users = [];
  bool _isLoading = false;
  bool _hasMore = true;
  
  @override
  void initState() {
    super.initState();
    _loadInitialUsers();
  }
  
  Future<void> _loadInitialUsers() async {
    PerformanceLogger().startTimer('initial_user_load');
    
    final users = await ErrorHandler.handleAsync(
      userService.getUsers(offset: 0, limit: 20),
      context: 'Load Initial Users',
      fallback: <User>[],
    );
    
    setState(() {
      _users.addAll(users);
      _hasMore = users.length == 20;
    });
    
    PerformanceLogger().stopTimer('initial_user_load');
    
    UserActionTracker().trackAction(
      'user_list_loaded',
      category: 'Data',
      properties: {'initial_count': users.length},
    );
  }
  
  Future<void> _loadMoreUsers() async {
    if (_isLoading || !_hasMore) return;
    
    setState(() => _isLoading = true);
    
    final newUsers = await ErrorHandler.handleAsync(
      userService.getUsers(offset: _users.length, limit: 20),
      context: 'Load More Users',
      fallback: <User>[],
    );
    
    setState(() {
      _users.addAll(newUsers);
      _hasMore = newUsers.length == 20;
      _isLoading = false;
    });
    
    UserActionTracker().trackAction(
      'more_users_loaded',
      category: 'Data',
      properties: {'new_count': newUsers.length, 'total_count': _users.length},
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return LazyLoadingListView<User>(
      loadMore: (offset, limit) => userService.getUsers(offset: offset, limit: limit),
      itemBuilder: (context, user, index) => OptimizedUserTile(user: user),
      initialItems: _users,
      pageSize: 20,
      hasMore: _hasMore,
      onLoadingChanged: (isLoading) => setState(() => _isLoading = isLoading),
      loadingIndicator: OptimizedShimmerPlaceholder(
        width: double.infinity,
        height: 80,
      ),
    );
  }
}
```

## Logging and Analytics Patterns

### Pattern 1: Comprehensive Feature Usage Tracking

**Use Case**: Track user interactions with a feature comprehensively

```dart
class ChallengeCreationScreen extends StatefulWidget {
  @override
  _ChallengeCreationScreenState createState() => _ChallengeCreationScreenState();
}

class _ChallengeCreationScreenState extends State<ChallengeCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  String _challengeType = '';
  int _participantCount = 0;
  DateTime? _startDate;
  
  @override
  void initState() {
    super.initState();
    
    // Track screen entry
    UserActionTracker().trackAction(
      'challenge_creation_started',
      category: 'Challenges',
      properties: {
        'entry_time': DateTime.now().toIso8601String(),
        'user_id': context.read<AuthProvider>().currentUser?.id,
      },
    );
    
    EnhancedLogger().info('Challenge creation screen opened', tag: 'UI');
  }
  
  void _onChallengeTypeChanged(String type) {
    setState(() => _challengeType = type);
    
    UserActionTracker().trackAction(
      'challenge_type_selected',
      category: 'Challenges',
      properties: {'type': type},
    );
  }
  
  void _onParticipantCountChanged(int count) {
    setState(() => _participantCount = count);
    
    UserActionTracker().trackAction(
      'participant_count_changed',
      category: 'Challenges',
      properties: {'count': count},
    );
  }
  
  Future<void> _createChallenge() async {
    if (!_formKey.currentState!.validate()) return;
    
    PerformanceLogger().startTimer('challenge_creation');
    
    try {
      UserActionTracker().trackAction(
        'challenge_creation_attempted',
        category: 'Challenges',
        properties: {
          'type': _challengeType,
          'participant_count': _participantCount,
          'start_date': _startDate?.toIso8601String(),
        },
      );
      
      final challenge = await challengeService.createChallenge(
        type: _challengeType,
        participantCount: _participantCount,
        startDate: _startDate!,
      );
      
      EnhancedLogger().info(
        'Challenge created successfully',
        tag: 'Challenges',
        metadata: {
          'challenge_id': challenge.id,
          'type': _challengeType,
          'participant_count': _participantCount,
        },
      );
      
      UserActionTracker().trackAction(
        'challenge_created_success',
        category: 'Challenges',
        properties: {
          'challenge_id': challenge.id,
          'creation_time_ms': PerformanceLogger().getElapsedTime('challenge_creation'),
        },
      );
      
      Navigator.pop(context, challenge);
      
    } catch (error, stackTrace) {
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'Challenge Creation',
        severity: ErrorSeverity.high,
        notifyUser: true,
        userMessage: 'Failed to create challenge. Please try again.',
        metadata: {
          'challenge_type': _challengeType,
          'participant_count': _participantCount,
        },
      );
      
      UserActionTracker().trackAction(
        'challenge_creation_failed',
        category: 'Challenges',
        properties: {
          'error_type': error.runtimeType.toString(),
          'error_message': error.toString(),
        },
      );
    } finally {
      PerformanceLogger().stopTimer('challenge_creation');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return PerformanceMonitor(
      name: 'ChallengeCreationScreen',
      enableLogging: kDebugMode,
      child: Scaffold(
        appBar: AppBar(title: Text('Create Challenge')),
        body: Form(
          key: _formKey,
          child: _buildForm(),
        ),
      ),
    );
  }
}
```

### Pattern 2: Network Request Logging

**Use Case**: Comprehensive logging of API interactions

```dart
class ApiService {
  final http.Client _client = http.Client();
  
  Future<T> _makeRequest<T>(
    String method,
    String endpoint,
    T Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    
    EnhancedLogger().debug(
      'API request started',
      tag: 'Network',
      metadata: {
        'request_id': requestId,
        'method': method,
        'endpoint': endpoint,
        'has_body': body != null,
      },
    );
    
    PerformanceLogger().startTimer('api_request_$requestId');
    
    try {
      http.Response response;
      final uri = Uri.parse('$baseUrl$endpoint');
      
      switch (method.toUpperCase()) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
      
      final duration = PerformanceLogger().getElapsedTime('api_request_$requestId');
      
      EnhancedLogger().info(
        'API request completed',
        tag: 'Network',
        metadata: {
          'request_id': requestId,
          'status_code': response.statusCode,
          'duration_ms': duration,
          'response_size': response.body.length,
        },
      );
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return parser(data);
      } else {
        throw ApiException(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          statusCode: response.statusCode,
          endpoint: endpoint,
        );
      }
      
    } catch (error, stackTrace) {
      final duration = PerformanceLogger().getElapsedTime('api_request_$requestId');
      
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'API Request',
        severity: _getErrorSeverity(error),
        metadata: {
          'request_id': requestId,
          'method': method,
          'endpoint': endpoint,
          'duration_ms': duration,
        },
      );
      
      rethrow;
    } finally {
      PerformanceLogger().stopTimer('api_request_$requestId');
    }
  }
  
  ErrorSeverity _getErrorSeverity(dynamic error) {
    if (error is ApiException) {
      if (error.statusCode >= 500) return ErrorSeverity.high;
      if (error.statusCode >= 400) return ErrorSeverity.medium;
    }
    if (error is SocketException) return ErrorSeverity.medium;
    return ErrorSeverity.low;
  }
}
```

## State Management Patterns

### Pattern 1: Provider with Error Recovery

**Use Case**: Robust state management with automatic error recovery

```dart
class DataProvider extends ChangeNotifier {
  List<Item> _items = [];
  bool _isLoading = false;
  String? _error;
  
  List<Item> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;
  
  Future<void> loadItems({bool refresh = false}) async {
    if (_isLoading && !refresh) return;
    
    _setLoading(true);
    _clearError();
    
    try {
      EnhancedLogger().info('Loading items', tag: 'DataProvider');
      PerformanceLogger().startTimer('load_items');
      
      final items = await ErrorHandler.handleAsync(
        apiService.getItems(),
        context: 'Load Items',
        fallback: <Item>[],
      );
      
      _items = items;
      
      UserActionTracker().trackAction(
        'items_loaded',
        category: 'Data',
        properties: {
          'count': items.length,
          'refresh': refresh,
        },
      );
      
      EnhancedLogger().info(
        'Items loaded successfully',
        tag: 'DataProvider',
        metadata: {'count': items.length},
      );
      
    } catch (error, stackTrace) {
      _error = 'Failed to load items. Please try again.';
      
      ErrorHandler().handleError(
        error,
        stackTrace: stackTrace,
        context: 'DataProvider.loadItems',
        severity: ErrorSeverity.medium,
        metadata: {'refresh': refresh},
      );
      
    } finally {
      _setLoading(false);
      PerformanceLogger().stopTimer('load_items');
    }
  }
  
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _clearError() {
    _error = null;
    notifyListeners();
  }
  
  void retry() {
    loadItems(refresh: true);
  }
}
```

## Testing Patterns

### Pattern 1: Widget Testing with Error Scenarios

**Use Case**: Test widgets with various error conditions

```dart
void main() {
  group('ErrorBoundary Widget Tests', () {
    testWidgets('should display error widget when child throws', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(
            child: ThrowingWidget(),
          ),
        ),
      );
      
      // Wait for error to be caught
      await tester.pumpAndSettle();
      
      // Verify error widget is displayed
      expect(find.byType(DefaultErrorWidget), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });
    
    testWidgets('should call onError callback when error occurs', (tester) async {
      bool errorCallbackCalled = false;
      AppError? capturedError;
      
      await tester.pumpWidget(
        MaterialApp(
          home: ErrorBoundary(
            onError: (error) {
              errorCallbackCalled = true;
              capturedError = error;
            },
            child: ThrowingWidget(),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      
      expect(errorCallbackCalled, isTrue);
      expect(capturedError, isNotNull);
    });
  });
}

class ThrowingWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    throw Exception('Test error');
  }
}
```

### Pattern 2: Integration Testing with Services

**Use Case**: Test service integration with error handling

```dart
void main() {
  group('ApiService Integration Tests', () {
    late ApiService apiService;
    late MockHttpClient mockClient;
    
    setUp(() {
      mockClient = MockHttpClient();
      apiService = ApiService(client: mockClient);
    });
    
    test('should handle network errors gracefully', () async {
      // Setup mock to throw network error
      when(mockClient.get(any, headers: anyNamed('headers')))
          .thenThrow(SocketException('Network unreachable'));
      
      // Expect specific exception type
      expect(
        () => apiService.getUsers(),
        throwsA(isA<NetworkException>()),
      );
      
      // Verify error was logged
      verify(mockErrorHandler.handleError(
        any,
        context: 'API Request',
        severity: ErrorSeverity.medium,
      )).called(1);
    });
  });
}
```

## Integration Examples

### Pattern 1: Complete Feature Implementation

**Use Case**: Implementing a complete feature with all patterns integrated

```dart
class ChallengeListScreen extends StatefulWidget {
  @override
  _ChallengeListScreenState createState() => _ChallengeListScreenState();
}

class _ChallengeListScreenState extends State<ChallengeListScreen> {
  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      child: PerformanceMonitor(
        name: 'ChallengeListScreen',
        child: Scaffold(
          appBar: AppBar(title: Text('Challenges')),
          body: Consumer<ChallengeProvider>(
            builder: (context, provider, child) {
              if (provider.hasError) {
                return DefaultErrorWidget(
                  error: AppError(
                    error: Exception(provider.error!),
                    stackTrace: StackTrace.current,
                    context: 'Challenge List',
                    severity: ErrorSeverity.medium,
                    timestamp: DateTime.now(),
                  ),
                  onRetry: provider.retry,
                );
              }
              
              return LazyLoadingListView<Challenge>(
                loadMore: provider.loadMoreChallenges,
                itemBuilder: (context, challenge, index) => 
                    OptimizedChallengeCard(challenge: challenge),
                initialItems: provider.challenges,
                pageSize: 10,
                hasMore: provider.hasMore,
                loadingIndicator: OptimizedShimmerPlaceholder(
                  width: double.infinity,
                  height: 120,
                ),
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _navigateToCreateChallenge(),
            child: Icon(Icons.add),
          ),
        ),
      ),
    );
  }
  
  void _navigateToCreateChallenge() {
    UserActionTracker().trackAction(
      'create_challenge_button_pressed',
      category: 'Navigation',
    );
    
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChallengeCreationScreen()),
    );
  }
}
```

This comprehensive documentation provides practical patterns for implementing robust, performant, and well-monitored features in the Chumbucket application.
