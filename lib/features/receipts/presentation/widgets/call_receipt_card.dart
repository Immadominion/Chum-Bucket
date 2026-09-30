/// Branded evidence artifact. Only supplied call facts enter the shared image.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CallReceiptCard extends StatelessWidget {
  final CallReceipt receipt;

  /// Optional original context supplies thesis and avatar without extending models.
  final CallFeedEntry? entry;
  const CallReceiptCard({super.key, required this.receipt, this.entry});

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
    final icon = switch (receipt.outcome) {
      CallOutcome.correct => 'check-outline',
      CallOutcome.incorrect => 'cross-outline',
      CallOutcome.voided => 'info-circle-outline',
      CallOutcome.pending => 'clock-outline',
    };
    final name = receipt.personDisplayName.trim();
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (receipt.venueIsDemo) ...[
                        Text(
                          'DEMO DATA · NOT A LIVE RESULT',
                          style: callJourneyHeading(context, 12),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'CHUMBUCKET · ON THE RECORD',
                        style: callJourneyBody(
                          12,
                        ).copyWith(color: AppColors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 20),
                      Text(headline, style: callJourneyHeading(context, 32)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BasilIcon(
                            icon,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: callJourneyHeading(context, 12),
                            ),
                          ),
                        ],
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            receipt.personDisplayName,
                            style: callJourneyHeading(context, 18),
                          ),
                          Text(
                            '@${receipt.personHandle}',
                            style: callJourneyBody(12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'CALLED ${receipt.side.wire}',
                      style: callJourneyHeading(context, 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  receipt.marketQuestion,
                  style: callJourneyHeading(context, 22),
                ),
                if (receipt.sideLabel.toUpperCase() != receipt.side.wire) ...[
                  const SizedBox(height: 8),
                  Text(receipt.sideLabel, style: callJourneyBody()),
                ],
                if (original?.call.thesis?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  Text(
                    original!.call.thesis!,
                    style: callJourneyBody().copyWith(
                      color: AppColors.textPrimary,
                      height: 1.7,
                    ),
                  ),
                ],
                const Divider(height: 32),
                CallJourneyFact(
                  'Locked',
                  CallsFormat.timestampUtc(receipt.lockedAt),
                ),
                CallJourneyFact(
                  'Exact timestamp',
                  receipt.lockedAt.toUtc().toIso8601String(),
                ),
                if (receipt.entryPrice == null)
                  CallJourneyFact(
                    receipt.venueLabel == 'Panta' ||
                            receipt.entryProbability == null
                        ? 'Price at call'
                        : 'Entry probability',
                    receipt.venueLabel == 'Panta' ||
                            receipt.entryProbability == null
                        ? 'Price not captured'
                        : CallsFormat.probability(receipt.entryProbability),
                  ),
                if (receipt.entryPrice case final price?) ...[
                  CallJourneyFact(
                    'YES at call',
                    CallsFormat.sharePrice(price.yesPrice),
                  ),
                  CallJourneyFact(
                    'NO at call',
                    CallsFormat.sharePrice(price.noPrice),
                  ),
                  CallJourneyFact(
                    'Price observed',
                    price.observedAtUtc.toIso8601String(),
                  ),
                  const CallJourneyFact(
                    'Price source',
                    SharePriceSnapshot.attribution,
                  ),
                  CallJourneyFact('Price record', price.id),
                  const CallJourneyFact(
                    'Price type',
                    'Indicative, not a trade quote',
                  ),
                ],
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
                    receipt.resolvedAt!.toUtc().toIso8601String(),
                  ),
                if (receipt.resolutionSource != null)
                  CallJourneyFact('Resolved by', receipt.resolutionSource!),
                CallJourneyFact(
                  'Evidence',
                  receipt.marketResolutionId ??
                      'No resolution reference published',
                ),
                if (original != null)
                  CallJourneyFact('Visibility', original.call.visibility.label),
                const Divider(height: 24),
                Text(
                  'Free call. No stake, no position, no money.',
                  style: callJourneyBody(12),
                ),
                const SizedBox(height: 16),
                Text('chumbucket.', style: callJourneyHeading(context, 22)),
                const SizedBox(height: 4),
                Text(
                  'A call. A timestamp. A receipt.',
                  style: callJourneyBody(12),
                ),
                const SizedBox(height: 8),
                Text('Call ${receipt.callId}', style: callJourneyBody(12)),
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
