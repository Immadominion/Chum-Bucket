import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'challenge_card.dart';
import 'shimmer_challenges.dart';
import 'resolve_challenge_sheet.dart';

class ChallengesTab extends StatefulWidget {
  final int refreshKey;
  final Function(Map<String, dynamic>, bool) onMarkChallengeCompleted;

  const ChallengesTab({
    super.key,
    required this.refreshKey,
    required this.onMarkChallengeCompleted,
  });

  @override
  State<ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<ChallengesTab> {
  int _lastRefreshKey = -1;

  @override
  void initState() {
    super.initState();
    _initializeProvider();
  }

  @override
  void didUpdateWidget(ChallengesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh if the refresh key actually changed
    if (widget.refreshKey != _lastRefreshKey) {
      _lastRefreshKey = widget.refreshKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _forceRefresh();
      });
    }
  }

  void _initializeProvider() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final currentUser = authProvider.currentUser;

      if (currentUser != null && mounted) {
        ChallengeStateProvider.instance.initialize(
          currentUser.id,
          walletAddress: walletProvider.walletAddress,
        );
      }
    });
  }

  void _forceRefresh() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser != null && walletProvider.walletAddress != null) {
      ChallengeStateProvider.instance.forceRefresh(
        currentUser.id,
        walletProvider.walletAddress!,
      );
    } else {
      // Soft refresh if no wallet
      ChallengeStateProvider.instance.softRefresh(currentUser?.id ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChallengeStateProvider>(
      builder: (context, challengeState, child) {
        // Show shimmer while loading or syncing
        if (challengeState.isLoading || challengeState.isSyncing) {
          return const ShimmerChallenges();
        }

        final challenges = challengeState.sortedChallenges;

        if (challenges.isEmpty) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 80.h),
                LottieBuilder.asset(
                  'assets/animations/lottie/done.json',
                  width: 150.w,
                  height: 150.w,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 16.h),
                Text(
                  'No challenges yet',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Create your first challenge!',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        // Render challenges list
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
            child: Column(
              children: [
                ...challenges.map((challenge) {
                  final challengeData = _challengeToMap(challenge);
                  final status =
                      challenge.status.toString().split('.').last.toLowerCase();

                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12.r),
                      onTap:
                          status == 'pending'
                              ? () => showResolveChallengeSheet(
                                context,
                                challenge: challengeData,
                                onMarkCompleted:
                                    widget.onMarkChallengeCompleted,
                              )
                              : null,
                      child: ChallengeCard(
                        challenge: challengeData,
                        onMarkCompleted: widget.onMarkChallengeCompleted,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Convert Challenge model to Map for compatibility with existing UI
  Map<String, dynamic> _challengeToMap(Challenge challenge) {
    return {
      'id': challenge.id,
      'title': challenge.title,
      'description': challenge.description,
      'amount': challenge.amount,
      'status': challenge.status.toString().split('.').last,
      'createdAt': challenge.createdAt,
      'expiresAt': challenge.expiresAt,
      'friendName': _getFriendDisplayName(challenge),
      'source': 'reactive_state',
      'escrowAddress': challenge.escrowAddress,
    };
  }

  /// Get display name for friend/participant
  String _getFriendDisplayName(Challenge challenge) {
    if (challenge.participantEmail?.isNotEmpty == true) {
      return challenge.participantEmail!;
    }
    if (challenge.participantId?.isNotEmpty == true) {
      return challenge.participantId!.substring(
        0,
        8,
      ); // Show first 8 chars of ID
    }
    return 'Unknown';
  }
}
