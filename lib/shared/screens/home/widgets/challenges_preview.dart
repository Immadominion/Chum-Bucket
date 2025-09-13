import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
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

  // Caching to prevent unnecessary reloads
  Future<List<dynamic>>? _challengesFuture;
  DateTime? _lastRefresh;

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

    // Initialize challenges future immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChallenges();
    });
  }

  void _initializeChallenges() {
    if (_challengesFuture == null || _shouldRefresh()) {
      _challengesFuture = null; // Clear cache
      _lastRefresh = DateTime.now();
      setState(() {}); // Trigger rebuild
    }
  }

  bool _shouldRefresh() {
    if (_lastRefresh == null) return true;
    final now = DateTime.now();
    return now.difference(_lastRefresh!).inSeconds >
        30; // Refresh after 30 seconds
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get providers without listening to avoid unnecessary rebuilds
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    final bool isSyncing =
        currentUser != null
            ? (EfficientSyncService.instance.getSyncStatus(
                  currentUser.id,
                  walletProvider.walletAddress,
                )['syncing']
                as bool)
            : false;

    // Use cached future or create new one
    _challengesFuture ??= _getPreviewChallenges(context, walletProvider);

    return FutureBuilder<List<dynamic>>(
      future: _challengesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || isSyncing) {
          return Column(
            children: [
              _buildShimmerChallenge(),
              SizedBox(height: 12.h),
              _buildShimmerChallenge(),
            ],
          );
        }

        final challenges = snapshot.data ?? [];

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
                            (challenge['status'] as String) == 'pending'
                                ? () => showResolveChallengeSheet(
                                  context,
                                  challenge: challenge as Map<String, dynamic>,
                                  onMarkCompleted:
                                      widget.onMarkChallengeCompleted,
                                )
                                : null,
                        child: _buildChallengePreviewCard(challenge),
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
          BoxShadow(color: Colors.grey.withOpacity(0.2), offset: Offset(0, 2)),
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

  Future<List<dynamic>> _getPreviewChallenges(
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

      // Sort: most recent first by createdAt
      challengesList.sort((a, b) {
        final da = a['createdAt'] as DateTime?;
        final db = b['createdAt'] as DateTime?;
        if (da == null && db == null) return 0;
        if (da == null) return 1; // nulls last
        if (db == null) return -1;
        return db.compareTo(da);
      });

      return challengesList;
    } catch (e) {
      return [];
    }
  }
}
