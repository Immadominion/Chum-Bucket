import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
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
          return buildNoChallengesView(
            withText: true,
            title:
                currentUserWallet == null
                    ? 'Connect your wallet to see them'
                    : 'No escrow challenges',
            message:
                currentUserWallet == null
                    ? 'Escrow challenges are kept by wallet. Connect the '
                        'wallet you used for them to see them here.'
                    : 'This wallet has none from before calls.',
          );
        }

        // Every row opens its sheet: an open one with the witness's settle
        // actions (or whose move it is), a settled one with how it ended and
        // its Solscan link. Pull down to re-read the list.
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            if (currentUserWallet != null) {
              await challengeState.softRefresh(currentUserWallet);
            }
          },
          child: SingleChildScrollView(
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
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.h),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12.r),
                        onTap:
                            () => showResolveChallengeSheet(
                              context,
                              challenge: challengeData,
                              onMarkCompleted: widget.onMarkChallengeCompleted,
                            ),
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
    // The other person in it: the challenger when you are the witness, the
    // witness otherwise. (It used to be "You" for a witness, so the settle
    // sheet showed "You" twice.)
    final isCurrentUserWitness =
        currentUserWallet != null &&
        challenge.witnessAddress == currentUserWallet;
    final displayName =
        isCurrentUserWitness
            ? (challenge.member1Address ?? 'The challenger')
            : _getFriendDisplayName(challenge);

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

/// The empty escrow list: the brand scene and one line. Nothing here invites
/// starting one: creating an escrow challenge is retired. [message] is read
/// to screen readers.
Widget buildNoChallengesView({
  bool withText = false,
  String title = 'No escrow challenges',
  String message = 'This wallet has none from before calls.',
}) {
  return ChumbucketStateFill(
    child:
        withText
            ? ChumbucketStateView(
              artwork: ChumbucketStateArtwork.challenges,
              message: title,
              semanticsHint: message,
            )
            : const ChumbucketStateArt.compact(
              ChumbucketStateArtwork.challenges,
            ),
  );
}
