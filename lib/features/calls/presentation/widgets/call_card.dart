/// Person-first call card. Response counts, crowd splits and public financial
/// amounts deliberately do not belong in this surface.
///
/// Compact on purpose: who called what (with their side beside their name),
/// the question, their reason, then ONE row — the few facts as icons on the
/// left, the answers on the right. Prices and venue lines live on the call's
/// detail, not in the list.
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
    final back = canRespond && onBack != null;
    final fade = canRespond && onFade != null;
    final respond = canRespond && !back && !fade && onRespond != null;
    final share =
        entry.isShareableReceipt &&
        call.visibility == CallVisibility.public &&
        onShareReceipt != null;
    final left = CallsFormat.timeLeft(market.closesAtUtc);

    final facts = Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!showAuthor) SidePill(side: call.side),
        if (entry.outcome.isSettled)
          CallOutcomeBadge(outcome: entry.outcome)
        else if (left != null)
          _Fact(
            icon: 'clock-outline',
            text: left,
            semanticsLabel: CallsFormat.untilClose(market.closesAtUtc),
          )
        else
          Text(CallsFormat.untilClose(market.closesAtUtc), style: _meta),
        // A confirmed Panta fill reads "$5 on YES" (or "Funded"); nothing
        // else does. The owner's own pending money call says pending.
        CallFundingMark(entry: entry, quiet: true),
        if (call.visibility == CallVisibility.followers)
          const _Fact(
            icon: 'eye-closed-outline',
            text: '',
            semanticsLabel: 'Followers only',
          ),
        DemoVenueBadge(venue: market.venue),
      ],
    );

    final actions = [
      if (back) _CardAction(label: 'Back', icon: 'add-outline', onTap: onBack!),
      if (fade)
        _CardAction(label: 'Fade', icon: 'exchange-outline', onTap: onFade!),
      if (respond)
        _CardAction(
          label: 'Answer',
          icon: 'exchange-outline',
          onTap: onRespond!,
          primary: true,
        ),
      if (share)
        IconButton(
          tooltip: 'Share receipt',
          onPressed: onShareReceipt,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const BasilIcon(
            'share-outline',
            size: 22,
            color: AppColors.textPrimary,
          ),
        ),
    ];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenCall ?? onOpenMarket,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor) ...[
                _AuthorRow(entry: entry, onOpenPerson: onOpenPerson),
                const SizedBox(height: 10),
              ],
              Text(market.question, style: AppTextStyles.questionTitle),
              if (call.thesis?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(
                  call.thesis!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF0F1F3))),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // One row when it fits; on a narrow phone or at large
                    // text the answers get their own row, full width.
                    final roomy =
                        constraints.maxWidth >= 300 &&
                        MediaQuery.textScalerOf(context).scale(13) <= 17;
                    if (actions.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: facts,
                      );
                    }
                    if (roomy) {
                      return Row(
                        children: [
                          Expanded(child: facts),
                          const SizedBox(width: 8),
                          ..._spaced(actions),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
                          child: facts,
                        ),
                        Row(
                          children: [
                            for (final action in _spaced(actions))
                              action is _CardAction
                                  ? Expanded(child: action)
                                  : action,
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> actions) => [
    for (var i = 0; i < actions.length; i++) ...[
      if (i > 0) const SizedBox(width: 6),
      actions[i],
    ],
  ];

  static final _meta = GoogleFonts.montserrat(fontSize: 12, color: _muted);

  /// The prototype's muted grey (#606775): 5.6:1 on white.
  static const _muted = Color(0xFF606775);
}

/// One fact as an icon and a few characters. [semanticsLabel] says it in
/// full; an icon-only fact passes an empty [text].
class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.text,
    required this.semanticsLabel,
  });
  final String icon;
  final String text;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BasilIcon(icon, size: 15, color: CallCard._muted),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(text, style: CallCard._meta),
        ],
      ],
    ),
  );
}

class _AuthorRow extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback? onOpenPerson;
  const _AuthorRow({required this.entry, this.onOpenPerson});

  @override
  Widget build(BuildContext context) {
    final author = entry.author;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpenPerson,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  AppAvatar(
                    initials: author.initials,
                    imageUrl: author.avatarUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
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
                        const SizedBox(height: 2),
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
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: 'called ${entry.call.side.wire}',
          excludeSemantics: true,
          child: SidePill(side: entry.call.side),
        ),
      ],
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

  /// A compact outline pill: icon and one word, 48dp tall to tap.
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: AppColors.textPrimary,
        backgroundColor:
            primary ? AppColors.primaryContainer : const Color(0xFFFAFAFA),
        side: BorderSide(
          color: primary ? AppColors.primaryContainer : const Color(0xFFE3E5E8),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      icon: BasilIcon(icon, size: 17, color: AppColors.textPrimary),
      label: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          fontFamily: 'PPNeueMachina',
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
