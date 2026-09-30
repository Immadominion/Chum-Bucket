/// Person-first call card. Response counts, crowd splits and public financial
/// amounts deliberately do not belong in this surface.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CallCard extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback? onOpenCall;
  final VoidCallback? onOpenMarket;
  final VoidCallback? onOpenPerson;
  final VoidCallback? onRespond;
  final VoidCallback? onBack;
  final VoidCallback? onFade;
  final VoidCallback? onShareReceipt;
  final bool showAuthor;

  const CallCard({
    super.key,
    required this.entry,
    this.onOpenCall,
    this.onOpenMarket,
    this.onOpenPerson,
    this.onRespond,
    this.onBack,
    this.onFade,
    this.onShareReceipt,
    this.showAuthor = true,
  });

  @override
  Widget build(BuildContext context) {
    final call = entry.call;
    final market = entry.market;
    final canRespond =
        market.status.acceptsNewCalls &&
        (market.closesAtUtc == null ||
            market.closesAtUtc!.isAfter(DateTime.now().toUtc())) &&
        !entry.outcome.isSettled;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenCall ?? onOpenMarket,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor) ...[
                _AuthorRow(entry: entry, onOpenPerson: onOpenPerson),
                const SizedBox(height: 18),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SideChip(side: call.side, label: call.side.wire),
                  if (entry.outcome.isSettled)
                    CallOutcomeBadge(outcome: entry.outcome)
                  else
                    Text(
                      CallsFormat.untilClose(market.closesAtUtc),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  DemoVenueBadge(venue: market.venue),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                market.question,
                style: const TextStyle(
                  fontFamily: 'PPNeueMachina',
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (call.thesis?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Text(
                  call.thesis!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FundingStateBadge(state: call.fundingState),
                  if (call.visibility == CallVisibility.followers)
                    const CallBadge(
                      label: 'Followers only',
                      color: AppColors.textSecondary,
                      icon: 'eye-outline',
                    ),
                ],
              ),
              if (call.entryPrice != null || call.entryProbability != null) ...[
                const SizedBox(height: 10),
                Text(
                  call.entryPrice != null
                      ? 'Called at ${CallsFormat.sharePrice(call.entryPrice!.priceFor(call.side))}'
                      : 'Locked at ${CallsFormat.probability(call.entryProbability)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                CallsFormat.venueAttribution(market),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (call.parentCallId != null) ...[
                const SizedBox(height: 6),
                const Text(
                  'In response to another call',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.outlineVariant),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (canRespond && onBack != null)
                    _CardAction(
                      label: 'Back',
                      icon: 'arrow-up-outline',
                      onTap: onBack!,
                    ),
                  if (canRespond && onFade != null)
                    _CardAction(
                      label: 'Fade',
                      icon: 'arrow-down-outline',
                      onTap: onFade!,
                    ),
                  if (canRespond &&
                      onBack == null &&
                      onFade == null &&
                      onRespond != null)
                    _CardAction(
                      label: 'Respond',
                      icon: 'exchange-outline',
                      onTap: onRespond!,
                      primary: true,
                    ),
                  if ((!canRespond ||
                          (onRespond == null &&
                              onBack == null &&
                              onFade == null)) &&
                      onOpenCall != null)
                    _CardAction(
                      label: 'View call',
                      icon: 'arrow-right-outline',
                      onTap: onOpenCall!,
                    ),
                  if (entry.isShareableReceipt &&
                      call.visibility == CallVisibility.public &&
                      onShareReceipt != null)
                    _CardAction(
                      label: 'Receipt',
                      icon: 'share-outline',
                      onTap: onShareReceipt!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback? onOpenPerson;
  const _AuthorRow({required this.entry, this.onOpenPerson});

  @override
  Widget build(BuildContext context) {
    final author = entry.author;
    return InkWell(
      onTap: onOpenPerson,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            AppAvatar(
              initials: author.initials,
              imageUrl: author.avatarUrl,
              size: 42,
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@${author.handle} · ${CallsFormat.relative(entry.call.createdAtUtc)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool primary;
  const _CardAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(92, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        foregroundColor: AppColors.textPrimary,
        backgroundColor:
            primary ? AppColors.primaryContainer : AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: BasilIcon(icon, size: 16, color: AppColors.textPrimary),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
