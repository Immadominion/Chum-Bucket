/// Badges whose whole job is that free / funded / pending / resolved / void
/// can never be confused for one another.
///
/// Each badge takes its copy from the FROZEN enum's own `label`, so there is
/// exactly one place the word "Funded" can come from — [FundingState.filled].
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CallBadge extends StatelessWidget {
  final String label;
  final Color color;
  final String? icon;
  final bool emphasised;

  const CallBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: emphasised ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            BasilIcon(
              icon!,
              size: 12.w,
              color: emphasised ? Colors.white : color,
            ),
            SizedBox(width: 4.w),
          ],
          // Flexible so a long venue label or status wraps to an ellipsis
          // instead of overflowing a narrow phone.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasised ? Colors.white : color,
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Free vs funded. `NONE` reads "Free call"; only [FundingState.filled] may
/// read "Funded", and that copy lives on the enum.
class FundingStateBadge extends StatelessWidget {
  final FundingState state;

  const FundingStateBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state) {
      FundingState.none => (AppColors.textSecondary, 'comment-outline'),
      FundingState.quoted => (AppColors.textSecondary, 'info-circle-outline'),
      FundingState.submitted => (AppColors.warning, 'clock-outline'),
      FundingState.filled => (AppColors.success, 'check-outline'),
      FundingState.partial => (AppColors.warning, 'info-circle-outline'),
      FundingState.failed => (AppColors.error, 'cross-outline'),
      FundingState.closed => (AppColors.textSecondary, 'check-outline'),
      FundingState.claimable => (AppColors.tertiary, 'award-outline'),
      FundingState.claimed => (AppColors.textSecondary, 'check-outline'),
    };
    return CallBadge(label: state.label, color: color, icon: icon);
  }
}

/// Pending / Correct / Incorrect / Void. Void is styled as neither win nor
/// loss and says so.
class CallOutcomeBadge extends StatelessWidget {
  final CallOutcome outcome;

  const CallOutcomeBadge({super.key, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (outcome) {
      CallOutcome.pending => (
        AppColors.textSecondary,
        'clock-outline',
        'Pending',
      ),
      CallOutcome.correct => (AppColors.success, 'check-outline', 'Correct'),
      CallOutcome.incorrect => (AppColors.error, 'cross-outline', 'Incorrect'),
      CallOutcome.voided => (
        AppColors.textTertiary,
        'info-circle-outline',
        'Void — no result',
      ),
    };
    return CallBadge(label: label, color: color, icon: icon);
  }
}

/// OPEN / CLOSED_PENDING_RESOLUTION / RESOLVED / CANCELLED / PAUSED, never
/// collapsed into one another.
class MarketStatusBadge extends StatelessWidget {
  final MarketStatus status;

  const MarketStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      MarketStatus.open => (AppColors.success, 'unlock-outline'),
      MarketStatus.closedPendingResolution => (
        AppColors.warning,
        'lock-time-outline',
      ),
      MarketStatus.resolved => (AppColors.textPrimary, 'check-outline'),
      MarketStatus.cancelled => (AppColors.textTertiary, 'cross-outline'),
      MarketStatus.paused => (AppColors.tertiary, 'pause-outline'),
    };
    return CallBadge(label: status.label, color: color, icon: icon);
  }
}

/// `fixture` venue data must be visibly labelled as demo and can never present
/// as a live result (contract §4).
class DemoVenueBadge extends StatelessWidget {
  final MarketVenue venue;

  const DemoVenueBadge({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    if (!venue.isDemo) return const SizedBox.shrink();
    return const CallBadge(
      label: 'DEMO DATA',
      color: AppColors.tertiary,
      icon: 'info-triangle-outline',
      emphasised: true,
    );
  }
}

/// YES / NO pill for a side the person actually took.
class SideChip extends StatelessWidget {
  final Side side;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;

  const SideChip({
    super.key,
    required this.side,
    this.label,
    this.selected = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = side == Side.yes ? AppColors.success : AppColors.error;
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: selected ? color : AppColors.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(
              color: selected ? color : AppColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6.w),
          Flexible(
            child: Text(
              label ?? side.wire,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? color : AppColors.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: content,
      ),
    );
  }
}
