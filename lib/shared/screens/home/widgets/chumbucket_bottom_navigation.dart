import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:chumbucket/core/theme/app_colors.dart';

class ChumbucketBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const ChumbucketBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const _items = <_NavigationItem>[
    _NavigationItem(
      label: 'Home',
      regular: PhosphorIconsRegular.house,
      selected: PhosphorIconsFill.house,
    ),
    _NavigationItem(
      label: 'Calls',
      regular: PhosphorIconsRegular.broadcast,
      selected: PhosphorIconsFill.broadcast,
    ),
    _NavigationItem(
      label: 'Friends',
      regular: PhosphorIconsRegular.usersThree,
      selected: PhosphorIconsFill.usersThree,
    ),
    _NavigationItem(
      label: 'Profile',
      regular: PhosphorIconsRegular.userCircle,
      selected: PhosphorIconsFill.userCircle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(12.w, 0, 12.w, 14.h),
      child: Container(
        height: 64.h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (index) {
            final item = _items[index];
            final isSelected = selectedIndex == index;
            return Expanded(
              child: Semantics(
                button: true,
                selected: isSelected,
                label: item.label,
                child: InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(24.r),
                  child: SizedBox.expand(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: 48.w,
                          height: 42.h,
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? AppColors.primaryContainer
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                          child: Center(
                            child: PhosphorIcon(
                              isSelected ? item.selected : item.regular,
                              size: 25.w,
                              color:
                                  isSelected
                                      ? AppColors.primary
                                      : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavigationItem {
  final String label;
  final IconData regular;
  final IconData selected;

  const _NavigationItem({
    required this.label,
    required this.regular,
    required this.selected,
  });
}
