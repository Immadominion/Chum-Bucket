import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/record/data/category_record.dart';

/// Counts only visible public free calls, never unscoped lifetime aggregates.
/// A null list means unavailable, never a fabricated zero.
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
    final correct = record?.tallies.first.count;
    final incorrect = record?.tallies[1].count;
    final voided = record?.tallies[2].count;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (record == null)
            Text(
              'Public call record unavailable',
              style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = MediaQuery.textScalerOf(context).scale(12) > 18;
                final width =
                    stacked
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    _stat(
                      styles,
                      width,
                      '$correct / ${record.decided}',
                      'correct / decided',
                    ),
                    _stat(
                      styles,
                      width,
                      '${record.pending}',
                      'awaiting result',
                    ),
                    _stat(styles, width, '$voided', 'void · not scored'),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              '$incorrect incorrect · ${record.decided} decided. Void excluded.',
              style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (publicEntries!.any((e) => e.market.venue.isDemo)) ...[
              const SizedBox(height: 8),
              Text('DEMO DATA · sample call record', style: styles.bodySmall),
            ],
          ],
        ],
      ),
    );
  }

  Widget _stat(TextTheme styles, double width, String value, String label) =>
      SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: styles.headlineSmall?.copyWith(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
}
