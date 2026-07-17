import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

class MatchCallersSheet extends StatelessWidget {
  final ArenaMatchEntry match;
  final VoidCallback onCallMatch;

  const MatchCallersSheet({
    super.key,
    required this.match,
    required this.onCallMatch,
  });

  @override
  Widget build(BuildContext context) {
    final matchId = match.fixture.matchId;
    return ChumbucketWavySheet(
      title: match.fixture.title,
      subtitle: match.fixture.competition,
      height: MediaQuery.sizeOf(context).height * 0.76,
      body: Consumer<ArenaProvider>(
        builder: (context, arena, _) {
          final callers = arena.matchCallersFor(matchId);
          final loading = arena.isLoadingMatchCallers(matchId);
          final hadError = arena.matchCallersHadError(matchId);
          return Column(
            children: [
              Expanded(
                child:
                    loading && callers.isEmpty
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                        : hadError && callers.isEmpty
                        ? _CallersState(
                          title: 'Could not load callers',
                          onRetry:
                              () => arena.loadMatchCallers(
                                matchId: matchId,
                                limit: 100,
                                force: true,
                              ),
                        )
                        : callers.isEmpty
                        ? const _CallersState(
                          title: 'Be the first to call this match',
                        )
                        : ListView.separated(
                          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
                          itemCount: callers.length,
                          separatorBuilder:
                              (_, __) =>
                                  Divider(height: 1, color: AppColors.divider),
                          itemBuilder:
                              (context, index) =>
                                  _CallerRow(caller: callers[index]),
                        ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 20.h),
                child: ChallengeButton(
                  label: 'Call this match',
                  blurRadius: false,
                  createNewChallenge: onCallMatch,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CallerRow extends StatelessWidget {
  final ArenaMatchCaller caller;

  const _CallerRow({required this.caller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21.r,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: AssetImage(_avatarAsset(caller.walletAddress)),
          ),
          SizedBox(width: 12.w),
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  '${ArenaFormat.usdcFromBaseUnits(caller.stakeBaseUnits)} - ${DateFormat('MMM d, h:mm a').format(caller.placedAt.toLocal())}',
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
          SizedBox(width: 10.w),
          Text(
            caller.bucket,
            style: TextStyle(
              color: _bucketColor(caller.bucket),
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallersState extends StatelessWidget {
  final String title;
  final VoidCallback? onRetry;

  const _CallersState({required this.title, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
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
