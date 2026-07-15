import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/arena_activity_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/dare_yourself_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';

/// Arena matchday list - open fixtures with live pot totals per bucket
/// (HOME/DRAW/AWAY), so a user can see the pool they'd be joining before
/// staking. This is separate from "Challenge a friend": it stakes into a
/// shared match-outcome pot, not a 1-v-1 friend escrow.
class MatchdayScreen extends StatefulWidget {
  const MatchdayScreen({super.key});

  @override
  State<MatchdayScreen> createState() => _MatchdayScreenState();
}

class _MatchdayScreenState extends State<MatchdayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final arena = Provider.of<ArenaProvider>(context, listen: false);
      arena.loadMatchday();
      _warmUpArenaService();
    });
  }

  /// Best-effort pre-warm so the first call screen tap doesn't have to
  /// wait for the Program/IDL to load. Failures here are silent - the Dare
  /// Yourself screen retries and surfaces any real error to the user.
  Future<void> _warmUpArenaService() async {
    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final arena = Provider.of<ArenaProvider>(context, listen: false);
      if (authProvider.isAuthenticated && authProvider.walletAddress != null) {
        await arena.ensureArenaService(
          authProvider: authProvider,
          walletAddress: authProvider.walletAddress,
          rpcUrl: NetworkConfig.rpcUrl,
        );
      }
    } catch (_) {
      // Silent - retried when the user actually tries to place a call.
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
          'Arena',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.dynamic_feed_outlined,
              color: Colors.black87,
            ),
            tooltip: 'Activity',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArenaActivityScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black87),
            tooltip: 'My Pots',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyPotsScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<ArenaProvider>(
        builder: (context, arena, _) {
          return RefreshIndicator(
            onRefresh: arena.loadMatchday,
            child: _buildBody(arena),
          );
        },
      ),
    );
  }

  Widget _buildBody(ArenaProvider arena) {
    if (arena.isLoadingMatchday && arena.matchday.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (arena.matchdayError != null && arena.matchday.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          Icon(Icons.cloud_off, size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'Could not load matchday.\n${arena.matchdayError}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    final open =
        arena.matchday.where((m) => m.isOpenForCalls).toList()
          ..sort((a, b) => a.fixture.kickoff.compareTo(b.fixture.kickoff));

    if (open.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          Icon(Icons.sports_soccer, size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'No open matches to call right now.\nCheck back soon.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.w),
      itemCount: open.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) => _MatchCard(match: open[index]),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final ArenaMatchEntry match;

  const _MatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final market = match.resultMarket;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DareYourselfScreen(match: match)),
        );
      },
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.fixture.competition,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  DateFormat(
                    'E, MMM d - h:mm a',
                  ).format(match.fixture.kickoff.toLocal()),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              match.fixture.title,
              style: TextStyle(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 12.h),
            if (market != null) _BucketTotalsRow(market: market),
          ],
        ),
      ),
    );
  }
}

class _BucketTotalsRow extends StatelessWidget {
  final ArenaMarket market;

  const _BucketTotalsRow({required this.market});

  @override
  Widget build(BuildContext context) {
    return Row(
      children:
          market.buckets
              .map(
                (bucket) => Expanded(
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 3.w),
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Column(
                      children: [
                        Text(
                          bucket.bucket,
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          ArenaFormat.usdcFromBaseUnits(bucket.stake),
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }
}
