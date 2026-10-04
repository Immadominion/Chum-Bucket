/// Badges whose whole job is that free / funded / pending / resolved / void
/// can never be confused for one another.
///
/// Free and funded each have exactly one mark: [FreeMarker] (outline, a gift,
/// "Free") and [FundedMarker] (solid pink, the dollars). The word "Funded"
/// comes only from [FundingState.filled].
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

  /// Icon and words in [color] with no box, for a badge that sits inside a
  /// line of metadata (the call card's price stamp). Same copy, same colour.
  final bool quiet;

  const CallBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.emphasised = false,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    if (quiet) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            BasilIcon(icon!, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: emphasised ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
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
                fontSize: 12,
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

/// The one mark a free call carries everywhere it shows: cards, call
/// screens, sheets and receipts. Outline, never filled (solid pink is money),
/// a gift and one word.
class FreeMarker extends StatelessWidget {
  const FreeMarker({super.key, this.large = false});

  /// A touch bigger, for a receipt's stamp or a sheet's action.
  final bool large;

  static const ink = AppColors.textMuted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: FundingState.none.label,
    excludeSemantics: true,
    child: Container(
      key: const ValueKey('free-marker'),
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 7,
        vertical: large ? 4 : 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BasilIcon('present-outline', size: large ? 15 : 13, color: ink),
          SizedBox(width: large ? 5 : 4),
          Text(
            'Free',
            maxLines: 1,
            style: TextStyle(
              color: ink,
              fontSize: large ? 13 : 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Money behind a call: solid pink with its dollars ("$5"), or "Funded"
/// where the amount isn't known. Only ever for a confirmed fill. Ink on
/// coral, as on the web: white on coral is under 4.5:1 at this size.
class FundedMarker extends StatelessWidget {
  const FundedMarker({super.key, this.amount, this.large = false});

  /// Dollars, already formatted ("$5"); null reads "Funded".
  final String? amount;
  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
    label: amount == null ? FundingState.filled.label : 'Funded, $amount',
    excludeSemantics: true,
    child: Container(
      key: const ValueKey('funded-marker'),
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 7,
        vertical: large ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BasilIcon(
            'wallet-solid',
            size: large ? 15 : 13,
            color: AppColors.textPrimary,
          ),
          SizedBox(width: large ? 5 : 4),
          Text(
            amount ?? FundingState.filled.label,
            maxLines: 1,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: large ? 13 : 12,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Free vs funded. `NONE` is the [FreeMarker]; only [FundingState.filled]
/// is the [FundedMarker], and its word lives on the enum. Every state in
/// between keeps its own plain badge: neither free nor money yet.
class FundingStateBadge extends StatelessWidget {
  final FundingState state;
  final bool quiet;

  const FundingStateBadge({super.key, required this.state, this.quiet = false});

  @override
  Widget build(BuildContext context) {
    if (state == FundingState.none) return const FreeMarker();
    if (state == FundingState.filled) return const FundedMarker();
    final (color, icon) = switch (state) {
      FundingState.none => (AppColors.textSecondary, 'present-outline'),
      FundingState.quoted => (AppColors.textSecondary, 'info-circle-outline'),
      FundingState.submitted => (AppColors.onWarningContainer, 'clock-outline'),
      FundingState.filled => (AppColors.onSuccessContainer, 'check-outline'),
      FundingState.partial => (
        AppColors.onWarningContainer,
        'info-circle-outline',
      ),
      FundingState.failed => (const Color(0xFFB42318), 'cross-outline'),
      FundingState.closed => (AppColors.textSecondary, 'check-outline'),
      FundingState.claimable => (AppColors.tertiary, 'award-outline'),
      FundingState.claimed => (AppColors.textSecondary, 'check-outline'),
    };
    return CallBadge(
      label: state.label,
      color: color,
      icon: icon,
      quiet: quiet,
    );
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
      CallOutcome.correct => (
        AppColors.onSuccessContainer,
        'check-outline',
        'Correct',
      ),
      CallOutcome.incorrect => (
        const Color(0xFFB42318),
        'cross-outline',
        'Incorrect',
      ),
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
      MarketStatus.open => (AppColors.onSuccessContainer, 'unlock-outline'),
      MarketStatus.closedPendingResolution => (
        AppColors.onWarningContainer,
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
      color: AppColors.onWarningContainer,
      icon: 'info-triangle-outline',
      emphasised: true,
    );
  }
}

/// The two sides' colours, everywhere a side is shown: YES green on mint,
/// NO slate on grey (both well over 4.5:1).
abstract final class CallSideColors {
  static const yesInk = Color(0xFF07644C);
  static const yesFill = Color(0xFFE6F6EF);
  static const noInk = Color(0xFF334155);
  static const noFill = Color(0xFFEEF0F4);

  static Color ink(Side side) => side == Side.yes ? yesInk : noInk;
  static Color fill(Side side) => side == Side.yes ? yesFill : noFill;
}

/// The side a call took, as a flat label (the prototype's stance pill).
/// Display only; [SideChip] is the selectable control.
class SidePill extends StatelessWidget {
  final Side side;
  final String? label;

  const SidePill({super.key, required this.side, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: CallSideColors.fill(side),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label ?? side.wire,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'PPNeueMachina',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.2,
          color: CallSideColors.ink(side),
        ),
      ),
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
    final color =
        side == Side.yes ? AppColors.onSuccessContainer : AppColors.textPrimary;
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
