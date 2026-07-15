import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';
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
    // DON'T initialize ChallengeStateProvider here - HomeScreen does it
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<
      MwaAuthProvider,
      MwaWalletProvider,
      ChallengeStateProvider
    >(
      builder: (context, authProvider, walletProvider, challengeState, child) {
        final walletAddress = walletProvider.walletAddress;
        final userWalletAddress = authProvider.walletAddress;

        if (walletAddress == null || userWalletAddress == null) {
          return Column(
            children: [
              _buildShimmerChallenge(),
              SizedBox(height: 12.h),
              _buildShimmerChallenge(),
            ],
          );
        }

        // DON'T initialize in build - it causes infinite loops
        // Initialize is done by HomeScreen

        // Show loading state ONLY while actively loading
        if (challengeState.isLoading) {
          return Column(
            children: [
              _buildShimmerChallenge(),
              SizedBox(height: 12.h),
              _buildShimmerChallenge(),
            ],
          );
        }

        final challenges = challengeState.sortedChallenges;

        // If no challenges after loading is complete, show empty state (no shimmer)
        if (challenges.isEmpty) {
          return _buildEmptyChallengesState();
        }

        return Column(
          children: [
            // Show up to 2 challenges
            ...challenges.take(2).map((challenge) {
              final statusStr = challenge.status.toString().split('.').last;
              final isInteractable = ChallengeStatusUtils.isResolvable(
                statusStr,
              );
              // Check if current user is the witness
              final isCurrentUserWitness =
                  challenge.witnessAddress == userWalletAddress;
              final challengeJson = challenge.toJson();
              // Add isCurrentUserWitness flag for UI
              challengeJson['isCurrentUserWitness'] = isCurrentUserWitness;
              if (isCurrentUserWitness) {
                challengeJson['friendName'] = 'You';
              }

              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: GestureDetector(
                  onTap:
                      isInteractable
                          ? () => showResolveChallengeSheet(
                            context,
                            challenge: challengeJson,
                            onMarkCompleted: widget.onMarkChallengeCompleted,
                          )
                          : null,
                  child: _buildChallengePreviewCard(
                    challengeJson,
                    userWalletAddress,
                  ),
                ),
              );
            }),
            // Removed shimmer placeholder - it looked like endless loading
          ],
        );
      },
    );
  }

  // Empty state when no challenges exist
  Widget _buildEmptyChallengesState() {
    return buildNoChallengesView();
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

  Widget _buildChallengePreviewCard(
    Map<String, dynamic> challenge,
    String? currentUserWallet,
  ) {
    final status = challenge['status'] as String;
    final isCurrentUserWitness = challenge['isCurrentUserWitness'] == true;

    // Use shared utility for consistent status display
    final statusIcon = ChallengeStatusUtils.getStatusIcon(status);
    final statusColor = ChallengeStatusUtils.getStatusColor(status);

    // Prefer showing the description; fall back to title if empty
    final String primaryText =
        (challenge['description'] as String?)?.trim().isNotEmpty == true
            ? (challenge['description'] as String)
            : (challenge['title'] as String? ?? 'Challenge');

    // If current user is witness, show "You"
    final String friendRaw =
        isCurrentUserWitness
            ? 'You'
            : (challenge['witness_display_name'] ??
                challenge['friendName'] ??
                challenge['witness_address'] ??
                challenge['member2_address'] ??
                'Unknown');

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
          PhosphorIcon(statusIcon, size: 18.w, color: statusColor),
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
                // If friendRaw is "You", show directly without resolution
                isCurrentUserWitness || friendRaw == 'You'
                    ? Text(
                      'witnessed by You',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                    : ResolvedAddressText(
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
          // Amount - format to avoid long decimals
          Text(
            '${_formatAmount(challenge['amount'])} SOL',
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

  /// Format amount to display nicely
  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final value =
        (amount is num)
            ? amount.toDouble()
            : double.tryParse(amount.toString()) ?? 0.0;
    // Remove trailing zeros and limit to 4 decimal places
    if (value == value.truncate()) {
      return value.truncate().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
