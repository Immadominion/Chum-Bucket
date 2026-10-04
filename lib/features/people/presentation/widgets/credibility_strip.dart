/// A person's credibility at a glance: accuracy once it is earned, then the
/// same four numbers your own Profile shows (correct, incorrect, pending,
/// void).
///
/// Drawn on the neutral half of the joined profile surface, like the stats it
/// replaces. Every figure is the server's public record — withdrawn calls
/// included, followers-only and trades excluded. What it counts is not printed
/// under it: tap the record (or the info glyph) to read it; screen readers
/// hear it with the record.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';
import 'package:chumbucket/features/record/presentation/widgets/record_stat_tiles.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// What a person's public record counts, said once behind the record.
const publicRecordScopeCopy =
    'Public free calls, misses and withdrawn calls included. Void is never '
    'scored. Followers-only calls and trades are not counted.';

class CredibilityStrip extends StatelessWidget {
  final PublicRecord record;
  final DateTime? joinedAtUtc;

  const CredibilityStrip({super.key, required this.record, this.joinedAtUtc});

  @override
  Widget build(BuildContext context) {
    final percent = PeopleFormat.accuracy(record);
    final joined = PeopleFormat.joined(joinedAtUtc);
    const muted = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      color: AppColors.outlineVariant,
      child: Tooltip(
        key: const ValueKey('person-record-scope'),
        message: publicRecordScopeCopy,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      container: true,
                      label:
                          percent == null
                              ? 'No accuracy yet: it shows after '
                                  '${record.minimumDecided} decided calls'
                              : '$percent accuracy',
                      excludeSemantics: true,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            percent ?? '—',
                            style: const TextStyle(
                              fontFamily: 'PPNeueMachina',
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            percent == null
                                ? 'accuracy after ${record.minimumDecided} decided'
                                : 'accuracy',
                            style: muted,
                          ),
                          if (joined != null) Text('· $joined', style: muted),
                        ],
                      ),
                    ),
                  ),
                  const BasilIcon(
                    'info-circle-outline',
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
            RecordStatRow(
              tiles: [
                RecordStatTile(
                  icon: 'check-outline',
                  color: RecordInk.correct,
                  value: '${record.correct}',
                  label: 'Correct',
                  semantics:
                      '${record.correct} correct of ${record.decided} decided',
                ),
                RecordStatTile(
                  icon: 'cross-outline',
                  color: RecordInk.incorrect,
                  value: '${record.incorrect}',
                  label: 'Incorrect',
                ),
                RecordStatTile(
                  icon: 'sand-watch-outline',
                  color: RecordInk.pending,
                  value: '${record.pending}',
                  label: 'Pending',
                ),
                RecordStatTile(
                  icon: 'cancel-outline',
                  color: RecordInk.voided,
                  value: '${record.voided}',
                  label: 'Void',
                  semantics: '${record.voided} void, not scored',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
