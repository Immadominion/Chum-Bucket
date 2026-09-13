/// The one affordance that opens a rematch.
///
/// One widget so every entry point — the person page today, the receipt sheet
/// once `docs/contracts/integration-requests/packet-g.md` lands — spells the
/// action, the tone and the "nothing at stake" promise identically. It renders
/// nothing at all when a rematch is not on offer, so a settled-only action can
/// never appear on a pending call.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/rematch/data/rematch_offer.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class RematchButton extends StatelessWidget {
  final RematchOffer offer;
  final VoidCallback onPressed;

  /// Full-width, for a sheet's action row. Compact is for a list.
  final bool expanded;

  const RematchButton({
    super.key,
    required this.offer,
    required this.onPressed,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    // A rematch answers a result. No result, no button — and no explaining
    // away a disabled control.
    if (!offer.isAvailable) return const SizedBox.shrink();

    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BasilIcon('exchange-outline', size: 15.w, color: AppColors.primary),
          SizedBox(width: 6.w),
          Flexible(
            child: Text(
              'Rematch @${offer.opponentHandle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: 'Rematch ${offer.opponentDisplayName}. Free, nothing at stake.',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999.r),
        child: content,
      ),
    );
  }
}
