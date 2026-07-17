import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/caller_profile_screen.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class FriendsHubTab extends StatefulWidget {
  final int refreshKey;
  final VoidCallback createNewChallenge;
  final void Function(String, String) onFriendSelected;
  final Widget Function(BuildContext, int) buildViewMoreItem;
  final VoidCallback onViewAllChallenges;
  final Future<void> Function(Map<String, dynamic>, bool)
  onMarkChallengeCompleted;

  const FriendsHubTab({
    super.key,
    required this.refreshKey,
    required this.createNewChallenge,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    required this.onViewAllChallenges,
    required this.onMarkChallengeCompleted,
  });

  @override
  State<FriendsHubTab> createState() => _FriendsHubTabState();
}

class _FriendsHubTabState extends State<FriendsHubTab>
    with AutomaticKeepAliveClientMixin {
  int _selectedIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ArenaProvider>().loadHotCallers();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: const ChumbucketAppHeader(title: 'Friends'),
          ),
          SizedBox(height: 10.h),
          ChumbucketTabs(
            labels: const ['Friends', 'Leaderboard'],
            selectedIndex: _selectedIndex,
            onSelected: (index) => setState(() => _selectedIndex = index),
          ),
          SizedBox(height: 10.h),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: FriendsTab(
                    key: ValueKey(widget.refreshKey),
                    createNewChallenge: widget.createNewChallenge,
                    onFriendSelected: widget.onFriendSelected,
                    buildViewMoreItem: widget.buildViewMoreItem,
                    onViewAllChallenges: widget.onViewAllChallenges,
                    onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
                    showChallengesPreview: false,
                    bottomPadding: 112,
                  ),
                ),
                const _Leaderboard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard();

  @override
  Widget build(BuildContext context) {
    return Consumer<ArenaProvider>(
      builder: (context, arena, _) {
        if (arena.isLoadingHotCallers && arena.hotCallers.isEmpty) {
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 112.h),
            itemCount: 6,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (_, __) => const _LeaderboardSkeleton(),
          );
        }
        if (arena.hotCallers.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(32.w, 100.h, 32.w, 112.h),
            children: [
              const BasilIcon(
                'award-outline',
                size: 42,
                color: AppColors.textTertiary,
              ),
              SizedBox(height: 12.h),
              Text(
                'No ranked callers yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 5.h),
              Text(
                'Settled calls will build the leaderboard.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                ),
              ),
            ],
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: arena.loadHotCallers,
          child: ListView.separated(
            key: const PageStorageKey('social-leaderboard'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 112.h),
            itemCount: arena.hotCallers.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final row = arena.hotCallers[index];
              return _LeaderboardRow(
                rank: index + 1,
                row: row,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => CallerProfileScreen(
                            walletAddress: row.walletAddress,
                          ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final ArenaLeaderboardRow row;
  final VoidCallback onTap;

  const _LeaderboardRow({
    required this.rank,
    required this.row,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: [
              SizedBox(
                width: 28.w,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        rank <= 3 ? AppColors.primary : AppColors.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              CircleAvatar(
                radius: 22.r,
                backgroundColor: AppColors.primaryContainer,
                backgroundImage: AssetImage(_avatarAsset(row.walletAddress)),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shortWallet(row.walletAddress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      '${row.callsMade} calls - ${ArenaFormat.percent(row.winRate)} win rate',
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
              SizedBox(width: 8.w),
              Text(
                _signedPnl(row.pnlBaseUnits),
                style: TextStyle(
                  color: _moneyColor(row.pnlBaseUnits),
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

class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76.h,
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

String _signedPnl(BigInt amount) {
  final value = amount.toDouble() / 1000000;
  final sign = value > 0 ? '+' : '';
  return '$sign${NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 1).format(value)}';
}

Color _moneyColor(BigInt amount) {
  if (amount > BigInt.zero) return AppColors.success;
  if (amount < BigInt.zero) return AppColors.error;
  return AppColors.textSecondary;
}
