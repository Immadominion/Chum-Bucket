import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class MenuTile extends StatelessWidget {
  /// Basil slug (preferred) or a Material/Cupertino fallback for the rare
  /// icon Basil doesn't cover — exactly one of the two must be set.
  final String? basilIcon;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool isDanger;

  const MenuTile({
    Key? key,
    this.basilIcon,
    this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor,
    this.isDanger = false,
  }) : assert(basilIcon != null || icon != null, 'provide basilIcon or icon'),
       super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
        leading: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: (iconColor ?? Theme.of(context).colorScheme.primary)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child:
              basilIcon != null
                  ? BasilIcon(
                    basilIcon!,
                    size: 20.sp,
                    color:
                        isDanger
                            ? Colors.red
                            : (iconColor ??
                                Theme.of(context).colorScheme.primary),
                  )
                  : Icon(
                    icon,
                    size: 20.sp,
                    color:
                        isDanger
                            ? Colors.red
                            : (iconColor ??
                                Theme.of(context).colorScheme.primary),
                  ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color:
                isDanger ? Colors.red : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle:
            subtitle != null
                ? Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                  ),
                )
                : null,
        trailing: BasilIcon(
          'caret-right-outline',
          size: 16.sp,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
        ),
        onTap: onTap,
      ),
    );
  }
}
