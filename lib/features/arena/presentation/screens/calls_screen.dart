import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/caller_profile_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/dare_yourself_screen.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen>
    with AutomaticKeepAliveClientMixin {
  String? _openingMatchId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({ArenaFeedMode? mode}) async {
    final arena = context.read<ArenaProvider>();
    final wallet = context.read<MwaAuthProvider>().walletAddress;
    final requests = <Future<void>>[
      arena.loadActivity(walletAddress: wallet, mode: mode ?? arena.feedMode),
    ];
    if (wallet != null) {
      requests.add(arena.loadSocialInbox(walletAddress: wallet));
      requests.add(arena.subscribeNotifications(walletAddress: wallet));
    }
    await Future.wait(requests);
  }

  Future<void> _openCall(ArenaActivityEvent event) async {
    final matchId = event.matchId;
    if (matchId == null || matchId.isEmpty) {
      SnackBarUtils.showInfo(
        context,
        title: 'No market attached',
        subtitle: 'This call cannot be copied yet.',
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
      final copied = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => DareYourselfScreen(match: match)),
      );
      if (copied == true && mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not open call',
        subtitle: error.toString(),
      );
    } finally {
      if (mounted) setState(() => _openingMatchId = null);
    }
  }

  void _openProfile(String wallet) {
    if (wallet.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallerProfileScreen(walletAddress: wallet),
      ),
    );
  }

  Future<void> _toggleFollow(String wallet) async {
    final arena = context.read<ArenaProvider>();
    final wasFollowing = arena.isFollowing(wallet);
    try {
      await arena.toggleFollow(
        authProvider: context.read<MwaAuthProvider>(),
        targetWallet: wallet,
      );
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: wasFollowing ? 'Unfollowed' : 'Following',
        subtitle:
            wasFollowing
                ? 'This caller was removed from your feed.'
                : 'Their calls will appear in Following.',
      );
    } catch (error) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not update follow',
        subtitle: error.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: Consumer2<ArenaProvider, MwaAuthProvider>(
        builder: (context, arena, auth, _) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: CustomScrollView(
              key: const PageStorageKey('calls-feed'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
                  sliver: const SliverToBoxAdapter(
                    child: ChumbucketAppHeader(title: 'Calls'),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 14.h),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.center,
                      child: ChumbucketTabs(
                        labels: const ['Global', 'Following'],
                        selectedIndex:
                            arena.feedMode == ArenaFeedMode.global ? 0 : 1,
                        onSelected: (index) {
                          if (index == 1 && auth.walletAddress == null) return;
                          _load(
                            mode:
                                index == 0
                                    ? ArenaFeedMode.global
                                    : ArenaFeedMode.following,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (arena.activityError != null && arena.activity.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CallsState(
                      icon: 'cloud-off-outline',
                      title: 'Could not load calls',
                      detail: 'Pull down or try again.',
                      action: _load,
                    ),
                  )
                else if (arena.isLoadingActivity && arena.activity.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    sliver: SliverList.separated(
                      itemCount: 4,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (_, __) => const _CallSkeleton(),
                    ),
                  )
                else if (arena.activity.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CallsState(
                      icon: 'hotspot-outline',
                      title:
                          arena.feedMode == ArenaFeedMode.following
                              ? 'Your following feed is quiet'
                              : 'No calls yet',
                      detail:
                          arena.feedMode == ArenaFeedMode.following
                              ? 'Follow a caller from their profile to build this feed.'
                              : 'The first public prediction will appear here.',
                      action: _load,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 112.h),
                    sliver: SliverList.separated(
                      itemCount: arena.activity.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (context, index) {
                        final event = arena.activity[index];
                        final isMe = event.walletAddress == auth.walletAddress;
                        return _CallCard(
                          event: event,
                          isMe: isMe,
                          isFollowing: arena.isFollowing(event.walletAddress),
                          isFollowBusy: arena.isFollowBusy(event.walletAddress),
                          isOpening:
                              _openingMatchId != null &&
                              _openingMatchId == event.matchId,
                          onProfile: () => _openProfile(event.walletAddress),
                          onFollow:
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

class _CallCard extends StatelessWidget {
  final ArenaActivityEvent event;
  final bool isMe;
  final bool isFollowing;
  final bool isFollowBusy;
  final bool isOpening;
  final VoidCallback onProfile;
  final VoidCallback? onFollow;
  final VoidCallback onCallToo;

  const _CallCard({
    required this.event,
    required this.isMe,
    required this.isFollowing,
    required this.isFollowBusy,
    required this.isOpening,
    required this.onProfile,
    required this.onFollow,
    required this.onCallToo,
  });

  @override
  Widget build(BuildContext context) {
    final stake = event.stakeBaseUnits;
    final bucket = event.displayBucket.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onProfile,
                  borderRadius: BorderRadius.circular(24.r),
                  child: CircleAvatar(
                    radius: 20.r,
                    backgroundColor: AppColors.primaryContainer,
                    backgroundImage: AssetImage(
                      _avatarAsset(event.walletAddress),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: InkWell(
                    onTap: onProfile,
                    borderRadius: BorderRadius.circular(10.r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe ? 'You' : _shortWallet(event.walletAddress),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          '${_eventVerb(event)} - ${_relativeTime(event.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isMe)
                  TextButton(
                    onPressed: isFollowBusy ? null : onFollow,
                    child:
                        isFollowBusy
                            ? SizedBox(
                              width: 14.w,
                              height: 14.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                            : Text(isFollowing ? 'Following' : 'Follow'),
                  ),
              ],
            ),
            SizedBox(height: 12.h),
            // The fixture (who's playing) is the useful, scannable info —
            // it's the headline. The activity type ("Call placed", "Winnings
            // claimed", ...) already reads in the subtitle above, so it
            // doesn't need its own line here too; neither does the
            // competition name, which was almost always the generic
            // "Prediction" fallback anyway.
            Text(
              event.fixtureTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                if (bucket.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 7.h,
                    ),
                    decoration: BoxDecoration(
                      color: _bucketColor(bucket).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      bucket,
                      style: TextStyle(
                        color: _bucketColor(bucket),
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (stake != null) ...[
                  if (bucket.isNotEmpty) SizedBox(width: 10.w),
                  Text(
                    ArenaFormat.usdcFromBaseUnits(stake),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                // "Call too" is a compact pill on the meta row (not a
                // full-width CTA per card) so the feed stays dense — more
                // calls visible without scrolling.
                if (!event.isSettled && event.matchId?.isNotEmpty == true)
                  _CompactCallToo(isLoading: isOpening, onTap: onCallToo)
                else
                  Text(
                    event.isSettled ? 'SETTLED' : event.status,
                    style: TextStyle(
                      color:
                          event.isSettled
                              ? AppColors.success
                              : AppColors.textSecondary,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactCallToo extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _CompactCallToo({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 12.sp,
                  height: 12.sp,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else
                BasilIcon(
                  'hotspot-solid',
                  color: Colors.white,
                  size: 13.sp,
                ),
              SizedBox(width: 6.w),
              Text(
                isLoading ? 'Opening' : 'Call too',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallsState extends StatelessWidget {
  final String icon;
  final String title;
  final String detail;
  final VoidCallback action;

  const _CallsState({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BasilIcon(icon, size: 40.w, color: AppColors.textTertiary),
            SizedBox(height: 12.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 5.h),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
            ),
            SizedBox(height: 8.h),
            TextButton(onPressed: action, child: const Text('Refresh')),
          ],
        ),
      ),
    );
  }
}

class _CallSkeleton extends StatelessWidget {
  const _CallSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 168.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
    );
  }
}

String _shortWallet(String wallet) {
  if (wallet.length <= 10) return wallet;
  return '${wallet.substring(0, 4)}...${wallet.substring(wallet.length - 4)}';
}

String _avatarAsset(String wallet) {
  final bucket = wallet.codeUnits.fold<int>(0, (sum, code) => sum + code);
  return 'assets/images/ai_gen/profile_images/${(bucket % 5) + 1}.png';
}

String _relativeTime(DateTime time) {
  final difference = DateTime.now().difference(time.toLocal());
  if (difference.inSeconds < 45) return 'now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return DateFormat('MMM d').format(time.toLocal());
}

String _eventVerb(ArenaActivityEvent event) {
  switch (event.type) {
    case 'CALL_COPIED':
      return 'copied a call';
    case 'CALL_SETTLED':
      return 'call settled';
    case 'CLAIMED':
      return 'claimed winnings';
    default:
      return 'called ${event.displayBucket}';
  }
}

Color _bucketColor(String bucket) {
  switch (bucket.toUpperCase()) {
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
