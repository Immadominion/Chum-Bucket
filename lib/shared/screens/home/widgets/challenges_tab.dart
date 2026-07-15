import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';
import 'package:chumbucket/core/config/network_config.dart';
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
    _lastRefreshKey = widget.refreshKey;
    // DON'T initialize here - HomeScreen does it
  }

  @override
  void didUpdateWidget(ChallengesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only trigger refresh on EXPLICIT key change (from pull-to-refresh)
    // AND only if the key actually changed from a valid previous value
    if (widget.refreshKey != _lastRefreshKey && _lastRefreshKey != -1) {
      _lastRefreshKey = widget.refreshKey;
      // DON'T call _forceRefresh here - let the pull-to-refresh handler do it
      // This prevents duplicate syncs
    }
  }

  /// Open the transaction or account on explorer for completed challenges
  Future<void> _openExplorer(Map<String, dynamic> challengeData) async {
    // Prefer transaction signature over escrow address
    final txSig = challengeData['transaction_signature'] as String?;
    final escrowAddress = challengeData['escrowAddress'] as String?;

    String url;
    if (txSig != null && txSig.isNotEmpty) {
      // View transaction
      url = NetworkConfig.getExplorerUrl(txSig);
    } else if (escrowAddress != null && escrowAddress.isNotEmpty) {
      // View account (escrow address)
      url = NetworkConfig.getAccountExplorerUrl(escrowAddress);
    } else {
      // No explorer link available - fallback to modal
      showResolveChallengeSheet(
        context,
        challenge: challengeData,
        onMarkCompleted: widget.onMarkChallengeCompleted,
      );
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to open explorer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChallengeStateProvider, MwaAuthProvider>(
      builder: (context, challengeState, authProvider, child) {
        final currentUserWallet = authProvider.walletAddress;

        // Show shimmer while loading or syncing
        if (challengeState.isLoading || challengeState.isSyncing) {
          return const ShimmerChallenges();
        }

        final challenges = challengeState.sortedChallenges;

        if (challenges.isEmpty) {
          return buildNoChallengesView(withText: true);
        }

        // Render challenges list
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
            child: Column(
              children: [
                ...challenges.map((challenge) {
                  final challengeData = _challengeToMap(
                    challenge,
                    currentUserWallet,
                  );
                  final status =
                      challenge.status.toString().split('.').last.toLowerCase();
                  final isCompleted = status == 'completed';

                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12.r),
                      onTap: () {
                        if (ChallengeStatusUtils.isResolvable(status)) {
                          // Pending challenges - open resolve modal
                          showResolveChallengeSheet(
                            context,
                            challenge: challengeData,
                            onMarkCompleted: widget.onMarkChallengeCompleted,
                          );
                        } else if (isCompleted) {
                          // Completed challenges - open explorer directly
                          _openExplorer(challengeData);
                        }
                      },
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
  Map<String, dynamic> _challengeToMap(
    Challenge challenge,
    String? currentUserWallet,
  ) {
    // Debug: Log escrow address from Challenge model
    debugPrint(
      '🔍 DEBUG _challengeToMap: id=${challenge.id}, escrowAddress=${challenge.escrowAddress}, witnessAddress=${challenge.witnessAddress}',
    );

    // Determine display name - show "You" if current user is the witness
    final isCurrentUserWitness =
        currentUserWallet != null &&
        challenge.witnessAddress == currentUserWallet;
    final displayName =
        isCurrentUserWitness ? 'You' : _getFriendDisplayName(challenge);

    return {
      'id': challenge.id,
      'title': challenge.title,
      'description': challenge.description,
      'amount': challenge.amount,
      'status': challenge.status.toString().split('.').last,
      'createdAt': challenge.createdAt,
      'expiresAt': challenge.expiresAt,
      'friendName': displayName,
      'isCurrentUserWitness': isCurrentUserWitness,
      'source': 'reactive_state',
      // Include all address fields for resolution
      'escrowAddress': challenge.escrowAddress,
      'multisig_address': challenge.escrowAddress,
      'creator_privy_id': challenge.creatorId,
      // CRITICAL: Use member1Address (wallet) not creatorId (may be UUID)
      'member1_address': challenge.member1Address,
      'creator_wallet_address': challenge.member1Address,
      // CRITICAL: Include witness address for resolution
      'member2_address': challenge.witnessAddress,
      'witness_address': challenge.witnessAddress,
      'witness_display_name': challenge.witnessDisplayName,
      'participantId': challenge.participantId,
      // Fee info for UI
      'winner_amount_sol': challenge.winnerAmount,
      'platform_fee_sol': challenge.platformFee,
      // Transaction signature for viewing on explorer
      'transaction_signature': challenge.transactionSignature,
    };
  }

  /// Get display name for friend/participant
  /// Priority: cached display name > email > shortened wallet address
  String _getFriendDisplayName(Challenge challenge) {
    // FIRST: Use cached display name from database (SNS domain or full_name)
    // This avoids expensive client-side RPC lookups
    if (challenge.witnessDisplayName?.isNotEmpty == true) {
      return challenge.witnessDisplayName!;
    }
    // Then try participant email
    if (challenge.participantEmail?.isNotEmpty == true &&
        !_looksLikeWalletAddress(challenge.participantEmail!)) {
      return challenge.participantEmail!;
    }
    // Fallback to shortened wallet address (will be resolved by ResolvedAddressText widget)
    if (challenge.witnessAddress?.isNotEmpty == true) {
      return challenge.witnessAddress!;
    }
    // Then participant ID
    if (challenge.participantId?.isNotEmpty == true) {
      return challenge.participantId!.substring(
        0,
        8,
      ); // Show first 8 chars of ID
    }
    return 'Unknown';
  }

  /// Check if string looks like a Solana wallet address (base58, 32-44 chars)
  bool _looksLikeWalletAddress(String value) {
    if (value.length < 32 || value.length > 50) return false;
    // Base58 charset check
    return RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(value);
  }
}

Widget buildNoChallengesView({withText = false}) {
  return SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        withText ? SizedBox(height: 80.h) : SizedBox.shrink(),
        LottieBuilder.asset(
          'assets/animations/lottie/done.json',
          width: withText ? 150.w : 100.w,
          height: withText ? 150.w : 100.w,
          fit: BoxFit.contain,
        ),
        SizedBox(height: 16.h),
        withText
            ? Text(
              'No challenges yet',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            )
            : SizedBox(),
        withText ? SizedBox(height: 8.h) : SizedBox.shrink(),
        withText
            ? Text(
              'Create your first challenge!',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            )
            : SizedBox(),
      ],
    ),
  );
}
