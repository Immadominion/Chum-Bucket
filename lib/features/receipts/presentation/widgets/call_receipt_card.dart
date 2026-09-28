/// The receipt itself — the widget that gets captured and shared.
///
/// Content-agnostic by construction: it is handed a [CallReceipt] and nothing
/// else, so there is no path by which a stake, a payout or a PnL figure could
/// reach it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';

class CallReceiptCard extends StatelessWidget {
  final CallReceipt receipt;

  const CallReceiptCard({super.key, required this.receipt});

  Color get _accent => switch (receipt.outcome) {
    CallOutcome.correct => AppColors.success,
    CallOutcome.incorrect => AppColors.error,
    CallOutcome.voided => AppColors.textTertiary,
    CallOutcome.pending => AppColors.textSecondary,
  };

  String get _verdict => switch (receipt.outcome) {
    CallOutcome.correct => 'CALLED IT',
    CallOutcome.incorrect => 'GOT IT WRONG',
    CallOutcome.voided => 'VOID',
    CallOutcome.pending => 'PENDING',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320.w,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: _accent.withValues(alpha: 0.10),
            padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 14.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _verdict,
                  style: TextStyle(
                    color: _accent,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  CallsFormat.outcomeSentence(receipt.outcome),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.sp,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 18.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${receipt.personHandle} said',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: 6.h),
                // The exact side.
                Text(
                  receipt.sideLabel,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20.sp,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 12.h),
                // The source market, verbatim.
                Text(
                  receipt.marketQuestion,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.sp,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 16.h),
                Divider(height: 1, color: AppColors.divider),
                SizedBox(height: 12.h),

                // The original timestamp — the whole point of a receipt.
                _Row(
                  label: 'Locked',
                  value: CallsFormat.timestampUtc(receipt.lockedAt),
                ),
                // The entry probability.
                if (receipt.entryPrice == null)
                  _Row(
                    label: 'Entry probability',
                    value: CallsFormat.probability(receipt.entryProbability),
                  ),
                if (receipt.entryPrice case final price?) ...[
                  _Row(
                    label: 'YES at call',
                    value: CallsFormat.sharePrice(price.yesPrice),
                    wrap: true,
                  ),
                  _Row(
                    label: 'NO at call',
                    value: CallsFormat.sharePrice(price.noPrice),
                    wrap: true,
                  ),
                  _Row(
                    label: 'Price observed',
                    value: CallsFormat.timestampUtc(price.observedAtUtc),
                    wrap: true,
                  ),
                  _Row(
                    label: 'Price source',
                    value: SharePriceSnapshot.attribution,
                  ),
                  _Row(label: 'Price record', value: price.id, wrap: true),
                  const _Row(
                    label: 'Price type',
                    value: 'Indicative, not a trade quote',
                    wrap: true,
                  ),
                ],
                if (receipt.resolvedAt != null)
                  _Row(
                    label: 'Resolved',
                    value: CallsFormat.timestampUtc(receipt.resolvedAt!),
                  ),
                if (receipt.resolution != null)
                  _Row(
                    label: 'Venue outcome',
                    value:
                        receipt.resolution == Resolution.voided
                            ? 'VOID — cancelled'
                            : receipt.resolution!.wire,
                  ),
                _Row(label: 'Source', value: receipt.venueLabel),
                if (receipt.resolutionSource != null)
                  _Row(
                    label: 'Resolved by',
                    value: receipt.resolutionSource!,
                    wrap: true,
                  ),
                if (receipt.marketResolutionId != null)
                  _Row(
                    label: 'Evidence',
                    value: receipt.marketResolutionId!,
                    mono: true,
                  ),

                if (receipt.venueIsDemo) ...[
                  SizedBox(height: 10.h),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      'DEMO DATA — sample catalog, not a live market result.',
                      style: TextStyle(
                        color: AppColors.onTertiaryContainer,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],

                SizedBox(height: 14.h),
                Text(
                  'Free call. No stake, no position, no money.',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'chumbucket · ${receipt.callId}',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 9.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool wrap;

  const _Row({
    required this.label,
    required this.value,
    this.mono = false,
    this.wrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: wrap ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.sp,
                height: 1.35,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
