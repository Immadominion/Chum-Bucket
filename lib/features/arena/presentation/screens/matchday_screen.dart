import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/arena_activity_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/dare_yourself_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';

/// Arena matchday list - open fixtures with live pot totals per bucket
/// (HOME/DRAW/AWAY), so a user can see the pool they'd be joining before
/// staking. This is separate from "Challenge a friend": it stakes into a
/// shared match-outcome pot, not a 1-v-1 friend escrow.
class MatchdayScreen extends StatefulWidget {
  const MatchdayScreen({super.key});

  @override
  State<MatchdayScreen> createState() => _MatchdayScreenState();
}

class _MatchdayScreenState extends State<MatchdayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final arena = Provider.of<ArenaProvider>(context, listen: false);
      arena.loadMatchday();
      _warmUpArenaService();
    });
  }

  /// Best-effort pre-warm so the first call screen tap doesn't have to
  /// wait for the Program/IDL to load. Failures here are silent - the Dare
  /// Yourself screen retries and surfaces any real error to the user.
  Future<void> _warmUpArenaService() async {
    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final arena = Provider.of<ArenaProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.walletAddress != null) {
        await arena.ensureArenaService(
          authProvider: authProvider,
          walletAddress: authProvider.walletAddress,
          rpcUrl: NetworkConfig.rpcUrl,
        );
      }
    } catch (_) {
      // Silent - retried when the user actually tries to place a call.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Arena',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.dynamic_feed_outlined,
              color: Colors.black87,
            ),
            tooltip: 'Activity',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArenaActivityScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black87),
            tooltip: 'My Pots',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyPotsScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<ArenaProvider>(
        builder: (context, arena, _) {
          return RefreshIndicator(
            onRefresh: arena.loadMatchday,
            child: _buildBody(arena),
          );
        },
      ),
    );
  }

  Widget _buildBody(ArenaProvider arena) {
    if (arena.isLoadingMatchday && arena.matchday.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (arena.matchdayError != null && arena.matchday.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          Icon(Icons.cloud_off, size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'Could not load matchday.\n${arena.matchdayError}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    final open =
        arena.matchday.where((m) => m.isOpenForCalls).toList()
          ..sort((a, b) => a.fixture.kickoff.compareTo(b.fixture.kickoff));

    if (open.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          Icon(Icons.sports_soccer, size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'No open matches to call right now.\nCheck back soon.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.w),
      itemCount: open.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) => _MatchCard(match: open[index]),
    );
  }
}

class _MatchCard extends StatefulWidget {
  final ArenaMatchEntry match;

  const _MatchCard({required this.match});

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ArenaProvider>().loadMatchCallers(
        matchId: widget.match.fixture.matchId,
        limit: 6,
      );
    });
  }

  Future<void> _showCallers() async {
    final arena = context.read<ArenaProvider>();
    await arena.loadMatchCallers(
      matchId: widget.match.fixture.matchId,
      limit: 100,
      force: true,
    );
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MatchCallersSheet(match: widget.match),
    );
  }

  void _openCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DareYourselfScreen(match: widget.match),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final market = match.resultMarket;

    return GestureDetector(
      onTap: _openCall,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.fixture.competition,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  DateFormat(
                    'E, MMM d - h:mm a',
                  ).format(match.fixture.kickoff.toLocal()),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              match.fixture.title,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 12.h),
            if (market != null) _BucketTotalsRow(market: market),
            SizedBox(height: 12.h),
            Consumer<ArenaProvider>(
              builder: (context, arena, _) {
                final callers = arena.matchCallersFor(match.fixture.matchId);
                return _MatchSocialProofRow(
                  callers: callers,
                  isLoading:
                      arena.isLoadingMatchCallers(match.fixture.matchId) &&
                      callers.isEmpty,
                  hadError: arena.matchCallersHadError(match.fixture.matchId),
                  totalCallers: market?.participantCount ?? callers.length,
                  onTap: _showCallers,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchSocialProofRow extends StatelessWidget {
  final List<ArenaMatchCaller> callers;
  final bool isLoading;
  final bool hadError;
  final int totalCallers;
  final VoidCallback onTap;

  const _MatchSocialProofRow({
    required this.callers,
    required this.isLoading,
    required this.hadError,
    required this.totalCallers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visible = callers.take(4).toList();
    final label =
        hadError
            ? 'Could not load callers'
            : totalCallers > 0
            ? '$totalCallers ${totalCallers == 1 ? 'caller' : 'callers'} on this'
            : 'Be the first caller';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14.r),
      child: Container(
        constraints: BoxConstraints(minHeight: 48.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            if (isLoading)
              SizedBox(
                width: 32.w,
                height: 32.w,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else if (visible.isEmpty)
              Container(
                width: 32.w,
                height: 32.w,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_add_alt_1,
                  size: 16.sp,
                  color: AppColors.primary,
                ),
              )
            else
              SizedBox(
                width: (22.w * visible.length) + 12.w,
                height: 32.w,
                child: Stack(
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      Positioned(
                        left: i * 22.w,
                        child: _CallerAvatar(
                          wallet: visible[i].walletAddress,
                          size: 32.w,
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    visible.isEmpty
                        ? 'Open the caller board'
                        : _bucketSummary(visible),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20.sp,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BucketTotalsRow extends StatelessWidget {
  final ArenaMarket market;

  const _BucketTotalsRow({required this.market});

  @override
  Widget build(BuildContext context) {
    return Row(
      children:
          market.buckets
              .map(
                (bucket) => Expanded(
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 3.w),
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Column(
                      children: [
                        Text(
                          bucket.bucket,
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          ArenaFormat.usdcFromBaseUnits(bucket.stake),
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _MatchCallersSheet extends StatelessWidget {
  final ArenaMatchEntry match;

  const _MatchCallersSheet({required this.match});

  @override
  Widget build(BuildContext context) {
    final matchId = match.fixture.matchId;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, controller) {
          return Consumer<ArenaProvider>(
            builder: (context, arena, _) {
              final callers = arena.matchCallersFor(matchId);
              final isLoading = arena.isLoadingMatchCallers(matchId);

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
                      child: _CallersSheetHeader(match: match),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 28.h),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          ChallengeButton(
                            label: 'Call this match',
                            blurRadius: false,
                            createNewChallenge: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => DareYourselfScreen(match: match),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: 18.h),
                          Text(
                            'Caller board',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          if (isLoading && callers.isEmpty)
                            ...List.generate(
                              4,
                              (_) => Padding(
                                padding: EdgeInsets.only(bottom: 10.h),
                                child: const _CallerRowSkeleton(),
                              ),
                            )
                          else if (callers.isEmpty)
                            _EmptyCallers(match: match)
                          else
                            ...callers.map(
                              (caller) => Padding(
                                padding: EdgeInsets.only(bottom: 10.h),
                                child: _CallerRow(caller: caller),
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

class _CallersSheetHeader extends StatelessWidget {
  final ArenaMatchEntry match;

  const _CallersSheetHeader({required this.match});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190.h,
      child: Stack(
        children: [
          Container(
            height: 164.h,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.lightPrimary, AppColors.primary],
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
              child: Container(height: 52.h, color: Colors.white),
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
            top: 48.h,
            left: 22.w,
            right: 22.w,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.fixture.competition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  match.fixture.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24.sp,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  DateFormat(
                    'E, MMM d - h:mm a',
                  ).format(match.fixture.kickoff.toLocal()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.86),
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

class _CallerRow extends StatelessWidget {
  final ArenaMatchCaller caller;

  const _CallerRow({required this.caller});

  @override
  Widget build(BuildContext context) {
    final payout = caller.payoutBaseUnits;
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          _CallerAvatar(wallet: caller.walletAddress, size: 42.w),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caller.handle ?? _shortWallet(caller.walletAddress),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  '${ArenaFormat.usdcFromBaseUnits(caller.stakeBaseUnits)} • ${_relativeTime(caller.placedAt)}',
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
          SizedBox(width: 8.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _BucketPill(bucket: caller.bucket),
              if (payout != null) ...[
                SizedBox(height: 4.h),
                Text(
                  ArenaFormat.usdcFromBaseUnits(payout),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BucketPill extends StatelessWidget {
  final String bucket;

  const _BucketPill({required this.bucket});

  @override
  Widget build(BuildContext context) {
    final color = _bucketColor(bucket);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        bucket,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5.sp,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _EmptyCallers extends StatelessWidget {
  final ArenaMatchEntry match;

  const _EmptyCallers({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Column(
        children: [
          Icon(Icons.campaign_outlined, size: 34.sp, color: AppColors.primary),
          SizedBox(height: 10.h),
          Text(
            'No public calls yet',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Start the board for ${match.fixture.home} vs ${match.fixture.away}.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallerRowSkeleton extends StatelessWidget {
  const _CallerRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68.h,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          _SkeletonBox(width: 42.w, height: 42.w, radius: 99.r),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkeletonBox(width: 120.w, height: 12.h),
                SizedBox(height: 8.h),
                _SkeletonBox(width: 160.w, height: 10.h),
              ],
            ),
          ),
          _SkeletonBox(width: 54.w, height: 26.h, radius: 99.r),
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
        color: AppColors.outlineVariant.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(radius ?? 8.r),
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
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
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
                child: Icon(
                  Icons.person_outline,
                  size: size * 0.48,
                  color: AppColors.primary,
                ),
              ),
        ),
      ),
    );
  }
}

String _bucketSummary(List<ArenaMatchCaller> callers) {
  final counts = <String, int>{};
  for (final caller in callers) {
    counts[caller.bucket] = (counts[caller.bucket] ?? 0) + 1;
  }
  return counts.entries.map((e) => '${e.value} ${e.key}').join(' • ');
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
