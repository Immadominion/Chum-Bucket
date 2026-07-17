import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

class CallerProfileScreen extends StatefulWidget {
  final String walletAddress;

  const CallerProfileScreen({super.key, required this.walletAddress});

  @override
  State<CallerProfileScreen> createState() => _CallerProfileScreenState();
}

class _CallerProfileScreenState extends State<CallerProfileScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<ArenaProvider>().loadProfile(
      targetWallet: widget.walletAddress,
      viewerWallet: context.read<MwaAuthProvider>().walletAddress,
    );
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleFollow() async {
    final arena = context.read<ArenaProvider>();
    final wasFollowing = arena.isFollowing(widget.walletAddress);
    try {
      await arena.toggleFollow(
        authProvider: context.read<MwaAuthProvider>(),
        targetWallet: widget.walletAddress,
      );
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: wasFollowing ? 'Unfollowed' : 'Following',
        subtitle:
            wasFollowing
                ? 'This caller was removed from your feed.'
                : 'Their calls will now appear in Following.',
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer2<ArenaProvider, MwaAuthProvider>(
          builder: (context, arena, auth, _) {
            final profile = arena.cachedProfile(widget.walletAddress);
            final isMe = auth.walletAddress == widget.walletAddress;

            if (_isLoading && profile == null) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (profile == null) {
              return _ProfileError(onRetry: _load);
            }

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const PhosphorIcon(
                          PhosphorIconsRegular.caretLeft,
                        ),
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (!isMe)
                        SizedBox(
                          width: 132.w,
                          child: ChallengeButton(
                            label:
                                arena.isFollowing(widget.walletAddress)
                                    ? 'Following'
                                    : 'Follow',
                            isLoading: arena.isFollowBusy(widget.walletAddress),
                            blurRadius: false,
                            createNewChallenge: _toggleFollow,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Center(
                    child: CircleAvatar(
                      radius: 46.r,
                      backgroundColor: AppColors.primaryContainer,
                      backgroundImage: AssetImage(
                        _avatarAsset(widget.walletAddress),
                      ),
                    ),
                  ),
                  SizedBox(height: 14.h),
                  Text(
                    isMe ? 'You' : _shortWallet(widget.walletAddress),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    widget.walletAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                      fontSize: 11.sp,
                    ),
                  ),
                  SizedBox(height: 22.h),
                  _ProfileStats(profile: profile),
                  SizedBox(height: 26.h),
                  Text(
                    'Recent calls',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  if (profile.activity.isEmpty)
                    const _EmptyActivity()
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < profile.activity.length;
                            index++
                          ) ...[
                            _ProfileActivityRow(event: profile.activity[index]),
                            if (index < profile.activity.length - 1)
                              Divider(
                                height: 1,
                                indent: 16.w,
                                endIndent: 16.w,
                                color: AppColors.divider,
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileStats extends StatelessWidget {
  final ArenaSocialProfile profile;

  const _ProfileStats({required this.profile});

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: [
          _Stat(label: 'Calls', value: '${stats?.callsMade ?? 0}'),
          _Stat(
            label: 'Win rate',
            value: ArenaFormat.percent(stats?.winRate ?? 0),
          ),
          _Stat(
            label: 'PnL',
            value: _signedUsdc(stats?.pnlBaseUnits ?? BigInt.zero),
            tone: _moneyColor(stats?.pnlBaseUnits ?? BigInt.zero),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? tone;

  const _Stat({required this.label, required this.value, this.tone});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone ?? AppColors.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.sp),
          ),
        ],
      ),
    );
  }
}

class _ProfileActivityRow extends StatelessWidget {
  final ArenaActivityEvent event;

  const _ProfileActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Container(
            width: 10.w,
            height: 10.w,
            decoration: BoxDecoration(
              color: _bucketColor(event.displayBucket),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title ?? event.fixtureTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  '${event.displayBucket} - ${DateFormat('MMM d').format(event.createdAt.toLocal())}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
          Text(
            event.status,
            style: TextStyle(
              color: event.isSettled ? AppColors.success : AppColors.primary,
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(28.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Center(
        child: Text(
          'No public calls yet.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
        ),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  final VoidCallback onRetry;

  const _ProfileError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PhosphorIcon(
            PhosphorIconsRegular.userCircle,
            color: AppColors.textTertiary,
            size: 42,
          ),
          SizedBox(height: 12.h),
          Text(
            'Could not load this profile',
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
          ),
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

String _signedUsdc(BigInt amount) {
  final value = amount.toDouble() / 1000000;
  final sign = value > 0 ? '+' : '';
  return '$sign${NumberFormat.compactCurrency(symbol: '', decimalDigits: 1).format(value)}';
}

Color _moneyColor(BigInt amount) {
  if (amount > BigInt.zero) return AppColors.success;
  if (amount < BigInt.zero) return AppColors.error;
  return AppColors.textSecondary;
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
