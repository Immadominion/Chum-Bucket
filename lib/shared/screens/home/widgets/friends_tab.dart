import 'dart:async';

import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_preview.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

/// Merge in each friend's resolved X-handle/display-name label, when the
/// wallet-profile cache already has one — leaves the map untouched otherwise
/// so the existing `full_name`/wallet fallback keeps working.
List<Map<String, String>> _withXLabels(
  List<Map<String, String>> friends,
  ArenaProvider arena,
) {
  return friends.map((f) {
    final wallet = f['walletAddress'] ?? '';
    final label = wallet.isEmpty ? null : arena.walletProfile(wallet)?.label;
    return label == null ? f : {...f, 'xLabel': label};
  }).toList();
}

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
  final Widget? invitations;

  const FriendsTab({
    super.key,
    required this.createNewChallenge,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    required this.onViewAllChallenges,
    required this.onMarkChallengeCompleted,
    this.showChallengesPreview = true,
    this.bottomPadding = 0,
    this.invitations,
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
  bool _hasLoadError = false; // M8: surfaced as a retryable error card
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
    _lastRefreshKey = widget.key is ValueKey ? widget.key as ValueKey : null;
    // Don't load friends immediately - wait for auth state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFriendsWhenReady();
    });

    // Also refresh the preview list as soon as a challenge is created by listening to WalletProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
      debugPrint('FriendsTab: Refresh key changed, clearing caches');
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
    if (!mounted) return;
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);

    // THROTTLING: Don't load if we loaded very recently
    if (hasAttemptedLoad && friends.isNotEmpty) {
      final timeSinceLoad = DateTime.now().difference(
        _lastLoadTime ?? DateTime.now(),
      );
      if (timeSinceLoad < Duration(seconds: 30)) {
        debugPrint(
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
      debugPrint('FriendsTab: Waiting for auth to be ready...');
      if (mounted) {
        setState(() => isLoading = true);
      }
    }
  }

  Future<List<Map<String, String>>> _loadFriendsData() async {
    debugPrint('FriendsTab: Starting to load friends...');

    // Get current user
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final walletAddress = authProvider.walletAddress;

    if (walletAddress == null) {
      debugPrint('FriendsTab: No current user found');
      return [];
    }

    debugPrint('FriendsTab: Loading friends for user: $walletAddress');

    // Best-effort: load this wallet's pending "added by X handle, not
    // joined yet" targets so the section below the grid can show them.
    unawaited(
      context.read<ArenaProvider>().loadPendingTargets(
        walletAddress: walletAddress,
      ),
    );

    // Load friends from Supabase
    final friendsData = await UnifiedDatabaseService.getUserFriends(
      walletAddress,
      userPrivyId: walletAddress,
    );
    if (!mounted) return [];

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

    debugPrint('FriendsTab: Loaded ${uiFriends.length} friends from Supabase');
    for (final friend in uiFriends) {
      debugPrint('  - ${friend['name']} (${friend['walletAddress']})');
    }

    return uiFriends;
  }

  void _showAllFriends() {
    final arena = context.read<ArenaProvider>();
    showViewMoreFriendsSheet(
      context,
      friends: _withXLabels(friends, arena),
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
      debugPrint(
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
          _hasLoadError = false;
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
        // Best-effort: resolve @handles for whoever just loaded into the list.
        unawaited(
          context.read<ArenaProvider>().loadWalletProfiles(
            uiFriends
                .map((f) => f['walletAddress'] ?? '')
                .where((w) => w.isNotEmpty)
                .toList(),
          ),
        );
      }

      debugPrint('FriendsTab: UI updated with ${friends.length} friends');
    } catch (e) {
      debugPrint('Error loading friends: $e');
      // M8: remember the failure so the UI can offer a real retry instead of
      // silently dropping to a blank grid.
      if (mounted) {
        setState(() {
          isLoading = false;
          _hasLoadError = true;
        });
      }
    }
  }

  Future<void> _retryLoadFriends() async {
    _friendsFuture = null;
    hasAttemptedLoad = false;
    await _loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    // Required for AutomaticKeepAliveClientMixin
    super.build(context);

    // Check auth state once without Consumer to avoid rebuilds
    final authProvider = context.watch<MwaAuthProvider>();

    // Auto-load friends when user becomes available (only if we haven't attempted yet)
    if (authProvider.walletAddress != null &&
        !hasAttemptedLoad &&
        _friendsFuture == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFriends();
      });
    }

    final styles = AppTextStyles.textTheme;
    final connected = authProvider.walletAddress != null;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _retryLoadFriends,
      child: SingleChildScrollView(
        key: const PageStorageKey('friends-grid'),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.invitations != null) widget.invitations!,
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child:
                  !connected
                      ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your existing friends',
                            style: styles.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connect your existing account to load your friends.',
                            style: styles.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: AppColors.textPrimary,
                            ),
                            onPressed: () => showProfileSettingsSheet(context),
                            child: const Text('Account settings'),
                          ),
                        ],
                      )
                      : Column(
                        children: [
                          if (isLoading && friends.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              'Loading your friends…',
                              style: styles.bodySmall,
                            ),
                          ] else if (_hasLoadError && friends.isEmpty) ...[
                            const ChumbucketStateArt.compact(
                              ChumbucketStateArtwork.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Couldn’t load your friends. Check your connection.',
                              style: styles.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                foregroundColor: AppColors.textPrimary,
                              ),
                              onPressed: _retryLoadFriends,
                              child: const Text('Try again'),
                            ),
                          ] else
                            Consumer<ArenaProvider>(
                              builder:
                                  (context, arena, _) => FriendsGrid(
                                    friends: _withXLabels(friends, arena),
                                    onFriendSelected: (friendName) {
                                      final friend = friends.firstWhere(
                                        (f) => f['name'] == friendName,
                                        orElse: () => {'walletAddress': ''},
                                      );
                                      widget.onFriendSelected(
                                        friendName,
                                        friend['walletAddress'] ?? '',
                                      );
                                    },
                                    buildViewMoreItem: widget.buildViewMoreItem,
                                    onViewMorePressed: _showAllFriends,
                                    maxVisibleFriends: 5,
                                  ),
                            ),
                          if (_hasLoadError && friends.isNotEmpty)
                            Text(
                              'Showing saved friends. Pull down to retry.',
                              style: styles.bodySmall,
                            ),
                        ],
                      ),
            ),
            if (connected) ...[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.lightPrimary, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton.icon(
                  onPressed: widget.createNewChallenge,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 52),
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.all(16),
                    textStyle: styles.titleMedium,
                  ),
                  icon: const BasilIcon('plus-outline'),
                  label: const Text('Add a friend'),
                ),
              ),
              const _PendingInvitesSection(),
            ],
            const SizedBox(height: 16),
            Text(
              'Friends are mutual connections. Following adds people’s calls to Home.',
              style: styles.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            if (widget.showChallengesPreview) ...[
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Challenges', style: styles.titleLarge),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppColors.textPrimary,
                    ),
                    onPressed: widget.onViewAllChallenges,
                    child: const Text('View all challenges'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ChallengesPreview(
                onViewAll: widget.onViewAllChallenges,
                onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
              ),
            ],
            SizedBox(height: widget.bottomPadding),
          ],
        ),
      ),
    );
  }
}

/// Existing add-by-handle requests. These are not delivered call invitations.
class _PendingInvitesSection extends StatelessWidget {
  const _PendingInvitesSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<ArenaProvider>(
      builder: (context, arena, _) {
        final unresolved =
            arena.pendingTargets.where((t) => !t.isResolved).toList();
        if (unresolved.isEmpty) return const SizedBox.shrink();
        final styles = AppTextStyles.textTheme;
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Waiting to join', style: styles.titleMedium),
              const SizedBox(height: 8),
              Text(
                'These friend requests are waiting for the person to join with their X account.',
                style: styles.bodySmall?.copyWith(
                  color: AppColors.onPrimaryContainer,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              for (final target in unresolved)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${target.providerUsername}',
                        style: styles.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('Not joined yet', style: styles.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
