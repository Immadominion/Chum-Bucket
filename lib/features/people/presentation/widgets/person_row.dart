/// One person in a list: avatar, name, handle and their public record.
///
/// Shared by the leaderboard, people search and the Following list so a
/// person reads the same wherever they appear. The record line is
/// [PeopleFormat.recordShort], so it never shows a percentage the server did
/// not hand over.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class PersonRow extends StatelessWidget {
  final PersonCard person;
  final VoidCallback onTap;

  /// A rank badge before the avatar (leaderboard), or nothing.
  final int? rank;

  /// Replaces the record line, e.g. "6 more decided calls to rank".
  final String? detail;

  /// Highlights the viewer's own row.
  final bool highlighted;

  /// Show "Following" beside the name when the viewer follows them.
  final bool showFollowing;

  const PersonRow({
    super.key,
    required this.person,
    required this.onTap,
    this.rank,
    this.detail,
    this.highlighted = false,
    this.showFollowing = false,
  });

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final percent = PeopleFormat.accuracy(person.record);
    // Above ~1.5x text the stats move under the name rather than squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;
    final stats =
        percent == null
            ? null
            : Column(
              crossAxisAlignment:
                  stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Text(
                  percent,
                  style: AppTextStyles.questionTitle.copyWith(
                    fontSize: 18,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  '${person.record.correct}/${person.record.decided}',
                  style: styles.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            );
    final recordLine = detail ?? PeopleFormat.recordShort(person.record);
    return Semantics(
      button: true,
      label: [
        if (rank != null) 'Rank $rank',
        person.displayName,
        '@${person.handle}',
        PeopleFormat.recordShort(person.record),
        if (detail != null) detail!,
        if (showFollowing && person.viewerIsFollowing) 'Following',
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: highlighted ? AppColors.primaryContainer : AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (rank != null)
                    // A minimum, not a fixed width: ranks line up at normal
                    // sizes and "#12" never wraps at large ones.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 34),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '#$rank',
                          softWrap: false,
                          style: AppTextStyles.questionTitle.copyWith(
                            fontSize: 15,
                            letterSpacing: 0,
                            color: _rankInk,
                          ),
                        ),
                      ),
                    ),
                  PersonAvatar(
                    initials: person.initials,
                    imageUrl: person.avatarUrl,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.displayName, style: styles.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '@${person.handle}'
                          '${showFollowing && person.viewerIsFollowing ? ' · Following' : ''}',
                          style: styles.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (percent == null || detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            recordLine,
                            style: styles.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        if (stacked && stats != null) ...[
                          const SizedBox(height: 6),
                          stats,
                        ],
                      ],
                    ),
                  ),
                  if (!stacked && stats != null) ...[
                    const SizedBox(width: 12),
                    stats,
                  ],
                  const SizedBox(width: 4),
                  const BasilIcon(
                    'arrow-right-outline',
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The prototype's accessible pink ink (#B8173B, 6.4:1 on white).
const _rankInk = Color(0xFFB8173B);

/// [AppAvatar] whose initials keep the circle's size at any text scale. The
/// initials are a picture of the name, not reading text — the name itself is
/// beside it and in the row's semantics, and that text scales fully.
class PersonAvatar extends StatelessWidget {
  final String initials;
  final String? imageUrl;
  final double size;

  const PersonAvatar({
    super.key,
    required this.initials,
    required this.size,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: AppAvatar(
      initials: initials,
      imageUrl: imageUrl,
      size: size,
      backgroundColor: AppColors.primaryContainer,
      textColor: AppColors.onPrimaryContainer,
    ),
  );
}

/// A white rounded group of [PersonRow]s separated by hairlines, as the
/// market list draws its rows.
class PersonRowGroup extends StatelessWidget {
  final List<Widget> rows;
  const PersonRowGroup({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const ColoredBox(
                color: AppColors.surface,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: AppColors.divider),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
