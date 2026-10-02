/// One person to follow (onboarding spec §6 P): avatar, name, real @handle,
/// their public record and their latest live call. No ranks, medals, money
/// or follower counts. At large text the Follow button moves under the name
/// rather than squeezing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

String suggestionRecordLine(PersonSuggestion s) => recordLine(
  s.person.record,
  accuracy: OnboardingCopy.recordAccuracy,
  building: OnboardingCopy.recordBuilding,
  open: OnboardingCopy.recordOpen,
  none: OnboardingCopy.recordNone,
);

class SuggestedPersonRow extends StatelessWidget {
  const SuggestedPersonRow({
    super.key,
    required this.suggestion,
    required this.following,
    required this.onToggle,
  });

  final PersonSuggestion suggestion;
  final bool following;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final person = suggestion.person;
    final name = shownName(
      displayName: person.displayName,
      handle: person.handle,
    );
    final handle = visibleHandle(person.handle);
    final record = suggestionRecordLine(suggestion);
    final latest = suggestion.latestLiveCall;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 21;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: OnbText.name),
        if (handle != null) Text('@$handle', style: OnbText.small),
        const SizedBox(height: 2),
        Text(record, style: OnbText.small),
        if (latest != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SidePill(side: latest.side),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latest.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OnbText.small.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    final button = FollowToggleButton(
      key: ValueKey('follow-${person.id}'),
      following: following,
      onPressed: onToggle,
      name: name,
    );

    return MergeSemantics(
      child: Semantics(
        label: [
          '$name, $record.',
          if (latest != null)
            '${OnboardingCopy.latestCall(latest.side.wire, latest.question)}.',
        ].join(' '),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child:
                stacked
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OnbAvatar(
                              personId: person.id,
                              imageUrl: person.avatarUrl,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _plain(identity)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(left: 56),
                          child: button,
                        ),
                      ],
                    )
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnbAvatar(
                          personId: person.id,
                          imageUrl: person.avatarUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _plain(identity)),
                        const SizedBox(width: 8),
                        button,
                      ],
                    ),
          ),
        ),
      ),
    );
  }

  /// The visible lines are summarised by the row's label; reading them again
  /// would say everything twice.
  Widget _plain(Widget child) => ExcludeSemantics(child: child);
}

/// Follow / Following: outlined in brand pink until chosen, then a pink-wash
/// fill with a check. 36dp visual inside a 48dp target.
class FollowToggleButton extends StatelessWidget {
  const FollowToggleButton({
    super.key,
    required this.following,
    required this.onPressed,
    this.name,
  });

  final bool following;
  final VoidCallback? onPressed;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final reduce = onbReduceMotion(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 150);
    final label = following ? OnboardingCopy.following : OnboardingCopy.follow;
    return Semantics(
      button: true,
      toggled: following,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap:
            onPressed == null
                ? null
                : () {
                  HapticFeedback.lightImpact();
                  onPressed!();
                },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: following ? AppColors.pinkWash : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: AnimatedSwitcher(
                duration: duration,
                child: Row(
                  key: ValueKey(following),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (following) ...[
                      const BasilIcon(
                        'check-outline',
                        size: 16,
                        color: AppColors.pinkInk,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: OnbText.chip.copyWith(
                        fontSize: 14,
                        color: AppColors.pinkInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
