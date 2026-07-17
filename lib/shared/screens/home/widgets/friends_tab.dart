import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_preview.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';

class FriendsTab extends StatefulWidget {
  final VoidCallback createNewChallenge;
  final Function(String, String)
  onFriendSelected; // Now passes name and wallet address
  final Widget Function(BuildContext context, int remainingCount)
  buildViewMoreItem;
  final VoidCallback
  onViewAllChallenges; // New callback for viewing all challenges
  final Function(Map<String, dynamic>, bool) onMarkChallengeCompleted;
  final bool showChallengesPreview;
  final double bottomPadding;

  const FriendsTab({
    super.key,
    required this.createNewChallenge,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    required this.onViewAllChallenges,
    required this.onMarkChallengeCompleted,
    this.showChallengesPreview = true,
    this.bottomPadding = 0,
  });
  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, String>> friends = [];
  bool isLoading = false; // Start as false - only show loading on first load
  bool hasAttemptedLoad = false; // Track if we've tried to load
  bool _isFirstLoad = true; // Track if this is the first load
  MwaWalletProvider?
  _walletProvider; // Store provider reference for safe disposal

  // Caching for performance optimization
  Future<List<Map<String, String>>>? _friendsFuture;
  ValueKey? _lastRefreshKey;
  DateTime? _lastLoadTime; // Track when we last loaded friends

