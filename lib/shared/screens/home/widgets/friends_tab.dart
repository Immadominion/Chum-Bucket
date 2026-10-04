import 'dart:async';

import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_preview.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';

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
  /// Opens Add a friend.
  final VoidCallback onAddFriend;

  /// A tapped friend's row: `name`, `walletAddress` and `userId` (their
  /// canonical person id, empty when unknown).
  final void Function(Map<String, String> friend) onFriendSelected;
  final Widget Function(BuildContext context, int remainingCount)
  buildViewMoreItem;
  final VoidCallback
  onViewAllChallenges; // New callback for viewing all challenges
  final Function(Map<String, dynamic>, bool) onMarkChallengeCompleted;
  final bool showChallengesPreview;
  final double bottomPadding;
  final Widget? invitations;

  /// The people you follow, drawn above the wallet friends. Null when there
  /// is nothing to draw (not loaded, none, or signed out).
  final Widget? followingSection;

  /// Whether the follow list is known to be empty. Null when this build or
  /// session has no follow list, so it cannot say.
  final bool? followingEmpty;

  /// The follow list's first read is in flight with nothing to show yet.
  final bool followingLoading;

  /// The follow list failed with nothing saved to show.
  final String? followingError;

  /// Pull-to-refresh also re-reads whatever the parent owns (follows,
  /// invitations).
  final Future<void> Function()? onRefresh;

  /// Bumped by Home on resume and after a friend is added: the wallet
  /// friends read again in place, and the list stays on screen meanwhile.
  final int refreshKey;

  const FriendsTab({
    super.key,
    required this.onAddFriend,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    required this.onViewAllChallenges,
    required this.onMarkChallengeCompleted,
    this.showChallengesPreview = true,
    this.bottomPadding = 0,
    this.invitations,
    this.followingSection,
    this.followingEmpty,
    this.followingLoading = false,
    this.followingError,
    this.onRefresh,
    this.refreshKey = 0,
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
  DateTime? _lastLoadTime; // Track when we last loaded friends

  // Keep state alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Don't load friends immediately - wait for auth state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFriendsWhenReady();
    });

    // Rebuild the (legacy) escrow preview when the wallet changes, e.g. after
    // a witness settles one.
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
    // A refresh reads again in place. (A changed widget key would build a
    // new, empty State instead, which is why the parent keys this tab by
    // wallet only and passes the refresh as [refreshKey].)
    if (oldWidget.refreshKey != widget.refreshKey) {
      debugPrint('FriendsTab: refresh requested, reading again in place');
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
        'userId': friend['userId'] ?? '',
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
      onFriendSelected: widget.onFriendSelected,
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

    final connected = authProvider.walletAddress != null;
    final walletLoading = connected && friends.isEmpty && !hasAttemptedLoad ||
        connected && isLoading && friends.isEmpty;
    final walletFailed = connected && _hasLoadError && friends.isEmpty;
    final hasWalletFriends = connected && friends.isNotEmpty;
    final loading = walletLoading || widget.followingLoading;
    final hasFollowing = widget.followingSection != null;
    final noFollowList = widget.followingEmpty == null && !hasFollowing;
    final followsKnownEmpty = widget.followingEmpty == true || noFollowList;

    Future<void> refresh() async {
      await Future.wait([
        if (connected) _retryLoadFriends(),
        if (widget.onRefresh != null) widget.onRefresh!(),
      ]);
    }

    // Nothing failed, nothing loading, nobody yet: the people scene, one
    // line and the one thing to do. Signed out, Add a friend opens sign-in.
    final nobodyYet =
        !loading &&
        !hasWalletFriends &&
        !walletFailed &&
        widget.followingError == null &&
        followsKnownEmpty;
    // Everything that could show people failed: one full-screen error.
    final allFailed =
        !loading &&
        !hasWalletFriends &&
        !hasFollowing &&
        (widget.followingError != null || walletFailed) &&
        (widget.followingError != null || noFollowList);

    if (nobodyYet || allFailed) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: refresh,
        child: CustomScrollView(
          key: const PageStorageKey('friends-grid'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (widget.invitations != null)
              SliverToBoxAdapter(child: widget.invitations!),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.bottomPadding),
                child: Center(
                  child:
                      allFailed
                          ? ChumbucketStateView(
                            artwork: ChumbucketStateArtwork.error,
                            message: 'Couldn’t load your friends',
                            actionLabel: 'Try again',
                            onAction: refresh,
                          )
                          : ChumbucketStateView(
                            artwork: ChumbucketStateArtwork.people,
                            message: 'Add friends to see their calls',
                            actionLabel: 'Add a friend',
                            actionIcon: 'user-plus-outline',
                            onAction: widget.onAddFriend,
                          ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final labelled = hasFollowing && hasWalletFriends;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: refresh,
      child: ListView(
        key: const PageStorageKey('friends-grid'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        children: [
          if (widget.invitations != null) widget.invitations!,
          // Every account can add a friend — wallet, Google or X: adding
          // follows a real Chumbucket person, confirmed on a card first
          // (add_friend_sheet.dart). Signed out, it opens sign-in.
          _AddFriendRow(onTap: widget.onAddFriend),
          const SizedBox(height: 16),
          if (loading && !hasFollowing && !hasWalletFriends)
            const _PeopleSkeleton(),
          if (hasFollowing) ...[
            if (labelled) const _SectionLabel('Following'),
            widget.followingSection!,
          ],
          if (hasWalletFriends) ...[
            if (hasFollowing) const SizedBox(height: 20),
            if (labelled) const _SectionLabel('Wallet friends'),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Consumer<ArenaProvider>(
                builder:
                    (context, arena, _) => FriendsGrid(
                      friends: _withXLabels(friends, arena),
                      onFriendSelected: widget.onFriendSelected,
                      buildViewMoreItem: widget.buildViewMoreItem,
                      onViewMorePressed: _showAllFriends,
                      maxVisibleFriends: 5,
                    ),
              ),
            ),
          ],
          if (widget.showChallengesPreview) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: _SectionLabel('Challenges')),
                IconButton(
                  tooltip: 'View all challenges',
                  onPressed: widget.onViewAllChallenges,
                  icon: const BasilIcon(
                    'arrow-right-outline',
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            ChallengesPreview(
              onViewAll: widget.onViewAllChallenges,
              onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
            ),
          ],
        ],
      ),
    );
  }
}

/// The way to add someone, always first in the list: a plus in a coral
/// circle, two words, a chevron.
class _AddFriendRow extends StatelessWidget {
  const _AddFriendRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add a friend',
    excludeSemantics: true,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('friends-add-friend'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: ChumbucketPrimaryButton.gradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: BasilIcon(
                      'user-plus-outline',
                      size: 22,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Add a friend',
                    style: TextStyle(
                      fontFamily: 'PPNeueMachina',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const BasilIcon(
                  'arrow-right-outline',
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'PPNeueMachina',
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// Three quiet placeholder rows while the first read of your people runs:
/// the shape of what is coming, no "Loading…" copy.
class _PeopleSkeleton extends StatelessWidget {
  const _PeopleSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your friends',
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.outlineVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: .5,
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.outlineVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: .3,
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.outlineVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
