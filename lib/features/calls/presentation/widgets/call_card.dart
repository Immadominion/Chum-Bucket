/// Person-first call card. Response counts, crowd splits and public financial
/// amounts deliberately do not belong in this surface.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final priceLine = _priceLine(entry);
    final stamp = [
      if (priceLine != null) priceLine,
      CallsFormat.venueAttribution(market),
      if (call.parentCallId != null) 'In response to another call',
    ].join(' · ');
    final back = canRespond && onBack != null;
    final fade = canRespond && onFade != null;
    final respond = canRespond && !back && !fade && onRespond != null;
    final view =
        (!canRespond || (onRespond == null && !back && !fade)) &&
        onOpenCall != null;
    final share =
        entry.isShareableReceipt &&
        call.visibility == CallVisibility.public &&
        onShareReceipt != null;
    // Codex's layout prototype: person, stance, question, reason, one price
    // stamp, then the responses. Every state the badges guard (free vs
    // funded, demo, followers-only, outcome) is still shown.
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenCall ?? onOpenMarket,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor) ...[
                _AuthorRow(entry: entry, onOpenPerson: onOpenPerson),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 7,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SidePill(side: call.side),
                  if (entry.outcome.isSettled)
                    CallOutcomeBadge(outcome: entry.outcome)
                  else
                    Text(
                      CallsFormat.untilClose(market.closesAtUtc),
                      style: _meta,
                    ),
                  FundingStateBadge(state: call.fundingState, quiet: true),
                  DemoVenueBadge(venue: market.venue),
                  if (call.visibility == CallVisibility.followers)
                    const CallBadge(
                      label: 'Followers only',
                      color: AppColors.textSecondary,
                      icon: 'eye-outline',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(market.question, style: AppTextStyles.questionTitle),
              if (call.thesis?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Text(
                  call.thesis!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF0F1F3))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: BasilIcon('lock-outline', size: 14, color: _muted),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(stamp, style: _meta)),
                  ],
                ),
              ),
              if (back || fade || respond || view || share) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (back)
                      Expanded(
                        child: _CardAction(
                          label: 'Back',
                          icon: 'plus-outline',
                          onTap: onBack!,
                        ),
                      ),
                    if (back && fade) const SizedBox(width: 7),
                    if (fade)
                      Expanded(
                        child: _CardAction(
                          label: 'Fade',
                          icon: 'exchange-outline',
                          onTap: onFade!,
                        ),
                      ),
                    if (respond)
                      Expanded(
                        child: _CardAction(
                          label: 'Respond',
                          icon: 'exchange-outline',
                          onTap: onRespond!,
                          primary: true,
                        ),
                      ),
                    if (view)
                      Expanded(
                        child: _CardAction(
                          label: 'View call',
                          icon: 'arrow-right-outline',
                          onTap: onOpenCall!,
                        ),
                      ),
                    if (share) ...[
                      if (back || fade || respond || view)
                        const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Share receipt',
                        onPressed: onShareReceipt,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const BasilIcon(
                          'share-outline',
                          size: 22,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static final _meta = GoogleFonts.montserrat(fontSize: 12, color: _muted);

  /// The prototype's muted grey (#606775): 5.6:1 on white.
  static const _muted = Color(0xFF606775);

  /// What the caller's side cost when the call locked, rounded for reading.
  /// The exact venue string is on the call's detail.
  static String? _priceLine(CallFeedEntry entry) {
    final call = entry.call;
    if (call.entryPrice != null) {
      final price = call.entryPrice!.priceFor(call.side);
      return price == null
          ? '${call.side.wire} price unavailable'
          : '${call.side.wire} was ${CallsFormat.displayPrice(price)} USDC/share';
    }
    if (call.entryProbability != null) {
      return 'Locked at ${CallsFormat.probability(call.entryProbability)}';
    }
    return null;
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
                      fontFamily: 'PPNeueMachina',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@${author.handle} · ${CallsFormat.relative(entry.call.createdAtUtc)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CallCard._meta,
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

  /// The prototype's outline response: #FAFAFA on a #E3E5E8 rule, Machina.
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        foregroundColor: AppColors.textPrimary,
        backgroundColor:
            primary ? AppColors.primaryContainer : const Color(0xFFFAFAFA),
        side: BorderSide(
          color: primary ? AppColors.primaryContainer : const Color(0xFFE3E5E8),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: BasilIcon(icon, size: 18, color: AppColors.textPrimary),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: 'PPNeueMachina',
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