  // Keep state alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Don't load friends immediately - wait for auth state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFriendsWhenReady();
    });

    // Also refresh the preview list as soon as a challenge is created by listening to WalletProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _walletProvider = Provider.of<MwaWalletProvider>(context, listen: false);
      _walletProvider?.addListener(_onWalletChange);
    });
  }

  void _onWalletChange() {
    if (!mounted) return;
    // Rebuild to refresh ChallengesPreview below the grid
    setState(() {});
  }

  @override
  void dispose() {
    // Remove listener safely by storing the provider reference in initState
    _walletProvider?.removeListener(_onWalletChange);
    super.dispose();
  }

  @override
  void didUpdateWidget(FriendsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if we need to refresh based on the widget key
    final newRefreshKey = widget.key;
    if (newRefreshKey != _lastRefreshKey && newRefreshKey is ValueKey) {
      print('FriendsTab: Refresh key changed, clearing caches');
      _lastRefreshKey = newRefreshKey;
      _friendsFuture = null; // Clear cache to force refresh
      hasAttemptedLoad = false; // Reset load flag to allow refresh
      // DON'T clear friends list - keep showing old data while refreshing
      // friends.clear();  // REMOVED - this was causing UI flash
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFriendsWhenReady();
      });
    }
  }

  Future<void> _loadFriendsWhenReady() async {
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);

    // THROTTLING: Don't load if we loaded very recently
    if (hasAttemptedLoad && friends.isNotEmpty) {
      final timeSinceLoad = DateTime.now().difference(
        _lastLoadTime ?? DateTime.now(),
      );
      if (timeSinceLoad < Duration(seconds: 30)) {
        print(
          'FriendsTab: Throttling load - too recent (${timeSinceLoad.inSeconds}s ago)',
        );
        return;
      }
    }

    // If user is already available, load friends immediately
    if (authProvider.walletAddress != null) {
      // If we don't have cached data, load it
      if (_friendsFuture == null) {
        _loadFriends();
      } else {
        // We have cached data, just update UI with it
        try {
          final cachedFriends = await _friendsFuture!;
          if (mounted) {
            setState(() {
              friends = cachedFriends;
              isLoading = false;
              hasAttemptedLoad = true;
            });
          }
        } catch (e) {
          // If cached data fails, reload
          _friendsFuture = null;
          _loadFriends();
        }
      }
    } else {
      // Otherwise, wait for auth to be ready
      print('FriendsTab: Waiting for auth to be ready...');
      if (mounted) {
        setState(() => isLoading = true);
      }
    }
  }

  Future<List<Map<String, String>>> _loadFriendsData() async {
    print('FriendsTab: Starting to load friends...');

    // Get current user
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final walletAddress = authProvider.walletAddress;

    if (walletAddress == null) {
      print('FriendsTab: No current user found');
      return [];
    }

    print('FriendsTab: Loading friends for user: $walletAddress');

    // Load friends from Supabase
    final friendsData = await UnifiedDatabaseService.getUserFriends(
      walletAddress,
      userPrivyId: walletAddress,
    );

    // Convert to UI format expected by FriendsGrid and assign images based on position
    final uiFriends = <Map<String, String>>[];
    final avatarColors = [
      '#FF5A76', // Pink
      '#4A90E2', // Blue
      '#7ED321', // Green
      '#F5A623', // Orange
      '#9013FE', // Purple
    ];

    for (int i = 0; i < friendsData.length; i++) {
      final friend = friendsData[i];
      // Cycle through images 1-5 for any number of friends
      final imageId = (i % 5) + 1; // This will give us 1,2,3,4,5,1,2,3,4,5...
      final colorIndex = i % avatarColors.length;

      uiFriends.add({
        'name': friend['name'] as String,
        'walletAddress': friend['walletAddress'] as String,
        'avatarColor': avatarColors[colorIndex],
        'imagePath': 'assets/images/ai_gen/profile_images/$imageId.png',
      });
    }

    print('FriendsTab: Loaded ${uiFriends.length} friends from Supabase');
    for (final friend in uiFriends) {
      print('  - ${friend['name']} (${friend['walletAddress']})');
    }

    return uiFriends;
  }

  void _showAllFriends() {
    showViewMoreFriendsSheet(
      context,
      friends: friends,
      onFriendSelected: (friendName) {
        final friend = friends.firstWhere(
          (f) => f['name'] == friendName,
          orElse: () => {'walletAddress': ''},
        );
        // Pass raw wallet address; resolution will happen where displayed
        widget.onFriendSelected(friendName, friend['walletAddress'] ?? '');
      },
    );
  }

  Future<void> _loadFriends() async {
    // If we already have cached data and haven't been asked to refresh, use it
    if (_friendsFuture != null && hasAttemptedLoad && friends.isNotEmpty) {
      print(
        'FriendsTab: Using cached friends data (${friends.length} friends)',
      );
      return;
    }

    try {
      if (mounted) {
        setState(() {
          // Only show loading spinner on first load, not on tab switches
          isLoading = _isFirstLoad;
          hasAttemptedLoad = true;
        });
      }

      // Use cached future if available
      _friendsFuture ??= _loadFriendsData();
      final uiFriends = await _friendsFuture!;

      if (mounted) {
        setState(() {
          friends = uiFriends;
          isLoading = false;
          _isFirstLoad = false; // No longer first load
          _lastLoadTime = DateTime.now(); // Track load time
        });
      }

      print('FriendsTab: UI updated with ${friends.length} friends');
    } catch (e) {
      print('Error loading friends: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Required for AutomaticKeepAliveClientMixin
    super.build(context);

    // Check auth state once without Consumer to avoid rebuilds
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);

    // Auto-load friends when user becomes available (only if we haven't attempted yet)
    if (authProvider.walletAddress != null &&
        !hasAttemptedLoad &&
        _friendsFuture == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFriends();
      });
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 10.h),
                Text(
                  'Who do you want to challenge?',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Only show spinner on first load when no data exists
                // Otherwise show the grid (even if empty or refreshing in background)
                (isLoading && friends.isEmpty)
                    ? Container(
                      width: 24.w,
                      height: 24.h,
                      margin: EdgeInsets.all(30.r),
                      child: const CircularProgressIndicator(),
                    )
                    : FriendsGrid(
                      friends: friends,
                      onFriendSelected: (friendName) {
                        final friend = friends.firstWhere(
                          (f) => f['name'] == friendName,
                          orElse: () => {'walletAddress': ''},
                        );
                        // Pass raw wallet address; resolution will happen where displayed
                        widget.onFriendSelected(
                          friendName,
                          friend['walletAddress'] ?? '',
                        );
                      },
                      buildViewMoreItem: widget.buildViewMoreItem,
                      onViewMorePressed: _showAllFriends,
                      maxVisibleFriends: 5, // Show 5 friends before "View More"
                    ),
                // SizedBox(height: 15.h),
                ChallengeButton(createNewChallenge: widget.createNewChallenge),
              ],
            ),
          ),
          if (widget.showChallengesPreview) ...[
            SizedBox(height: 24.h),
            Stack(
              children: [
                Center(
                  child: Opacity(
                    opacity: 0.9,
                    child: Text(
                      'Challenges',
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: -2,
                  child: GestureDetector(
                    onTap: widget.onViewAllChallenges,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 8.h,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View All',
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          SizedBox(width: 4.w),
                          PhosphorIcon(
                            PhosphorIconsRegular.arrowRight,
                            color: Colors.grey.shade700,
                            size: 18.sp,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            ChallengesPreview(
              onViewAll: widget.onViewAllChallenges,
              onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
            ),
          ],
          SizedBox(height: widget.bottomPadding.h),
        ],
      ),
    );
  }
}
