import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_dimensions.dart';

/// Standard app header with consistent styling
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Color? backgroundColor;
  final bool centerTitle;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.showBackButton = false,
    this.onBackPressed,
    this.backgroundColor,
    this.centerTitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: backgroundColor ?? AppColors.surface,
      padding: EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: AppDimensions.paddingSmall,
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Leading/Back button
            if (showBackButton || leading != null) ...[
              leading ??
                  IconButton(
                    onPressed:
                        onBackPressed ?? () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back_ios,
                      color: AppColors.onSurface,
                      size: 20.sp,
                    ),
                  ),
              SizedBox(width: AppDimensions.paddingSmall),
            ],

            // Title section
            Expanded(
              child: Column(
                crossAxisAlignment:
                    centerTitle
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Actions
            if (actions != null) ...[
              SizedBox(width: AppDimensions.paddingSmall),
              ...actions!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Section header with optional action
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onActionTap;
  final EdgeInsets? padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onActionTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: AppDimensions.paddingSmall,
          ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null || onActionTap != null) ...[
            SizedBox(width: AppDimensions.paddingMedium),
            action ??
                IconButton(
                  onPressed: onActionTap,
                  icon: Icon(
                    Icons.more_vert,
                    color: AppColors.onSurfaceVariant,
                    size: 20.sp,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

/// Tab header with underline indicator
class TabHeader extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;
  final Color? selectedColor;
  final Color? unselectedColor;

  const TabHeader({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabChanged,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabChanged(index),
              child: Container(
                padding: EdgeInsets.symmetric(
                  vertical: AppDimensions.paddingMedium,
                ),
                decoration: BoxDecoration(
                  border:
                      isSelected
                          ? Border(
                            bottom: BorderSide(
                              color: selectedColor ?? AppColors.primary,
                              width: 2,
                            ),
                          )
                          : null,
                ),
                child: Text(
                  tabs[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color:
                        isSelected
                            ? (selectedColor ?? AppColors.primary)
                            : (unselectedColor ?? AppColors.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
