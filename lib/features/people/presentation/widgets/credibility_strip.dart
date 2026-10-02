/// A person's credibility at a glance: calls on record, correct over decided,
/// accuracy once it is earned, and when they joined.
///
/// Drawn on the neutral half of the joined profile surface, like the stats it
/// replaces. Every figure is the server's public record — withdrawn calls
/// included, followers-only and trades excluded — and the percentage cell
/// says what is still missing instead of printing a number too early.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';

class CredibilityStrip extends StatelessWidget {
  final PublicRecord record;
  final DateTime? joinedAtUtc;

  const CredibilityStrip({super.key, required this.record, this.joinedAtUtc});

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final percent = PeopleFormat.accuracy(record);
    final joined = PeopleFormat.joined(joinedAtUtc);
    final cells = <(String, String)>[
      ('${record.total}', 'calls on record'),
      ('${record.correct}/${record.decided}', 'correct / decided'),
      percent == null
          ? ('—', 'accuracy after ${record.minimumDecided} decided')
          : (percent, 'accuracy'),
      if (joined != null) (joined.replaceFirst('Joined ', ''), 'joined'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Two columns normally; one at large text so no value wraps
              // mid-figure.
              final stacked = MediaQuery.textScalerOf(context).scale(12) > 18;
              final width =
                  stacked
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final (value, label) in cells)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        container: true,
                        label: '$value $label',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: styles.headlineSmall?.copyWith(
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              label,
                              style: styles.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${record.incorrect} incorrect · ${record.voided} void, not scored · '
            '${record.pending} awaiting result.',
            style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
