import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
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
  Future<List<dynamic>>? _challengesFuture;
  int _lastRefreshKey = -1;

  @override
  void initState() {
    super.initState();
    _initializeChallenges();
  }

  @override
  void didUpdateWidget(ChallengesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refresh if the refresh key actually changed
    if (widget.refreshKey != _lastRefreshKey) {
      _challengesFuture = null; // Clear cache to force refresh
      _initializeChallenges();
    }
  }

  void _initializeChallenges() {
    _lastRefreshKey = widget.refreshKey;
    // Only create new future if we don't have one cached
    if (_challengesFuture == null) {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      _challengesFuture = _getAllChallenges(context, walletProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get providers without listening to avoid unnecessary rebuilds
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    final isSyncing =
        currentUser != null
            ? (EfficientSyncService.instance.getSyncStatus(
                  currentUser.id,
                  walletProvider.walletAddress,
                )['syncing']
                as bool)
            : false;

    return FutureBuilder<List<dynamic>>(
      future: _challengesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || isSyncing) {
          return const ShimmerChallenges();
        }

        if (snapshot.hasError) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Container(
              padding: EdgeInsets.all(32.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PhosphorIcon(
                    PhosphorIconsRegular.warning,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'Error loading challenges',
                    style: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  ),
                  SizedBox(height: 8.h),
                  TextButton(
                    onPressed: () {
                      // Trigger rebuild
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final challenges = snapshot.data ?? [];

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

        // Revamped list: clean stack of cards with spacing, not wrapped in a container
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
            child: Column(
              children: [
                ...List.generate(challenges.length, (index) {
                  final challenge = challenges[index];
                  final status =
                      (challenge['status'] as String?)?.toLowerCase() ??
                      'pending';
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12.r),
                      onTap:
                          status == 'pending'
                              ? () => showResolveChallengeSheet(
                                context,
                                challenge: challenge as Map<String, dynamic>,
                                onMarkCompleted:
                                    widget.onMarkChallengeCompleted,
                              )
                              : null,
                      child: ChallengeCard(
                        challenge: challenge,
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

  Future<List<dynamic>> _getAllChallenges(
    BuildContext context,
    WalletProvider walletProvider,
  ) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null || walletProvider.challengeService == null) {
        return [];
      }

      // Use efficient sync service - database-first approach
      final challenges = await EfficientSyncService.instance.getChallenges(
        userId: currentUser.id,
        walletAddress: walletProvider.walletAddress,
      );

      // Convert to UI format
      final challengesList = <Map<String, dynamic>>[];

      for (final challenge in challenges) {
        // Try to get participant's wallet address if they have participated
        String displayName = challenge.participantEmail ?? 'Unknown';
        if (challenge.participantId != null) {
          final participantWallet = await EfficientSyncService.instance
              .getParticipantWalletAddress(
                challenge.id,
                challenge.participantId!,
              );
          if (participantWallet != null && participantWallet.isNotEmpty) {
            displayName =
                participantWallet; // Use wallet address for resolution
          }
        }

        challengesList.add({
          'id': challenge.id,
          'title': challenge.title,
          'description': challenge.description,
          'amount': challenge.amount,
          'status': challenge.status.toString().split('.').last,
          'createdAt': challenge.createdAt,
          'expiresAt': challenge.expiresAt,
          'friendName': displayName,
          'source': 'database',
          'escrowAddress': challenge.escrowAddress,
        });
      }

      // Sort by creation date (most recent first)
      challengesList.sort((a, b) {
        final da = a['createdAt'] as DateTime?;
        final db = b['createdAt'] as DateTime?;
        if (da == null && db == null) return 0;
        if (da == null) return 1; // nulls last
        if (db == null) return -1;
        return db.compareTo(da); // Most recent first
      });

      return challengesList;
    } catch (e) {
      return [];
    }
  }
}
