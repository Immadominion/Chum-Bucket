import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/record/data/category_record.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// What the record counts, said once behind the info icon instead of under
/// every profile.
const recordScopeCopy =
    'Public free calls only, incorrect ones included. Void calls are not '
    'scored. Separate from trading.';

/// The public call record at a glance: correct, incorrect, pending and void,
/// each a number with an icon. Counts only visible public free calls, never
/// unscoped lifetime aggregates. A null list means unavailable, never a
/// fabricated zero.
class ProfileStatsCard extends StatelessWidget {
  final List<CallFeedEntry>? entries;
  const ProfileStatsCard({super.key, this.entries});

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final publicEntries = entries?.where(
      (entry) => entry.call.visibility == CallVisibility.public,
    );
    final record =
        publicEntries == null
            ? null
            : PersonRecord.fromEntries(publicEntries).overall;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      color: AppColors.outlineVariant,
      child:
          record == null
              ? Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Text(
                  'Public call record unavailable',
                  style: styles.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tap anywhere on the record for what it counts; screen
                  // readers hear it with the record.
                  Tooltip(
                    key: const ValueKey('record-scope'),
                    message: recordScopeCopy,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 6),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Four across; two by two at large text.
                          final columns =
                              MediaQuery.textScalerOf(context).scale(12) > 18
                                  ? 2
                                  : 4;
                          final width =
                              (constraints.maxWidth - 8 * (columns - 1)) /
                              columns;
                          final decided = record.decided;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Stat(
                                key: const ValueKey('record-correct'),
                                width: width,
                                icon: 'check-outline',
                                color: const Color(0xFF07644C),
                                value: '${record.tallies[0].count}',
                                label: 'Correct',
                                semantics:
                                    '${record.tallies[0].count} correct of '
                                    '$decided decided',
                              ),
                              _Stat(
                                key: const ValueKey('record-incorrect'),
                                width: width,
                                icon: 'cross-outline',
                                color: const Color(0xFF334155),
                                value: '${record.tallies[1].count}',
                                label: 'Incorrect',
                              ),
                              _Stat(
                                key: const ValueKey('record-pending'),
                                width: width,
                                icon: 'sand-watch-outline',
                                color: AppColors.onWarningContainer,
                                value: '${record.pending}',
                                label: 'Pending',
                              ),
                              _Stat(
                                key: const ValueKey('record-void'),
                                width: width,
                                icon: 'cancel-outline',
                                color: AppColors.textSecondary,
                                value: '${record.tallies[2].count}',
                                label: 'Void',
                                semantics:
                                    '${record.tallies[2].count} void, not '
                                    'scored',
                                info: true,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  if (publicEntries!.any((e) => e.market.venue.isDemo)) ...[
                    const SizedBox(height: 8),
                    Text(
                      'DEMO DATA · sample call record',
                      style: styles.bodySmall,
                    ),
                  ],
                ],
              ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.width,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.semantics,
    this.info = false,
  });

  /// Draws the small info glyph that says the record can be tapped.
  final bool info;

  final double width;
  final String icon;
  final Color color;
  final String value;
  final String label;
  final String? semantics;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Semantics(
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
    ),
  );
}
