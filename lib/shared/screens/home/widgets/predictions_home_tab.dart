import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/dare_yourself_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/presentation/widgets/match_callers_sheet.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_preview.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

class PredictionsHomeTab extends StatefulWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onViewCalls;
  final VoidCallback onViewChallenges;
  final Future<void> Function(Map<String, dynamic>, bool)
  onMarkChallengeCompleted;

  const PredictionsHomeTab({
    super.key,
    required this.onProfileTap,
    required this.onViewCalls,
    required this.onViewChallenges,
    required this.onMarkChallengeCompleted,
  });

  @override
  State<PredictionsHomeTab> createState() => _PredictionsHomeTabState();
}

class _PredictionsHomeTabState extends State<PredictionsHomeTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final arena = context.read<ArenaProvider>();
    final auth = context.read<MwaAuthProvider>();
    final wallet = auth.walletAddress;

    final requests = <Future<void>>[arena.loadMatchday()];
    if (wallet != null) {
      requests.add(arena.loadClaimable(walletAddress: wallet));
      requests.add(arena.loadMyPots(walletAddress: wallet));
      requests.add(
        ChallengeStateProvider.instance.softRefresh(wallet).catchError((_) {}),
      );
      try {
        await arena.ensureArenaService(
          authProvider: auth,
          walletAddress: wallet,
          rpcUrl: NetworkConfig.rpcUrl,
        );
      } catch (_) {
        // The transaction screen retries and reports a useful wallet error.
      }
    }
    await Future.wait(requests);
  }

  void _openMatch(ArenaMatchEntry match) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DareYourselfScreen(match: match)));
  }

  Future<void> _openCallers(ArenaMatchEntry match) async {
    final arena = context.read<ArenaProvider>();
    await arena.loadMatchCallers(
      matchId: match.fixture.matchId,
      limit: 100,
      force: true,
    );
    if (!mounted) return;
    await showChumbucketWavySheet<void>(
      context: context,
      builder:
          (sheetContext) => MatchCallersSheet(
            match: match,
            onCallMatch: () {
              Navigator.of(sheetContext).pop();
              _openMatch(match);
            },
          ),
    );
  }

  void _openPositions() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyPotsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: Consumer<ArenaProvider>(
        builder: (context, arena, _) {
          final matches =
              arena.matchday.where((match) => match.isOpenForCalls).toList()
                ..sort(
                  (a, b) => a.fixture.kickoff.compareTo(b.fixture.kickoff),
                );

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: CustomScrollView(
              key: const PageStorageKey('predictions-home'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
                  sliver: SliverToBoxAdapter(
                    child: homeScreenHeader(
                      context,
                      onProfileTap: widget.onProfileTap,
                    ),
                  ),
                ),
                if (arena.claimablePositions.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
                    sliver: SliverToBoxAdapter(
                      child: _ClaimableStrip(
                        count: arena.claimablePositions.length,
                        onTap: _openPositions,
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20.w, 2.h, 20.w, 12.h),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: "Today's markets",
                      action: 'See calls',
                      onAction: widget.onViewCalls,
                    ),
                  ),
                ),
                if (arena.isLoadingMatchday && matches.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    sliver: SliverList.separated(
                      itemCount: 3,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (_, __) => const _MarketSkeleton(),
                    ),
                  )
                else if (arena.matchdayError != null && matches.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    sliver: SliverToBoxAdapter(
                      child: _HomeState(
                        icon: PhosphorIconsRegular.broadcast,
                        title: 'Markets are taking a moment',
                        detail: 'Pull down to try again.',
                        onTap: _load,
                      ),
                    ),
                  )
                else if (matches.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    sliver: const SliverToBoxAdapter(
                      child: _HomeState(
                        icon: Icons.sports_soccer_outlined,
                        title: 'No open markets right now',
                        detail:
                            'New fixtures will appear here when calls open.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    sliver: SliverList.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder:
                          (context, index) => _MarketRow(
                            match: matches[index],
                            onTap: () => _openMatch(matches[index]),
                            onCallers: () => _openCallers(matches[index]),
                          ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20.w, 28.h, 20.w, 12.h),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Your challenges',
                      action: 'View all',
                      onAction: widget.onViewChallenges,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  sliver: SliverToBoxAdapter(
                    child: ChallengesPreview(
                      onViewAll: widget.onViewChallenges,
                      onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: 112.h)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _SectionHeader({this.action, this.onAction, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              action!,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _ClaimableStrip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ClaimableStrip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: PhosphorIcon(
                    PhosphorIconsFill.checkCircle,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${count == 1 ? 'win is' : 'wins are'} ready',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Claim from your prediction history',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const PhosphorIcon(
                PhosphorIconsRegular.caretRight,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final ArenaMatchEntry match;
  final VoidCallback onTap;
  final VoidCallback onCallers;

  const _MarketRow({
    required this.match,
    required this.onTap,
    required this.onCallers,
  });

  @override
  Widget build(BuildContext context) {
    final market = match.resultMarket;
    final localKickoff = match.fixture.kickoff.toLocal();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      match.fixture.competition,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('E, h:mm a').format(localKickoff),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                match.fixture.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17.sp,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (market != null && market.buckets.isNotEmpty) ...[
                SizedBox(height: 14.h),
                Row(
                  children:
                      market.buckets.map((bucket) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: bucket == market.buckets.last ? 0 : 6.w,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 9.h,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    bucket.bucket,
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    ArenaFormat.usdcFromBaseUnits(bucket.stake),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
              SizedBox(height: 12.h),
              InkWell(
                onTap: onCallers,
                borderRadius: BorderRadius.circular(12.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  child: Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIconsRegular.usersThree,
                        size: 17.w,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          market == null || market.participantCount == 0
                              ? 'Be the first to call it'
                              : '${market.participantCount} ${market.participantCount == 1 ? 'caller' : 'callers'}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const PhosphorIcon(
                        PhosphorIconsRegular.caretRight,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  const _HomeState({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        children: [
          PhosphorIcon(icon, size: 30.w, color: AppColors.textTertiary),
          SizedBox(height: 10.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4.h),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
          ),
          if (onTap != null) ...[
            SizedBox(height: 8.h),
            TextButton(onPressed: onTap, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

class _MarketSkeleton extends StatelessWidget {
  const _MarketSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 158.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
    );
  }
}
