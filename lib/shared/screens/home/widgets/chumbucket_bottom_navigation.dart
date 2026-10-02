import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Home holds people's calls; Markets holds discovery. The rollback shell
/// retains its original Calls destination through [showMarkets].
class ChumbucketBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showMarkets;

  const ChumbucketBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.showMarkets = true,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Home', 'home-outline', 'home-solid'),
      // Prototype icons, same Basil set. Group has no solid cut, so Friends
      // marks selection by colour and its pill alone.
      showMarkets
          ? ('Markets', 'chart-pie-alt-outline', 'chart-pie-alt-solid')
          : ('Calls', 'hotspot-outline', 'hotspot-solid'),
      ('Friends', 'group-151-outline', 'group-151-outline'),
      ('Profile', 'user-outline', 'user-solid'),
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: AppColors.textPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = selectedIndex == index;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.$1,
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(19),
                    child: ExcludeSemantics(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color:
                              selected
                                  ? AppColors.primaryContainer
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BasilIcon(
                              selected ? item.$3 : item.$2,
                              size: 22,
                              color:
                                  selected
                                      ? const Color(0xFFB8173B)
                                      : AppColors.textSecondary,
                            ),
                            const SizedBox(height: 5),
                            // Grow with the user's text setting, fitting only
                            // labels that exceed their quarter of the bar.
                            // Equal line boxes keep the four icons aligned;
                            // body text elsewhere is never scale-clamped.
                            SizedBox(
                              width: double.infinity,
                              height:
                                  MediaQuery.textScalerOf(context).scale(12) *
                                  1.2,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    item.$1,
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.2,
                                      fontWeight:
                                          selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                      color:
                                          selected
                                              ? AppColors.textPrimary
                                              : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
