/// One topic: a category that really has open markets right now, with how
/// many (onboarding spec §6 T). 48dp minimum, wraps at any text size, and
/// selection shows a check as well as colour.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class TopicChip extends StatelessWidget {
  const TopicChip({
    super.key,
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final TopicCount topic;
  final bool selected;
  final VoidCallback onTap;

  static const _border = Color(0xFFE5E7EB);
  static const _countFill = Color(0x0F111827);

  @override
  Widget build(BuildContext context) {
    final reduce = onbReduceMotion(context);
    final label = marketCategoryLabel(topic.slug);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 150);
    final ink = selected ? AppColors.onPrimaryContainer : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: OnboardingCopy.topicChipA11y(label, topic.openCount),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('topic-${topic.slug}'),
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.pinkWash : AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.primary : _border,
                width: 1.5,
              ),
            ),
            // Label and count wrap rather than break a word at large text.
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration:
                          reduce
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                      transitionBuilder:
                          (child, animation) => ScaleTransition(
                            scale: CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                            ),
                            child: child,
                          ),
                      child: BasilIcon(
                        selected
                            ? 'check-outline'
                            : MarketGlyph.categoryIcon(topic.slug),
                        key: ValueKey(selected),
                        size: 18,
                        color:
                            selected ? AppColors.pinkInk : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: OnbText.chip.copyWith(color: ink),
                      ),
                    ),
                  ],
                ),
                AnimatedContainer(
                  duration: duration,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.surface : _countFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${topic.openCount}',
                    style: OnbText.meta.copyWith(
                      fontWeight: FontWeight.w500,
                      color: selected ? ink : AppColors.textMuted,
                    ),
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

/// The chips, wrapping (8dp apart), in the order given.
class TopicChips extends StatelessWidget {
  const TopicChips({
    super.key,
    required this.topics,
    required this.selected,
    required this.onToggle,
  });

  final List<TopicCount> topics;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final topic in topics)
        TopicChip(
          topic: topic,
          selected: selected.contains(topic.slug),
          onTap: () => onToggle(topic.slug),
        ),
    ],
  );
}

/// Four chip-shaped placeholders while the catalog loads.
class TopicChipsSkeleton extends StatelessWidget {
  const TopicChipsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OnbSkeleton(height: 48, width: 132, radius: 999),
        OnbSkeleton(height: 48, width: 104, radius: 999),
        OnbSkeleton(height: 48, width: 150, radius: 999),
        OnbSkeleton(height: 48, width: 118, radius: 999),
      ],
    ),
  );
}

/// T's topics as big tiles, two to a row, docked above the button where a
/// thumb reaches on a tall phone. Same data and rules as [TopicChips].
class TopicTiles extends StatelessWidget {
  const TopicTiles({
    super.key,
    required this.topics,
    required this.selected,
    required this.onToggle,
  });

  final List<TopicCount> topics;
  final Set<String> selected;
  final void Function(String slug) onToggle;

  @override
  Widget build(BuildContext context) {
    final rows = <List<TopicCount>>[
      for (var i = 0; i < topics.length; i += 2)
        topics.sublist(i, i + 2 > topics.length ? topics.length : i + 2),
    ];
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var c = 0; c < 2; c++) ...[
                if (c > 0) const SizedBox(width: 10),
                Expanded(
                  child:
                      c < rows[r].length
                          ? OnbReveal(
                            delay: Duration(milliseconds: 40 * (r * 2 + c)),
                            child: _TopicTile(
                              topic: rows[r][c],
                              selected: selected.contains(rows[r][c].slug),
                              onTap: () => onToggle(rows[r][c].slug),
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.selected,
    required this.onTap,
  });

  final TopicCount topic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = onbReduceMotion(context);
    final label = marketCategoryLabel(topic.slug);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: selected,
      label: OnboardingCopy.topicChipA11y(label, topic.openCount),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('topic-${topic.slug}'),
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.pinkWash : AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFE5E7EB),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.surface : AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: BasilIcon(
                        MarketGlyph.categoryIcon(topic.slug),
                        size: 19,
                        color:
                            selected ? AppColors.pinkInk : AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    AnimatedScale(
                      duration: duration,
                      curve: Curves.easeOutBack,
                      scale: selected ? 1 : 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const BasilIcon(
                          'check-outline',
                          size: 14,
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'PPNeueMachina',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  OnboardingCopy.topicTileCount(topic.openCount),
                  style: OnbText.meta,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
