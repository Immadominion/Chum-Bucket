/// Welcome's live strip: real calls from production (or, when nobody has a
/// live call, markets open on Panta). Up to six cards, 280dp wide with the
/// next one peeking, as tall as the tallest card so no question is ever cut.
/// Nothing here is a fixture: an empty source removes the strip.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_format.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';

class LiveCallStrip extends StatelessWidget {
  const LiveCallStrip({
    super.key,
    required this.strip,
    required this.onOpenCall,
    required this.onOpenMarket,
    this.controller,
    this.now,
  });

  final LiveStrip strip;
  final void Function(CallFeedEntry entry) onOpenCall;
  final void Function(VenueMarket market) onOpenMarket;
  final ScrollController? controller;
  final DateTime? now;

  static const double cardWidth = 280;

  @override
  Widget build(BuildContext context) {
    final items = strip.items;
    final width = MediaQuery.sizeOf(context).width;
    // Narrow phones still show the next card's edge.
    final card = width < 360 ? width - 56 : cardWidth;
    return Semantics(
      label: '${items.length} ${items.length == 1 ? 'item' : 'items'}',
      container: true,
      explicitChildNodes: true,
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: OnbSpace.gutter),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(
                  width: card,
                  child: OnbReveal(
                    delay: Duration(milliseconds: 60 * (i < 3 ? i : 3)),
                    duration: const Duration(milliseconds: 320),
                    rise: i < 3 ? 16 : 0,
                    child: switch (items[i]) {
                      LiveCallItem(:final entry) => LiveCallCard(
                        entry: entry,
                        now: now,
                        onTap: () => onOpenCall(entry),
                      ),
                      LiveMarketItem(:final market) => LiveMarketCard(
                        market: market,
                        now: now,
                        onTap: () => onOpenMarket(market),
                      ),
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    required this.onTap,
    required this.label,
  });

  final Widget child;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(OnbSpace.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

/// "{name} called YES" on a real question.
class LiveCallCard extends StatelessWidget {
  const LiveCallCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.now,
  });

  final CallFeedEntry entry;
  final VoidCallback onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final author = entry.author;
    final name = shownName(
      displayName: author.displayName,
      handle: author.handle,
    );
    final handle = visibleHandle(author.handle);
    final side = entry.call.side.wire;
    final closes = OnbFormat.closesLine(entry.market, now: now);
    final until = OnbFormat.until(entry.market.closesAtUtc, now: now);
    return _CardShell(
      onTap: onTap,
      label:
          '${OnboardingCopy.welcomeCardCalled(name, side)} on '
          '${entry.market.question}.'
          '${until == null ? '' : ' Closes $until.'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OnbAvatar(name: name, imageUrl: author.avatarUrl, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: OnbText.name),
                    if (handle != null) Text('@$handle', style: OnbText.small),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SidePill(
            side: entry.call.side,
            label: OnboardingCopy.calledSide(side),
          ),
          const SizedBox(height: 10),
          Text(entry.market.question, style: OnbText.question),
          const Spacer(),
          const SizedBox(height: 12),
          Text(closes, style: OnbText.meta),
        ],
      ),
    );
  }
}

/// A market open on Panta, when no live call exists.
class LiveMarketCard extends StatelessWidget {
  const LiveMarketCard({
    super.key,
    required this.market,
    required this.onTap,
    this.now,
  });

  final VenueMarket market;
  final VoidCallback onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final until = OnbFormat.until(market.closesAtUtc, now: now);
    return _CardShell(
      onTap: onTap,
      label: '${market.question}.${until == null ? '' : ' Closes $until.'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarketGlyph(market: market),
          const SizedBox(height: 12),
          Text(market.question, style: OnbText.question),
          const Spacer(),
          const SizedBox(height: 12),
          Text(OnbFormat.closesLine(market, now: now), style: OnbText.meta),
        ],
      ),
    );
  }
}

/// Two card-shaped placeholders while the live sources answer.
class LiveStripSkeleton extends StatelessWidget {
  const LiveStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: OnbSpace.gutter),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Container(
              width: LiveCallStrip.cardWidth,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(OnbSpace.radius),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OnbSkeleton(height: 32, width: 32, radius: 16),
                      SizedBox(width: 10),
                      OnbSkeleton(width: 120),
                    ],
                  ),
                  SizedBox(height: 14),
                  OnbSkeleton(width: 84, height: 22),
                  SizedBox(height: 12),
                  OnbSkeleton(width: 220),
                  SizedBox(height: 8),
                  OnbSkeleton(width: 160),
                  SizedBox(height: 18),
                  OnbSkeleton(width: 120, height: 12),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
