/// One row of the call feed.
///
/// What is deliberately absent: any stake amount, any copy-trade control, any
/// "N people are on this side" number, and any PnL. A call is a statement by a
/// person, so the card leads with the person, the claim and the timestamp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CallCard extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback? onOpenMarket;
  final VoidCallback? onOpenPerson;
  final VoidCallback? onRespond;
  final VoidCallback? onShareReceipt;

  /// Compact form for a person's page, where the author is already obvious.
  final bool showAuthor;

  const CallCard({
    super.key,
    required this.entry,
    this.onOpenMarket,
    this.onOpenPerson,
    this.onRespond,
    this.onShareReceipt,
    this.showAuthor = true,
  });

  @override
  Widget build(BuildContext context) {
    final call = entry.call;
    final market = entry.market;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenMarket,
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAuthor) ...[
                  _AuthorRow(entry: entry, onOpenPerson: onOpenPerson),
                  SizedBox(height: 12.h),
                ],
                Text(
                  market.question,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.sp,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SideChip(
                      side: call.side,
                      label: market.labelFor(call.side),
                    ),
                    // Entry probability — the price THIS person locked at.
                    // Never the current crowd number.
                    if (call.entryProbability != null)
                      CallBadge(
                        label:
                            'Locked at ${CallsFormat.probability(call.entryProbability)}',
                        color: AppColors.textSecondary,
                        icon: 'lock-outline',
                      ),
                    FundingStateBadge(state: call.fundingState),
                    if (entry.outcome.isSettled)
                      CallOutcomeBadge(outcome: entry.outcome),
                    DemoVenueBadge(venue: market.venue),
                    if (call.visibility == CallVisibility.followers)
                      CallBadge(
                        label: call.visibility.label,
                        color: AppColors.textTertiary,
                        icon: 'eye-outline',
                      ),
                  ],
                ),
                if (call.thesis != null && call.thesis!.isNotEmpty) ...[
                  SizedBox(height: 12.h),
                  Text(
                    call.thesis!,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.sp,
                      height: 1.45,
                    ),
                  ),
                ],
                if (call.confidence != null) ...[
                  SizedBox(height: 8.h),
                  Text(
                    CallsFormat.confidence(call.confidence),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (call.parentCallId != null) ...[
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      BasilIcon(
                        'exchange-outline',
                        size: 13.w,
                        color: AppColors.textTertiary,
                      ),
                      SizedBox(width: 5.w),
                      Flexible(
                        child: Text(
                          'Made in response to another call',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 14.h),
                _FooterRow(
                  entry: entry,
                  onRespond: onRespond,
                  onShareReceipt: onShareReceipt,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback? onOpenPerson;

  const _AuthorRow({required this.entry, this.onOpenPerson});

  @override
  Widget build(BuildContext context) {
    final author = entry.author;
    return Row(
      children: [
        AppAvatar(
          initials: author.initials,
          imageUrl: author.avatarUrl,
          size: 34,
          onTap: onOpenPerson,
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: GestureDetector(
            onTap: onOpenPerson,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 1.h),
                Text(
                  '@${author.handle} · ${CallsFormat.relative(entry.call.createdAtUtc)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Accuracy, not PnL. Null until something has actually settled.
        if (author.accuracy != null)
          CallBadge(
            label: '${CallsFormat.probability(author.accuracy)} accurate',
            color: AppColors.textSecondary,
            icon: 'award-outline',
          ),
      ],
    );
  }
}

class _FooterRow extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback? onRespond;
  final VoidCallback? onShareReceipt;

  const _FooterRow({
    required this.entry,
    this.onRespond,
    this.onShareReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final responses = entry.backCount + entry.fadeCount;
    return Row(
      children: [
        Expanded(
          child: Text(
            responses == 0
                ? 'No one has answered this yet'
                : '$responses ${responses == 1 ? 'person' : 'people'} answered',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12.sp),
          ),
        ),
        if (entry.isShareableReceipt && onShareReceipt != null)
          _FooterAction(
            icon: 'share-outline',
            label: 'Receipt',
            onTap: onShareReceipt!,
          ),
        if (onRespond != null) ...[
          SizedBox(width: 6.w),
          _FooterAction(
            icon: 'exchange-outline',
            label: 'Answer',
            emphasised: true,
            onTap: onRespond!,
          ),
        ],
      ],
    );
  }
}

class _FooterAction extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasised;

  const _FooterAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = emphasised ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BasilIcon(icon, size: 14.w, color: color),
              SizedBox(width: 5.w),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
