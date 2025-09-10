import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_dimensions.dart';

/// Standard card container used throughout the app
class StandardCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? backgroundColor;
  final double? elevation;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const StandardCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.elevation,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: elevation ?? AppDimensions.cardElevation,
      color: backgroundColor ?? AppColors.surface,
      margin: margin ?? EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppDimensions.borderRadius),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(AppDimensions.paddingMedium),
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppDimensions.borderRadius),
        child: card,
      );
    }

    return card;
  }
}

/// Content section with optional header
class ContentSection extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsets? padding;
  final Widget? trailing;
  final VoidCallback? onTitleTap;

  const ContentSection({
    super.key,
    this.title,
    required this.child,
    this.padding,
    this.trailing,
    this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.all(AppDimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            GestureDetector(
              onTap: onTitleTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            SizedBox(height: AppDimensions.paddingSmall),
          ],
          child,
        ],
      ),
    );
  }
}

/// Modal bottom sheet container
class ModalContainer extends StatelessWidget {
  final Widget child;
  final String? title;
  final bool showHandle;
  final EdgeInsets? padding;
  final double? maxHeight;

  const ModalContainer({
    super.key,
    required this.child,
    this.title,
    this.showHandle = true,
    this.padding,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          maxHeight != null ? BoxConstraints(maxHeight: maxHeight!) : null,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.borderRadiusLarge),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHandle) ...[
            SizedBox(height: AppDimensions.paddingSmall),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: AppDimensions.paddingSmall),
          ],
          if (title != null) ...[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingLarge,
                vertical: AppDimensions.paddingMedium,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.outline),
          ],
          Flexible(
            child: Padding(
              padding: padding ?? EdgeInsets.all(AppDimensions.paddingLarge),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state container
class EmptyStateContainer extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyStateContainer({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppDimensions.paddingXLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64.sp, color: AppColors.onSurfaceVariant),
            SizedBox(height: AppDimensions.paddingLarge),
            Text(
              title,
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: AppDimensions.paddingSmall),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: AppDimensions.paddingLarge),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
