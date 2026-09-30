import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// The same market entry on Home and in discovery. Prices and exact rules are
/// fetched on detail; a catalog row cannot invent a quote or a crowd split.
class CallMarketCard extends StatelessWidget {
  const CallMarketCard({super.key, required this.market, required this.onTap});

  final VenueMarket market;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20.r),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.r),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  market.venue.label,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                MarketStatusBadge(status: market.status),
                DemoVenueBadge(venue: market.venue),
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              market.question,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17.sp,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                BasilIcon(
                  'clock-outline',
                  size: 16.w,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    CallsFormat.untilClose(market.closesAtUtc),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
                const BasilIcon(
                  'caret-right-outline',
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
