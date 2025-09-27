import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'resolve_challenge_sheet.dart';

class ChallengesPreview extends StatefulWidget {
  final VoidCallback onViewAll;
  final Function(Map<String, dynamic>, bool) onMarkChallengeCompleted;

  const ChallengesPreview({
    super.key,
    required this.onViewAll,
    required this.onMarkChallengeCompleted,
  });

  @override
  State<ChallengesPreview> createState() => _ChallengesPreviewState();
}

class _ChallengesPreviewState extends State<ChallengesPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.ease),
    );
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AuthProvider, WalletProvider, ChallengeStateProvider>(
      builder: (context, authProvider, walletProvider, challengeState, child) {
        final walletAddress = walletProvider.walletAddress;
        final currentUser = authProvider.currentUser;

        if (walletAddress == null || currentUser == null) {
          return Column(
            children: [
              _buildShimmerChallenge(),
              SizedBox(height: 12.h),
              _buildShimmerChallenge(),
            ],
          );
        }

        // Initialize challenges if needed
        if (challengeState.challenges.isEmpty && !challengeState.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            challengeState.initialize(
              currentUser.id,
              walletAddress: walletAddress,
            );
          });
        }

        // Show loading state
        if (challengeState.isLoading && challengeState.challenges.isEmpty) {
          return Column(
            children: [
              _buildShimmerChallenge(),
              SizedBox(height: 12.h),
              _buildShimmerChallenge(),
            ],
          );
        }

        final challenges = challengeState.sortedChallenges;

        return Column(
          children: [
            // Show up to 2 challenges or shimmer if empty
            if (challenges.isEmpty) ...[
              _buildShimmerChallenge(),
              SizedBox(height: 12.h),
              _buildShimmerChallenge(),
            ] else ...[
              ...challenges
                  .take(2)
                  .map(
                    (challenge) => Padding(
                      padding: EdgeInsets.only(bottom: 12.h),
                      child: GestureDetector(
                        onTap:
                            challenge.status.toString().split('.').last ==
                                    'pending'
                                ? () => showResolveChallengeSheet(
                                  context,
                                  challenge: challenge.toJson(),
                                  onMarkCompleted:
                                      widget.onMarkChallengeCompleted,
                                )
                                : null,
                        child: _buildChallengePreviewCard(challenge.toJson()),
                      ),
                    ),
                  ),
              if (challenges.length == 1) _buildShimmerChallenge(),
            ],
          ],
        );
      },
    );
  }

  Widget _buildShimmerChallenge() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 70.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            gradient: LinearGradient(
              colors: [
                Colors.grey.shade300,
                Colors.grey.shade100,
                Colors.grey.shade300,
              ],
              begin: Alignment(_animation.value - 1, 0.0),
              end: Alignment(_animation.value, 0.0),
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChallengePreviewCard(Map<String, dynamic> challenge) {
    final status = challenge['status'] as String;
    final isPending = status == 'pending';

    // Prefer showing the description; fall back to title if empty
    final String primaryText =
        (challenge['description'] as String?)?.trim().isNotEmpty == true
            ? (challenge['description'] as String)
            : (challenge['title'] as String? ?? 'Challenge');

    final String friendRaw = challenge['friendName'] ?? 'Unknown';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          PhosphorIcon(
            isPending
                ? PhosphorIconsRegular.circle
                : PhosphorIconsRegular.checkCircle,
            size: 18.w,
            color: isPending ? Colors.orange : Colors.green,
          ),
          SizedBox(width: 12.w),
          // Challenge info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primaryText[0].toUpperCase() + primaryText.substring(1),
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                ResolvedAddressText(
                  addressOrLabel: friendRaw,
                  prefix: 'witnessed by ',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          // Amount
          Text(
            '${challenge['amount']} SOL',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          SizedBox(width: 8.w),
          PhosphorIcon(
            PhosphorIconsRegular.caretRight,
            color: Colors.grey.shade400,
            size: 24.sp,
          ),
        ],
      ),
    );
  }
}
