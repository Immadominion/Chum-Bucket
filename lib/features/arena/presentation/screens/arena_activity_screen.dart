import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';

class ArenaActivityScreen extends StatefulWidget {
  const ArenaActivityScreen({super.key});

  @override
  State<ArenaActivityScreen> createState() => _ArenaActivityScreenState();
}

class _ArenaActivityScreenState extends State<ArenaActivityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() {
    return Provider.of<ArenaProvider>(context, listen: false).loadActivity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Activity',
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
    if (arena.isLoadingActivity && arena.activity.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (arena.activityError != null && arena.activity.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          Icon(Icons.cloud_off, size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'Could not load activity.\n${arena.activityError}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    if (arena.activity.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 80.h),
        children: [
          Icon(Icons.dynamic_feed_outlined, size: 48.sp, color: Colors.grey),
          SizedBox(height: 12.h),
          Text(
            'No calls have landed in the feed yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.sp),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(16.w),
      itemCount: arena.activity.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder:
          (context, index) => _ActivityCard(event: arena.activity[index]),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final ArenaActivityEvent event;

  const _ActivityCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final stake = event.stakeBaseUnits;
    final bucket = event.bucket ?? '?';

    return Container(
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
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(18.r),
                ),
                child: Icon(
                  Icons.sports_soccer,
                  size: 18.sp,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shortWallet(event.walletAddress),
                      style: TextStyle(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      DateFormat(
                        'MMM d, h:mm a',
                      ).format(event.createdAt.toLocal()),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(verified: event.isVerified),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            event.fixtureTitle,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6.h),
          Text(
            'Called $bucket${stake == null ? '' : ' • ${ArenaFormat.usdcFromBaseUnits(stake)}'}',
            style: TextStyle(fontSize: 12.5.sp, color: Colors.grey.shade700),
          ),
          if (event.txSignature != null && event.txSignature!.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              _shortSignature(event.txSignature!),
              style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  String _shortWallet(String wallet) {
    if (wallet.length <= 10) return wallet;
    return '${wallet.substring(0, 4)}...${wallet.substring(wallet.length - 4)}';
  }

  String _shortSignature(String signature) {
    if (signature.length <= 16) return signature;
    return 'tx ${signature.substring(0, 6)}...${signature.substring(signature.length - 6)}';
  }
}

class _StatusPill extends StatelessWidget {
  final bool verified;

  const _StatusPill({required this.verified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
      decoration: BoxDecoration(
        color:
            verified ? AppColors.successContainer : AppColors.warningContainer,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        verified ? 'Verified' : 'Pending',
        style: TextStyle(
          fontSize: 10.5.sp,
          fontWeight: FontWeight.w700,
          color:
              verified
                  ? AppColors.onSuccessContainer
                  : AppColors.onWarningContainer,
        ),
      ),
    );
  }
}
