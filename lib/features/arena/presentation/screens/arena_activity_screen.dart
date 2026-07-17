import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/dare_yourself_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_notifications_sheet.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

class ArenaActivityScreen extends StatefulWidget {
  const ArenaActivityScreen({super.key});

  @override
  State<ArenaActivityScreen> createState() => _ArenaActivityScreenState();
}

class _ArenaActivityScreenState extends State<ArenaActivityScreen> {
  String? _openingMatchId;
  final Set<String> _openingProfiles = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitial();
    });
  }

  Future<void> _loadInitial() async {
    final arena = context.read<ArenaProvider>();
    final auth = context.read<MwaAuthProvider>();
    final requests = <Future<void>>[
      arena.loadActivity(
        walletAddress: auth.walletAddress,
        mode: arena.feedMode,
      ),
      arena.loadHotCallers(),
    ];
    final wallet = auth.walletAddress;
    if (wallet != null) {
      requests.add(arena.loadSocialInbox(walletAddress: wallet));
      requests.add(arena.subscribeNotifications(walletAddress: wallet));
    }
    await Future.wait(requests);
  }

  Future<void> _reload({ArenaFeedMode? mode}) async {
    final arena = context.read<ArenaProvider>();
    final auth = context.read<MwaAuthProvider>();
    await arena.loadActivity(walletAddress: auth.walletAddress, mode: mode);
  }

  Future<void> _openCall(ArenaActivityEvent event) async {
    final matchId = event.matchId;
    if (matchId == null || matchId.isEmpty) {
      SnackBarUtils.showInfo(
        context,
        title: 'No market attached',
        subtitle: 'This activity cannot be copied yet.',
      );
      return;
    }

    setState(() => _openingMatchId = matchId);
    try {
      final match = await context.read<ArenaProvider>().refreshMatch(matchId);
      if (!mounted) return;
      if (!match.isOpenForCalls) {
        SnackBarUtils.showInfo(
          context,
          title: 'Market closed',
          subtitle: 'This call has already locked or settled.',
        );
        return;
      }

      final copied = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => DareYourselfScreen(match: match)),
      );
      if (copied == true && mounted) {
        await _reload();
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not open call',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _openingMatchId = null);
    }
  }

  Future<void> _showProfile(String wallet) async {
    if (wallet.isEmpty) return;
    setState(() => _openingProfiles.add(wallet));
    final arena = context.read<ArenaProvider>();
    final auth = context.read<MwaAuthProvider>();
    final profile = await arena.loadProfile(
      targetWallet: wallet,
      viewerWallet: auth.walletAddress,
    );
    if (!mounted) return;
    setState(() => _openingProfiles.remove(wallet));

    if (profile == null) {
      SnackBarUtils.showError(
        context,
        title: 'Could not load profile',
        subtitle: arena.profileError ?? 'Try again in a moment.',
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _CallerProfileSheet(
            wallet: wallet,
            onToggleFollow: () => _toggleFollow(wallet),
          ),
    );
  }

  Future<void> _toggleFollow(String wallet) async {
    final arena = context.read<ArenaProvider>();
    final auth = context.read<MwaAuthProvider>();
    final wasFollowing = arena.isFollowing(wallet);
    try {
      await arena.toggleFollow(authProvider: auth, targetWallet: wallet);
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: wasFollowing ? 'Unfollowed' : 'Following',
        subtitle:
            wasFollowing
                ? 'Removed ${_shortWallet(wallet)} from your feed.'
                : 'Calls from ${_shortWallet(wallet)} will show in Following.',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not update follow',
        subtitle: e.toString(),
      );
    }
  }

  void _openNotifications() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => ArenaNotificationsSheet(
            onOpenClaimable: () {
              Navigator.of(context).pop();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const MyPotsScreen()));
            },
          ),
    );
  }

  void _openMyPots() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyPotsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Calls',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Consumer<ArenaProvider>(
            builder:
                (context, arena, _) => _NotificationBell(
                  unreadCount: arena.unreadNotificationCount,
                  onPressed: _openNotifications,
                ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: PhosphorIcon(
              PhosphorIcons.arrowsClockwise(),
              color: AppColors.textPrimary,
            ),
            onPressed: _loadInitial,
          ),
        ],
      ),
      body: Consumer2<ArenaProvider, MwaAuthProvider>(
        builder: (context, arena, auth, _) {
          final wallet = auth.walletAddress;

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadInitial,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 12.h),
                    child: _FeedHeader(
                      mode: arena.feedMode,
                      canUseFollowing: wallet != null,
                      onModeChanged: (mode) => _reload(mode: mode),
                    ),
                  ),
                ),
                if (wallet != null &&
                    (arena.claimablePositions.isNotEmpty ||
                        arena.isLoadingClaimable ||
                        arena.claimableError != null))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
                      child: _ClaimableBanner(
                        positions: arena.claimablePositions,
                        isLoading: arena.isLoadingClaimable,
                        error: arena.claimableError,
                        onOpen: _openMyPots,
                        onRetry:
                            () => arena.loadClaimable(walletAddress: wallet),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _HotCallersStrip(
                    rows: arena.hotCallers,
                    isLoading: arena.isLoadingHotCallers,
                    openingProfiles: _openingProfiles,
                    onTapCaller: _showProfile,
                  ),
                ),
                if (arena.activityError != null && arena.activity.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _FeedStateMessage(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load calls',
                      subtitle: arena.activityError!,
                      actionLabel: 'Try again',
                      onAction: _loadInitial,
                    ),
                  )
                else if (arena.isLoadingActivity && arena.activity.isEmpty)
                  SliverList.separated(
                    itemCount: 4,
                    separatorBuilder: (_, __) => SizedBox(height: 12.h),
                    itemBuilder:
                        (_, __) => Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: const _FeedSkeletonCard(),
                        ),
                  )
                else if (arena.activity.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _FeedStateMessage(
                      icon: Icons.dynamic_feed_outlined,
                      title:
                          arena.feedMode == ArenaFeedMode.following
                              ? 'Your following feed is quiet'
                              : 'No calls yet',
                      subtitle:
                          arena.feedMode == ArenaFeedMode.following
                              ? 'Follow callers from the hot list to build your feed.'
                              : 'Fresh calls will appear here once the arena wakes up.',
                      actionLabel: 'Refresh',
                      onAction: _loadInitial,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20.w, 2.h, 20.w, 24.h),
                    sliver: SliverList.separated(
                      itemCount: arena.activity.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (context, index) {
                        final event = arena.activity[index];
                        final isMe = event.walletAddress == wallet;
                        return _PredictionFeedCard(
                          event: event,
                          isMe: isMe,
                          isFollowing: arena.isFollowing(event.walletAddress),
                          isFollowBusy:
                              arena.isFollowBusy(event.walletAddress) ||
                              _openingProfiles.contains(event.walletAddress),
                          isOpeningCall: _openingMatchId == event.matchId,
                          onProfileTap: () => _showProfile(event.walletAddress),
                          onFollowTap:
                              isMe
                                  ? null
                                  : () => _toggleFollow(event.walletAddress),
                          onCallToo: () => _openCall(event),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const _NotificationBell({required this.unreadCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip:
          unreadCount == 0
              ? 'Notifications'
              : '$unreadCount unread notifications',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text(unreadCount > 9 ? '9+' : '$unreadCount'),
        backgroundColor: AppColors.primary,
        textColor: Colors.white,
        child: Icon(
          Icons.notifications_none_outlined,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ClaimableBanner extends StatelessWidget {
  final List<ArenaServerPosition> positions;
  final bool isLoading;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  const _ClaimableBanner({
    required this.positions,
    required this.isLoading,
    required this.error,
    required this.onOpen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && positions.isEmpty) {
      return const _ClaimableSkeleton();
    }
    if (error != null && positions.isEmpty) {
      return _ClaimableRetry(onRetry: onRetry);
    }

    final total = positions.fold<BigInt>(
      BigInt.zero,
      (sum, position) => sum + (position.payoutBaseUnits ?? BigInt.zero),
    );
    final amount = total.toDouble() / 1000000;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18.r),
      child: Ink(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: AppColors.successContainer,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.success,
                size: 22.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    positions.length == 1
                        ? 'Winnings ready to claim'
                        : '${positions.length} winnings ready to claim',
                    style: TextStyle(
                      color: AppColors.onSuccessContainer,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    total == BigInt.zero
                        ? 'Open My Pots to pull your payout.'
                        : '${ArenaFormat.usdc(amount)} waiting in My Pots',
                    style: TextStyle(
                      color: AppColors.onSuccessContainer.withValues(
                        alpha: 0.8,
                      ),
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.success, size: 22.sp),
          ],
        ),
      ),
    );
  }
}

class _ClaimableSkeleton extends StatelessWidget {
  const _ClaimableSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 70.h,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18.r),
    ),
  );
}

class _ClaimableRetry extends StatelessWidget {
  final VoidCallback onRetry;

  const _ClaimableRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16.r),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(
          Icons.cloud_off_outlined,
          size: 18.sp,
          color: AppColors.textSecondary,
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            'Could not check claimable winnings.',
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _FeedHeader extends StatelessWidget {
  final ArenaFeedMode mode;
  final bool canUseFollowing;
  final ValueChanged<ArenaFeedMode> onModeChanged;

  const _FeedHeader({
    required this.mode,
    required this.canUseFollowing,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'See the call. Back it. Settle it.',
            style: TextStyle(
              fontSize: 22.sp,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Follow sharp callers, copy their predictions, and track who actually settles green.',
            style: TextStyle(
              fontSize: 13.sp,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 14.h),
          Container(
            height: 44.h,
            padding: EdgeInsets.all(4.w),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    label: 'Global',
                    selected: mode == ArenaFeedMode.global,
                    onTap: () => onModeChanged(ArenaFeedMode.global),
                  ),
                ),
                SizedBox(width: 6.w),
                Expanded(
                  child: _ModeButton(
                    label: 'Following',
                    selected: mode == ArenaFeedMode.following,
                    enabled: canUseFollowing,
                    onTap: () => onModeChanged(ArenaFeedMode.following),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(11.r),
        onTap: enabled ? onTap : null,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w800,
              color:
                  !enabled
                      ? AppColors.textTertiary
                      : selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HotCallersStrip extends StatelessWidget {
  final List<ArenaLeaderboardRow> rows;
  final bool isLoading;
  final Set<String> openingProfiles;
  final ValueChanged<String> onTapCaller;

  const _HotCallersStrip({
    required this.rows,
    required this.isLoading,
    required this.openingProfiles,
    required this.onTapCaller,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = isLoading && rows.isEmpty ? 5 : rows.length;
    if (itemCount == 0) return SizedBox(height: 8.h);

    return SizedBox(
      height: 120.h,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(20.w, 2.h, 20.w, 16.h),
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(width: 10.w),
        itemBuilder: (context, index) {
          if (rows.isEmpty) return const _HotCallerSkeleton();
          final row = rows[index];
          final wallet = row.walletAddress;
          return _HotCallerChip(
            row: row,
            loading: openingProfiles.contains(wallet),
            onTap: () => onTapCaller(wallet),
          );
        },
      ),
    );
  }
}

class _HotCallerChip extends StatelessWidget {
  final ArenaLeaderboardRow row;
  final bool loading;
  final VoidCallback onTap;

  const _HotCallerChip({
    required this.row,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(22.r),
      child: Container(
        width: 118.w,
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CallerAvatar(wallet: row.walletAddress, size: 34.w),
                const Spacer(),
                if (loading)
                  SizedBox(
                    width: 14.w,
                    height: 14.w,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.local_fire_department,
                    size: 16.sp,
                    color: AppColors.primary,
                  ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              _shortWallet(row.walletAddress),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 3.h),
            Text(
              '${ArenaFormat.percent(row.winRate)} win • ${_formatSignedUsdc(row.pnlBaseUnits)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
                color: _moneyColor(row.pnlBaseUnits),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictionFeedCard extends StatelessWidget {
  final ArenaActivityEvent event;
  final bool isMe;
  final bool isFollowing;
  final bool isFollowBusy;
  final bool isOpeningCall;
  final VoidCallback onProfileTap;
  final VoidCallback? onFollowTap;
  final VoidCallback onCallToo;

  const _PredictionFeedCard({
    required this.event,
    required this.isMe,
    required this.isFollowing,
    required this.isFollowBusy,
    required this.isOpeningCall,
    required this.onProfileTap,
    required this.onFollowTap,
    required this.onCallToo,
  });

  @override
  Widget build(BuildContext context) {
    final stake = event.stakeBaseUnits;
    final bucketTone = _bucketColor(event.displayBucket);

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onProfileTap,
                borderRadius: BorderRadius.circular(24.r),
                child: _CallerAvatar(wallet: event.walletAddress, size: 44.w),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: InkWell(
                  onTap: onProfileTap,
                  borderRadius: BorderRadius.circular(10.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 2.h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe ? 'You' : _shortWallet(event.walletAddress),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          '${_eventVerb(event)} • ${_relativeTime(event.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isMe)
                _FollowPill(
                  isFollowing: isFollowing,
                  isBusy: isFollowBusy,
                  onTap: onFollowTap,
                ),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title ?? event.fixtureTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16.sp,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  event.competition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 12.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    _InfoPill(
                      label: event.displayBucket,
                      color: bucketTone,
                      solid: true,
                    ),
                    if (stake != null)
                      _InfoPill(
                        label: ArenaFormat.usdcFromBaseUnits(stake),
                        color: AppColors.textPrimary,
                      ),
                    _InfoPill(
                      label: event.isSettled ? 'Settled' : event.status,
                      color:
                          event.isSettled
                              ? AppColors.success
                              : AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: ChallengeButton(
                  label: isOpeningCall ? 'Opening...' : 'Call too',
                  isLoading: isOpeningCall,
                  createNewChallenge: onCallToo,
                  blurRadius: false,
                ),
              ),
              SizedBox(width: 10.w),
              SizedBox(
                width: 48.w,
                height: 48.h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: IconButton(
                    tooltip: 'Open profile',
                    onPressed: onProfileTap,
                    icon: const PhosphorIcon(PhosphorIconsRegular.user),
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CallerProfileSheet extends StatelessWidget {
  final String wallet;
  final VoidCallback onToggleFollow;

  const _CallerProfileSheet({
    required this.wallet,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.55,
        maxChildSize: 0.94,
        builder: (context, controller) {
          return Consumer2<ArenaProvider, MwaAuthProvider>(
            builder: (context, arena, auth, _) {
              final profile = arena.cachedProfile(wallet);
              final stats = profile?.stats;
              final isMe = auth.walletAddress == wallet;
              final following = arena.isFollowing(wallet);
              final busy = arena.isFollowBusy(wallet);

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(38.r),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 194.h,
                        child: Stack(
                          children: [
                            Container(
                              height: 168.h,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.lightPrimary,
                                    AppColors.primary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: ClipPath(
                                clipper: DetailedWaveClipper(),
                                child: Container(
                                  height: 52.h,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10.h,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  width: 42.w,
                                  height: 5.h,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(99.r),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 54.h,
                              left: 20.w,
                              right: 20.w,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _CallerAvatar(wallet: wallet, size: 76.w),
                                  SizedBox(width: 14.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isMe ? 'You' : _shortWallet(wallet),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 24.sp,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(height: 4.h),
                                        Text(
                                          wallet,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.sp,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isMe)
                                    _FollowPill(
                                      isFollowing: following,
                                      isBusy: busy,
                                      light: true,
                                      onTap: busy ? null : onToggleFollow,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 28.h),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate.fixed([
                          if (!isMe)
                            Padding(
                              padding: EdgeInsets.only(bottom: 14.h),
                              child: ChallengeButton(
                                label:
                                    busy
                                        ? 'Updating...'
                                        : following
                                        ? 'Following'
                                        : 'Follow caller',
                                isLoading: busy,
                                blurRadius: false,
                                createNewChallenge: onToggleFollow,
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: _ProfileStatCard(
                                  label: 'Calls',
                                  value: '${stats?.callsMade ?? 0}',
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: _ProfileStatCard(
                                  label: 'Win rate',
                                  value: ArenaFormat.percent(
                                    stats?.winRate ?? 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10.h),
                          Row(
                            children: [
                              Expanded(
                                child: _ProfileStatCard(
                                  label: 'PnL',
                                  value: _formatSignedUsdc(
                                    stats?.pnlBaseUnits ?? BigInt.zero,
                                  ),
                                  valueColor: _moneyColor(
                                    stats?.pnlBaseUnits ?? BigInt.zero,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: _ProfileStatCard(
                                  label: 'Streak',
                                  value: '${stats?.currentStreak ?? 0}',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14.h),
                          Container(
                            padding: EdgeInsets.all(14.w),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(18.r),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _MiniCount(
                                    label: 'Followers',
                                    value: '${profile?.counts.followers ?? 0}',
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 32.h,
                                  color: AppColors.outlineVariant,
                                ),
                                Expanded(
                                  child: _MiniCount(
                                    label: 'Following',
                                    value: '${profile?.counts.following ?? 0}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 18.h),
                          Text(
                            'Recent calls',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          if ((profile?.activity ?? const []).isEmpty)
                            Text(
                              'No public calls yet.',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            )
                          else
                            ...profile!.activity
                                .take(5)
                                .map(
                                  (event) => Padding(
                                    padding: EdgeInsets.only(bottom: 10.h),
                                    child: _CompactActivityRow(event: event),
                                  ),
                                ),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ProfileStatCard({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w900,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActivityRow extends StatelessWidget {
  final ArenaActivityEvent event;

  const _CompactActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          _InfoPill(
            label: event.displayBucket,
            color: _bucketColor(event.displayBucket),
            solid: true,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title ?? event.fixtureTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _relativeTime(event.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  final String label;
  final String value;

  const _MiniCount({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 3.h),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FollowPill extends StatelessWidget {
  final bool isFollowing;
  final bool isBusy;
  final bool light;
  final VoidCallback? onTap;

  const _FollowPill({
    required this.isFollowing,
    required this.isBusy,
    this.light = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background =
        light
            ? Colors.white.withValues(alpha: 0.18)
            : isFollowing
            ? AppColors.surfaceVariant
            : AppColors.primaryContainer;
    final foreground =
        light
            ? Colors.white
            : isFollowing
            ? AppColors.textPrimary
            : AppColors.primary;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999.r),
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(999.r),
        child: Container(
          height: 34.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          alignment: Alignment.center,
          child:
              isBusy
                  ? SizedBox(
                    width: 14.w,
                    height: 14.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                  : Text(
                    isFollowing ? 'Following' : 'Follow',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w900,
                      color: foreground,
                    ),
                  ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool solid;

  const _InfoPill({
    required this.label,
    required this.color,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w900,
          color: solid ? Colors.white : color,
        ),
      ),
    );
  }
}

class _CallerAvatar extends StatelessWidget {
  final String wallet;
  final double size;

  const _CallerAvatar({required this.wallet, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(2.w),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.lightPrimary, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          _avatarAsset(wallet),
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) => Container(
                color: AppColors.primaryContainer,
                alignment: Alignment.center,
                child: PhosphorIcon(
                  PhosphorIcons.user(),
                  size: size * 0.48,
                  color: AppColors.primary,
                ),
              ),
        ),
      ),
    );
  }
}

class _FeedStateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _FeedStateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 42.sp, color: AppColors.textTertiary),
          SizedBox(height: 12.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 18.h),
          SizedBox(
            width: 160.w,
            child: ChallengeButton(
              label: actionLabel,
              createNewChallenge: () {
                onAction();
              },
              blurRadius: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedSkeletonCard extends StatelessWidget {
  const _FeedSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(width: 44.w, height: 44.w, radius: 99.r),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 118.w, height: 12.h),
                    SizedBox(height: 8.h),
                    _SkeletonBox(width: 84.w, height: 10.h),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18.h),
          _SkeletonBox(width: double.infinity, height: 74.h, radius: 16.r),
          SizedBox(height: 14.h),
          _SkeletonBox(width: double.infinity, height: 42.h, radius: 16.r),
        ],
      ),
    );
  }
}

class _HotCallerSkeleton extends StatelessWidget {
  const _HotCallerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118.w,
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 34.w, height: 34.w, radius: 99.r),
          SizedBox(height: 10.h),
          _SkeletonBox(width: 74.w, height: 10.h),
          SizedBox(height: 8.h),
          _SkeletonBox(width: 92.w, height: 10.h),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double? radius;

  const _SkeletonBox({required this.width, required this.height, this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.outlineVariant.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(radius ?? 8.r),
      ),
    );
  }
}

String _shortWallet(String wallet) {
  if (wallet.length <= 10) return wallet;
  return '${wallet.substring(0, 4)}...${wallet.substring(wallet.length - 4)}';
}

String _relativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time.toLocal());
  if (diff.inSeconds < 45) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('MMM d').format(time.toLocal());
}

String _eventVerb(ArenaActivityEvent event) {
  if (event.type == 'CALL_COPIED') return 'copied a call';
  if (event.isSettled) return 'settled';
  return 'called ${event.displayBucket}';
}

String _formatSignedUsdc(BigInt baseUnits) {
  final amount = baseUnits.toDouble() / 1000000;
  final sign = amount > 0 ? '+' : '';
  return '$sign${NumberFormat.compactCurrency(symbol: '', decimalDigits: 1).format(amount)} USDC';
}

Color _moneyColor(BigInt amount) {
  if (amount > BigInt.zero) return AppColors.success;
  if (amount < BigInt.zero) return AppColors.error;
  return AppColors.textSecondary;
}

Color _bucketColor(String label) {
  switch (label.toUpperCase()) {
    case 'HOME':
      return AppColors.primary;
    case 'DRAW':
      return AppColors.warning;
    case 'AWAY':
      return AppColors.challengeActive;
    default:
      return AppColors.textSecondary;
  }
}

String _avatarAsset(String wallet) {
  final bucket = wallet.codeUnits.fold<int>(0, (sum, code) => sum + code);
  return 'assets/images/ai_gen/profile_images/${(bucket % 5) + 1}.png';
}
