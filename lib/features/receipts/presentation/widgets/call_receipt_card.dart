/// Branded evidence artifact. Only supplied call facts enter the shared image.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/panta_trading/data/panta_lifecycle_models.dart';
import 'package:chumbucket/features/panta_trading/presentation/panta_market_link.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';

class CallReceiptCard extends StatelessWidget {
  final CallReceipt receipt;

  /// Optional original context supplies thesis and avatar without extending models.
  final CallFeedEntry? entry;

  /// Rounded and outlined as a standalone card. A sheet that uses this card
  /// as its own top passes false so the hero meets the sheet's corners.
  final bool framed;
  const CallReceiptCard({
    super.key,
    required this.receipt,
    this.entry,
    this.framed = true,
  });

  static const _eyebrow = Color(0xFF6B1931);
  static const _muted = Color(0xFF606775);

  @override
  Widget build(BuildContext context) {
    final original = entry?.call.id == receipt.callId ? entry : null;
    final headline = switch (receipt.outcome) {
      CallOutcome.correct => 'Called it.',
      CallOutcome.incorrect => 'Missed this one.',
      CallOutcome.voided => 'Market voided.',
      CallOutcome.pending => 'On record.',
    };
    final label =
        receipt.outcome == CallOutcome.pending
            ? 'Awaiting result'
            : CallsFormat.outcomeSentence(receipt.outcome);
    final name = receipt.personDisplayName.trim();
    final proofStyle = callJourneyBody(12).copyWith(color: _muted);
    // Codex's layout prototype (frame 06): a centred hero on the brand
    // gradient, then the person, the side, the question and the reason, the
    // facts a reader needs, and below a rule the exact proof.
    return Container(
      constraints: BoxConstraints(maxWidth: framed ? 420 : double.infinity),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: framed ? BorderRadius.circular(24) : null,
        border: framed ? Border.all(color: AppColors.outlineVariant) : null,
      ),
      clipBehavior: framed ? Clip.antiAlias : Clip.none,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.lightPrimary, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  // Unframed, the sheet's handle sits in the first 30dp.
                  padding: EdgeInsets.fromLTRB(18, framed ? 20 : 30, 18, 6),
                  child: Column(
                    children: [
                      if (receipt.venueIsDemo) ...[
                        Text(
                          'DEMO DATA · NOT A LIVE RESULT',
                          textAlign: TextAlign.center,
                          style: callJourneyHeading(context, 12),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        'CHUMBUCKET · ON THE RECORD',
                        textAlign: TextAlign.center,
                        style: callJourneyBody(12).copyWith(
                          color: _eyebrow,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        headline,
                        textAlign: TextAlign.center,
                        style: callJourneyHeading(
                          context,
                          38,
                        ).copyWith(letterSpacing: -1.4, height: 1.1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: callJourneyBody(12).copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                ClipPath(
                  clipper: DetailedWaveClipper(),
                  child: Container(height: 28, color: AppColors.surface),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AppAvatar(
                      initials:
                          original?.author.initials ??
                          (name.isEmpty ? '?' : name.characters.first),
                      imageUrl: original?.author.avatarUrl,
                      size: 44,
                      backgroundColor: AppColors.primaryContainer,
                      textColor: AppColors.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.personDisplayName,
                            style: callJourneyHeading(context, 16),
                          ),
                          Text('@${receipt.personHandle}', style: proofStyle),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // The side, stamped Free or Funded beside it.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SidePill(
                      side: receipt.side,
                      label: 'CALLED ${receipt.side.wire}',
                    ),
                    if (receipt.fundedOnPanta)
                      const FundedMarker(large: true)
                    else if (receipt.free)
                      const FreeMarker(large: true),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  receipt.marketQuestion,
                  style: callJourneyHeading(
                    context,
                    22,
                  ).copyWith(letterSpacing: -.6, height: 1.32),
                ),
                if (receipt.sideLabel.toUpperCase() != receipt.side.wire) ...[
                  const SizedBox(height: 8),
                  Text(receipt.sideLabel, style: callJourneyBody()),
                ],
                if (original?.call.thesis?.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Text(
                    original!.call.thesis!,
                    style: callJourneyBody(
                      15,
                    ).copyWith(color: AppColors.textPrimary, height: 1.6),
                  ),
                ],
                const _DashedRule(),
                CallJourneyFact(
                  'Called',
                  CallsFormat.timestampUtc(receipt.lockedAt),
                ),
                // Odds as a percent, USDC and SOL markets alike.
                CallJourneyFact(
                  'Odds at call',
                  switch (receipt.entryPrice) {
                    final price? => CallsFormat.sidesOdds(price),
                    null =>
                      receipt.venueLabel == 'Panta' ||
                              receipt.entryProbability == null
                          ? 'Not captured'
                          : CallsFormat.probability(receipt.entryProbability),
                  },
                ),
                CallJourneyFact(
                  'Venue outcome',
                  receipt.resolution == null
                      ? 'Awaiting result'
                      : receipt.resolution == Resolution.voided
                      ? 'VOID — cancelled'
                      : receipt.resolution!.wire,
                ),
                CallJourneyFact('Source', receipt.venueLabel),
                if (receipt.resolvedAt != null)
                  CallJourneyFact(
                    'Resolved',
                    CallsFormat.timestampUtc(receipt.resolvedAt!),
                  ),
                const _DashedRule(),
                // The exact record behind the facts above, for anyone checking.
                Text('Proof', style: callJourneyHeading(context, 13)),
                const SizedBox(height: 10),
                CallJourneyFact(
                  'Exact timestamp',
                  receipt.lockedAt.toUtc().toIso8601String(),
                ),
                if (receipt.entryPrice case final price?) ...[
                  CallJourneyFact(
                    'Odds observed',
                    price.observedAtUtc.toIso8601String(),
                  ),
                ],
                // Panta's public page, never its authenticated API URL.
                if (receipt.resolvedByPanta) ...[
                  CallJourneyFact(
                    'Resolved by',
                    'Panta · ${pantaMarketUri(receipt.venueMarketId!).host}'
                        '${pantaMarketUri(receipt.venueMarketId!).path}',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PantaMarketLink(
                      venueMarketId: receipt.venueMarketId!,
                      label: 'Check the result on Panta',
                      style: proofStyle,
                    ),
                  ),
                ] else if (receipt.resolutionSource != null &&
                    receipt.venueLabel != 'Panta')
                  CallJourneyFact('Resolved by', receipt.resolutionSource!),
                CallJourneyFact(
                  'Evidence',
                  receipt.marketResolutionId == null
                      ? 'No resolution published yet'
                      : '${receipt.venueLabel} published the result',
                ),
                if (original != null)
                  CallJourneyFact('Visibility', original.call.visibility.label),
                // Raw record IDs, for anyone checking, behind a disclosure.
                _RecordIds(receipt: receipt, style: proofStyle),
                const SizedBox(height: 18),
                // Wordmark left, tagline right; the tagline drops below at
                // large text rather than squeezing either.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text('chumbucket.', style: callJourneyHeading(context, 18)),
                    Text('A call. A timestamp. A receipt.', style: proofStyle),
                  ],
                ),
                if (receipt.venueIsDemo) ...[
                  const SizedBox(height: 16),
                  const CallJourneyNote(
                    'DEMO DATA — sample catalog, not a live market result.',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The exact identifiers behind the receipt, collapsed by default so a shared
/// image shows facts, not UUIDs.
class _RecordIds extends StatelessWidget {
  const _RecordIds({required this.receipt, required this.style});
  final CallReceipt receipt;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ids = <(String, String)>[
      ('Call', receipt.callId),
      if (receipt.entryPrice case final price?) ('Price record', price.id),
      if (receipt.marketResolutionId case final id?) ('Result record', id),
      if (receipt.venueMarketId case final id?) ('Venue market', id),
    ];
    // Its own transparent Material: the receipt is a decorated box, and a
    // list tile paints its ink on the nearest Material.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('receipt-record-ids-${receipt.callId}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          dense: true,
          title: Text('Record IDs', style: style),
          children: [
            for (final (label, value) in ids)
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText('$label  $value', style: style),
              ),
          ],
        ),
      ),
    );
  }
}

/// The prototype's dashed rule between the receipt's sections.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 17),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter()),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = const Color(0xFFCCD0D5)
          ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, .5), Offset(x + 4, .5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}
