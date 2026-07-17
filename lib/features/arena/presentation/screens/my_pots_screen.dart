import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// "My Pots" - every Arena match the player has staked into, its status,
/// and a Claim action once the match has settled. Distinct from the
/// friend-challenge history - this only ever reflects chumbucket_arena
/// Positions/Pots.
class MyPotsScreen extends StatefulWidget {
  const MyPotsScreen({super.key});

  @override
  State<MyPotsScreen> createState() => _MyPotsScreenState();
}

class _MyPotsScreenState extends State<MyPotsScreen> {
  final Set<String> _claiming = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final arena = Provider.of<ArenaProvider>(context, listen: false);
    final address = authProvider.walletAddress;
    if (address == null) return;

    if (arena.matchday.isEmpty) {
      await arena.loadMatchday();
    }
    await arena.loadMyPots(walletAddress: address);
  }

  /// Best-effort status lookup from the cached matchday list. A record
  /// whose match has aged out of that list (no longer OPEN/LOCKED) is
  /// treated as claim-eligible - the on-chain `claim()` call is the actual
  /// source of truth and will reject with a clear error if it isn't.
  ArenaMatchEntry? _cachedMatch(ArenaProvider arena, String matchId) {
    for (final m in arena.matchday) {
      if (m.fixture.matchId == matchId) return m;
    }
    return null;
  }

  Future<void> _claim(MyPotRecord record) async {
    final arena = Provider.of<ArenaProvider>(context, listen: false);
    setState(() => _claiming.add(record.matchId));
    try {
      await arena.claim(record);
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: 'Claimed',
        subtitle: '${record.home} vs ${record.away} payout claimed.',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not claim',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _claiming.remove(record.matchId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'My Pots',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
      body: Consumer<ArenaProvider>(
        builder: (context, arena, _) {
          return RefreshIndicator(onRefresh: _load, child: _buildBody(arena));
        },
      ),
    );
  }

  Widget _buildBody(ArenaProvider arena) {
    if (arena.isLoadingMyPots && arena.myPots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (arena.myPots.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          BasilIcon('award-outline', size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'You haven\'t dared yourself on any matches yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.w),
      itemCount: arena.myPots.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final record = arena.myPots[index];
        final cached = _cachedMatch(arena, record.matchId);
        final isMatchStillActive =
            cached != null &&
            (cached.status == 'OPEN' || cached.status == 'LOCKED');
        final isClaiming = _claiming.contains(record.matchId);

        return _PotCard(
          record: record,
          isMatchStillActive: isMatchStillActive,
          isClaiming: isClaiming,
          onClaim: () => _claim(record),
        );
      },
    );
  }
}

class _PotCard extends StatelessWidget {
  final MyPotRecord record;
  final bool isMatchStillActive;
  final bool isClaiming;
  final VoidCallback onClaim;

  const _PotCard({
    required this.record,
    required this.isMatchStillActive,
    required this.isClaiming,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${record.home} vs ${record.away}',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusChip(
                claimed: record.claimedLocally,
                active: isMatchStillActive,
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            'Called ${ArenaFormat.bucketLabel(record.bucket)} • '
            '${ArenaFormat.usdc(record.amountUsdc)}',
            style: TextStyle(fontSize: 12.5.sp, color: Colors.grey.shade700),
          ),
          SizedBox(height: 2.h),
          Text(
            DateFormat('MMM d, h:mm a').format(record.placedAt.toLocal()),
            style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade500),
          ),
          if (!record.claimedLocally) ...[
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: (isMatchStillActive || isClaiming) ? null : onClaim,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                child:
                    isClaiming
                        ? SizedBox(
                          height: 16.h,
                          width: 16.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                        : Text(
                          isMatchStillActive ? 'Match in progress' : 'Claim',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool claimed;
  final bool active;

  const _StatusChip({required this.claimed, required this.active});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (claimed) {
      label = 'Claimed';
      color = AppColors.success;
    } else if (active) {
      label = 'Live';
      color = AppColors.tertiary;
    } else {
      label = 'Settled';
      color = AppColors.primary;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
