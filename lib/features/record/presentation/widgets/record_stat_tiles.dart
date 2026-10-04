/// The compact call record: a few numbers, each with an icon and one word.
///
/// Shared by your own Profile (`ProfileStatsCard`) and other people's
/// (`CredibilityStrip`) so a record reads the same everywhere. What a record
/// counts is never printed under it; it sits behind a tap on the record (a
/// `Tooltip` with `TooltipTriggerMode.tap`), which screen readers also hear.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Colours for the record's glyphs: YES green for correct, NO slate for
/// incorrect, the warning ink for pending, and muted for void.
abstract final class RecordInk {
  static const Color correct = Color(0xFF07644C);
  static const Color incorrect = Color(0xFF334155);
  static const Color pending = AppColors.onWarningContainer;
  static const Color voided = AppColors.textSecondary;
}

/// One number: an icon, the figure, one word under it.
class RecordStatTile extends StatelessWidget {
  const RecordStatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.semantics,
    this.info = false,
  });

  final String icon;
  final Color color;
  final String value;
  final String label;

  /// Read instead of "[value] [label]" when the figure needs context.
  final String? semantics;

  /// Draws the small info glyph that says the record can be tapped.
  final bool info;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics ?? '$value $label',
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BasilIcon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                // A wide figure ("100%") scales down rather than clipping.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: 'PPNeueMachina',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (info)
                const BasilIcon(
                  'info-circle-outline',
                  size: 13,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
          const SizedBox(height: 2),
          // Scaled down, never cut off, when large text meets a narrow tile.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Lays [tiles] out four across, two by two at large text.
class RecordStatRow extends StatelessWidget {
  const RecordStatRow({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = MediaQuery.textScalerOf(context).scale(12) > 18 ? 2 : 4;
      final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tile in tiles) SizedBox(width: width, child: tile),
        ],
      );
    },
  );
}
