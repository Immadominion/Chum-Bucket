import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Individual settings menu item with consistent styling
class ProfileMenuItem extends StatelessWidget {
  /// Basil slug (preferred) or a Material fallback for the rare icon Basil
  /// doesn't cover — exactly one of the two must be set.
  final String? basilIcon;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final double? iconSize;
  final bool isDanger;

  const ProfileMenuItem({
    super.key,
    this.basilIcon,
    this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor,
    this.iconSize,
    this.isDanger = false,
  }) : assert(basilIcon != null || icon != null, 'provide basilIcon or icon');

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        isDanger ? Colors.red : iconColor ?? const Color(0xFFFF5A76);

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26.r),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.2), offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              children: [
                // Icon container
                Container(
                  padding: EdgeInsets.all(4.w),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(25.r),
                  ),
                  child:
                      basilIcon != null
                          ? BasilIcon(
                            basilIcon!,
                            size: iconSize ?? 26.w,
                            color: effectiveIconColor,
                          )
                          : Icon(
                            icon,
                            size: iconSize ?? 26.w,
                            color: effectiveIconColor,
                          ),
                ),

                SizedBox(width: 16.w),

                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: isDanger ? Colors.red : Colors.black87,
                        ),
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2.h),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Arrow
                BasilIcon(
                  'caret-right-outline',
                  size: 18.w,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
