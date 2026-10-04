import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/record/data/category_record.dart';
import 'package:chumbucket/features/record/presentation/widgets/record_stat_tiles.dart';

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
    // Not read yet (or not readable): the same four tiles with a quiet "—",
    // so nothing jumps when it lands and no internal state is narrated.
    String count(int? n) => n == null ? '\u2014' : '$n';
    final correct = record?.tallies[0].count;
    final voided = record?.tallies[2].count;
    final tiles = RecordStatRow(
      tiles: [
        RecordStatTile(
          key: const ValueKey('record-correct'),
          icon: 'check-outline',
          color: RecordInk.correct,
          value: count(correct),
          label: 'Correct',
          semantics:
              record == null
                  ? null
                  : '$correct correct of ${record.decided} decided',
        ),
        RecordStatTile(
          key: const ValueKey('record-incorrect'),
          icon: 'cross-outline',
          color: RecordInk.incorrect,
          value: count(record?.tallies[1].count),
          label: 'Incorrect',
        ),
        RecordStatTile(
          key: const ValueKey('record-pending'),
          icon: 'sand-watch-outline',
          color: RecordInk.pending,
          value: count(record?.pending),
          label: 'Pending',
        ),
        RecordStatTile(
          key: const ValueKey('record-void'),
          icon: 'cancel-outline',
          color: RecordInk.voided,
          value: count(voided),
          label: 'Void',
          semantics: record == null ? null : '$voided void, not scored',
          info: record != null,
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      color: AppColors.outlineVariant,
      child:
          record == null
              ? Semantics(
                container: true,
                label: 'Call record not loaded',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: tiles,
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
                      child: tiles,
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
