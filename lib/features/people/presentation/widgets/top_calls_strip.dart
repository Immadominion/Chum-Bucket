/// Home's "Top calls": named people's open calls that others are answering.
///
/// Each card leads with the person and their record, then the side they took
/// and the venue's exact question. The engagement line is direction-free
/// ("12 responses") until the viewer has their own call on that market; only
/// then does the server hand over the back/fade split, and only then is it
/// drawn. The strip renders nothing at all when there is nothing real to show.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';
import 'package:chumbucket/features/people/presentation/widgets/person_row.dart';

class TopCallsStrip extends StatelessWidget {
  final List<TopCall> calls;
  final void Function(TopCall call) onOpen;

  const TopCallsStrip({super.key, required this.calls, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (calls.isEmpty) return const SizedBox.shrink();
    final styles = AppTextStyles.textTheme;
    final width = math.min(280.0, MediaQuery.sizeOf(context).width * 0.78);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Top calls',
            style: AppTextStyles.questionTitle.copyWith(
              fontSize: 17,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Open calls, most answered first. Lock your own call to see which way people went.',
          style: styles.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        // Cards share the tallest card's height, so a large text size grows
        // the strip instead of clipping a question.
        SingleChildScrollView(
          key: const PageStorageKey('home-top-calls'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < calls.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  SizedBox(
                    width: width,
                    child: TopCallCard(
                      call: calls[i],
                      onTap: () => onOpen(calls[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TopCallCard extends StatelessWidget {
  final TopCall call;
  final VoidCallback onTap;

  const TopCallCard({super.key, required this.call, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final author = call.author;
    final engagement = [
      PeopleFormat.responses(call.responses),
      if (call.split case final split?)
        '${split.backs} back · ${split.fades} fade',
    ].join(' · ');
    final demo = call.market.venue.isDemo;
    final closes = CallsFormat.untilClose(call.market.closesAtUtc);
    return Semantics(
      button: true,
      label:
          '${demo ? 'Demo data. ' : ''}'
          '${author.displayName} called ${call.call.side.wire} on '
          '${call.market.question}. ${PeopleFormat.recordShort(author.record)}. '
          '$engagement. $closes.',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PersonAvatar(
                      initials: author.initials,
                      imageUrl: author.avatarUrl,
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            author.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.titleSmall,
                          ),
                          Text(
                            PeopleFormat.recordShort(author.record),
                            style: styles.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SidePill(side: call.call.side),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        closes,
                        style: styles.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // The full question is in the card's semantics label and on
                // the call it opens; here it is a preview.
                Text(
                  call.market.question,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.marketRowQuestion.copyWith(fontSize: 15),
                ),
                const Spacer(),
                const SizedBox(height: 12),
                if (demo)
                  Text(
                    'DEMO DATA · not a live market',
                    style: styles.bodySmall?.copyWith(
                      color: AppColors.onWarningContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  engagement,
                  style: styles.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
