/// Renders a [PersonRecord].
///
/// The widget's only data source is [CategoryRecord.tallies], which always
/// contains correct, incorrect and void. That is the mechanical reason a record
/// on screen can never be a highlight reel: there is no getter here that could
/// hand back the hits without the misses.
///
/// Reused rather than rebuilt: `CallBadge` for the tally chips and
/// `CallsFormat.probability` for the percentage, so a record and a call card
/// spell a percentage the same way and a missing value renders as an em dash
/// rather than as 0%.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/record/data/category_record.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CategoryRecordCard extends StatelessWidget {
  final PersonRecord record;

  /// Whose record this is, for the accessibility summary.
  final String personName;

  const CategoryRecordCard({
    super.key,
    required this.record,
    required this.personName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BasilIcon(
                'award-outline',
                size: 16.w,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  'Track record',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Text(
            // Both halves of this line are load-bearing: the record is built
            // from free calls only, and a void market decided nothing.
            'Free calls only. Void is neither a win nor a loss.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11.sp),
          ),
          SizedBox(height: 14.h),
          _RecordBlock(record: record.overall, personName: personName),
          if (record.categories.length > 1) ...[
            SizedBox(height: 16.h),
            Divider(height: 1.h, color: AppColors.outlineVariant),
            SizedBox(height: 12.h),
            Text(
              'By category',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            SizedBox(height: 10.h),
            for (final category in record.categories) ...[
              _RecordBlock(
                record: category,
                personName: personName,
                compact: true,
              ),
              SizedBox(height: 12.h),
            ],
          ],
        ],
      ),
    );
  }
}

/// One record — overall or a single category.
class _RecordBlock extends StatelessWidget {
  final CategoryRecord record;
  final String personName;
  final bool compact;

  const _RecordBlock({
    required this.record,
    required this.personName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tallies = record.tallies;
    return Semantics(
      container: true,
      label: _semanticsLabel(record, personName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  record.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: compact ? 13.sp : 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                record.resolved == 1
                    ? '1 settled call'
                    : '${record.resolved} settled calls',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _Accuracy(record: record, compact: compact),
          SizedBox(height: 10.h),
          // Every tally, every time. Correct, incorrect, void.
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final tally in tallies) _TallyChip(tally: tally),
              if (record.pending > 0)
                CallBadge(
                  label: '${record.pending} pending',
                  color: AppColors.textSecondary,
                  icon: 'clock-outline',
                ),
            ],
          ),
          if (record.nonFreeCalls > 0) ...[
            SizedBox(height: 8.h),
            Text(
              _nonFreeLine(record),
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11.sp,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The percentage — or, below the threshold, the honest alternative to one.
class _Accuracy extends StatelessWidget {
  final CategoryRecord record;
  final bool compact;

  const _Accuracy({required this.record, required this.compact});

  @override
  Widget build(BuildContext context) {
    final accuracy = record.accuracy;

    if (accuracy == null) {
      final remaining = record.decidedCallsUntilAccuracy;
      return Text(
        record.decided == 0
            ? 'No decided calls yet — nothing to score.'
            : 'Too few calls to put a percentage on. '
                '$remaining more decided ${remaining == 1 ? 'call' : 'calls'} '
                'before we show one.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.sp,
          height: 1.35,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          CallsFormat.probability(accuracy),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: compact ? 20.sp : 26.sp,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(width: 6.w),
        Padding(
          padding: EdgeInsets.only(bottom: 2.h),
          child: Text(
            'of ${record.decided} decided calls',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TallyChip extends StatelessWidget {
  final RecordTally tally;

  const _TallyChip({required this.tally});

  @override
  Widget build(BuildContext context) {
    // Same tone mapping as `CallOutcomeBadge`, so a result means the same
    // colour wherever it appears.
    final (color, icon, noun) = switch (tally.outcome) {
      CallOutcome.correct => (AppColors.success, 'check-outline', 'correct'),
      CallOutcome.incorrect => (AppColors.error, 'cross-outline', 'incorrect'),
      CallOutcome.voided => (
        AppColors.textTertiary,
        'info-circle-outline',
        'void',
      ),
      CallOutcome.pending => (
        AppColors.textSecondary,
        'clock-outline',
        'pending',
      ),
    };
    return CallBadge(
      label: '${tally.count} $noun',
      color: color,
      icon: icon,
    );
  }
}

String _nonFreeLine(CategoryRecord record) {
  final funded = record.fundedCalls;
  final total = record.nonFreeCalls;
  // The word "Funded" comes from the frozen enum so it can only ever describe
  // FundingState.filled.
  final fundedWord = FundingState.filled.label.toLowerCase();
  final suffix =
      funded == 0
          ? ''
          : ' $funded of them reached $fundedWord.';
  return '$total call${total == 1 ? '' : 's'} here had a position attached and '
      'sit outside this record. Free-call accuracy is kept separate.$suffix';
}

String _semanticsLabel(CategoryRecord record, String personName) {
  final parts = record.tallies
      .map((t) => '${t.count} ${t.outcome.label.toLowerCase()}')
      .join(', ');
  final accuracy = record.accuracy;
  final headline =
      accuracy == null
          ? 'Not enough decided calls for a percentage'
          : '${CallsFormat.probability(accuracy)} of ${record.decided} decided calls correct';
  return '$personName, ${record.label}. $headline. $parts.';
}
