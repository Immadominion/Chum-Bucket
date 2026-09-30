import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';

/// Content filters, distinct from bottom navigation. Parents can scroll the
/// strip horizontally at larger accessibility text sizes.
class ChumbucketTabs extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const ChumbucketTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(labels.length, (index) {
        final selected = index == selectedIndex;
        return Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            onTap: () => onSelected(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? AppColors.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
