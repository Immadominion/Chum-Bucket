/// P "Follow people who call it", and its friends variant "Your friends are
/// here" after sign-in (onboarding spec §6). Every row is a real person from
/// the server; the step is skipped when there are not enough of them.
/// Signed out, choices wait on this phone and apply after sign-in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/suggested_person_row.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key, this.friends = false});

  /// The friends variant (after sign-in).
  final bool friends;

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final rows = friends ? flow.friends : flow.people;
    final selected = friends ? flow.selectedFriends : flow.selectedPeople;
    final loading = !friends && flow.peopleData == StepData.loading;
    final chosen = rows.where((r) => selected.contains(r.id)).length;
    final allChosen = rows.isNotEmpty && chosen == rows.length;
    final title =
        friends ? OnboardingCopy.friendsTitle : OnboardingCopy.peopleTitle;

    return OnboardingScaffold(
      onBack: flow.canGoBack ? flow.back : null,
      progress: flow.progress,
      announce: title,
      actions: [
        ChumbucketPrimaryButton(
          key: const ValueKey('people-continue'),
          label:
              chosen == 0 ? OnboardingCopy.ctaSkip : OnboardingCopy.ctaContinue,
          onPressed:
              loading
                  ? null
                  : () => unawaited(flow.completePeople(friend: friends)),
        ),
      ],
      children: [
        OnbTitle(title),
        const SizedBox(height: 8),
        OnbBody(
          friends ? OnboardingCopy.friendsBody : OnboardingCopy.peopleBody,
        ),
        const SizedBox(height: 24),
        _SectionHeader(
          title:
              friends
                  ? OnboardingCopy.friendsSection
                  : OnboardingCopy.peopleSection,
          action:
              rows.length >= 3
                  ? TextButton(
                    key: const ValueKey('people-follow-all'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      // Flush with the list's edge below it (right, or left
                      // when it moves under the title at large text); the
                      // 48dp target is kept by the minimum size.
                      padding: EdgeInsets.zero,
                      foregroundColor: AppColors.pinkInk,
                    ),
                    onPressed: () {
                      flow.setAllPeople(!allChosen, friend: friends);
                      // A state change, said out loud (§11).
                      onbAnnounce(
                        context,
                        allChosen
                            ? OnboardingCopy.unfollowedAllA11y
                            : OnboardingCopy.followedAllA11y(rows.length),
                      );
                    },
                    child: Text(
                      allChosen
                          ? OnboardingCopy.unfollowAll
                          : OnboardingCopy.followAll,
                      style: OnbText.chip.copyWith(
                        fontSize: 14,
                        color: AppColors.pinkInk,
                      ),
                    ),
                  )
                  : null,
        ),
        const SizedBox(height: 8),
        OnbSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child:
              loading
                  ? const _PeopleSkeleton()
                  : Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.divider),
                        SuggestedPersonRow(
                          suggestion: rows[i],
                          following: selected.contains(rows[i].id),
                          onToggle:
                              () => flow.togglePerson(
                                rows[i].id,
                                friend: friends,
                              ),
                        ),
                      ],
                    ],
                  ),
        ),
        if (!flow.signedIn && chosen > 0) ...[
          const SizedBox(height: 12),
          OnbIconLine(
            key: const ValueKey('people-pending-note'),
            icon: 'info-circle-outline',
            text: OnboardingCopy.pendingNote,
          ),
        ],
      ],
    );
  }
}

/// The section title with "Follow all" at its right; at large text the
/// action moves under the title rather than squeezing it.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(title, style: OnbText.section),
    );
    final action = this.action;
    if (action == null) return heading;
    if (MediaQuery.textScalerOf(context).scale(10) > 15) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [heading, action],
      );
    }
    return Row(children: [Expanded(child: heading), action]);
  }
}

class _PeopleSkeleton extends StatelessWidget {
  const _PeopleSkeleton();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                OnbSkeleton(height: 44, width: 44, radius: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OnbSkeleton(width: 140),
                      SizedBox(height: 8),
                      OnbSkeleton(width: 100, height: 12),
                    ],
                  ),
                ),
                OnbSkeleton(height: 36, width: 84, radius: 999),
              ],
            ),
          ),
      ],
    ),
  );
}
