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

  /// Codex's layout prototype: the strip starts flush with the content, the
  /// labels sit ~20dp apart and the 3dp underline spans only the word. Each
  /// tab's touch target still reaches 48dp across and down.
  static const double _gap = 20;

  static const TextStyle _labelStyle = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 14,
    height: 1.3,
  );

  /// How wide the strip lays out at [context]'s text scale, measured at the
  /// selected (heaviest) weight so a selection never makes it grow. Lets a
  /// parent decide whether an action still fits beside every label, instead
  /// of letting the action sit over the last one.
  static double naturalWidth(BuildContext context, List<String> labels) {
    final scaler = MediaQuery.textScalerOf(context);
    var width = _gap * (labels.length - 1);
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: _labelStyle.copyWith(fontWeight: FontWeight.w800),
        ),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width += (painter.width + 2).clamp(48, double.infinity);
      painter.dispose();
    }
    return width;
  }

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : _gap / 2,
                  right: index == labels.length - 1 ? 0 : _gap / 2,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.fromLTRB(1, 14, 1, 11),
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
                    style: _labelStyle.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                      color:
                          selected
                              ? AppColors.textPrimary
                              : const Color(0xFF606775),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
