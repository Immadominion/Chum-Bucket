import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/market_creation_models.dart';

final _local = DateFormat('EEE d MMM y, HH:mm');

/// Local wall-clock time with an explicit marker, for times a person picks.
String localTime(DateTime value) =>
    '${_local.format(value.toLocal())} (your time)';

/// The proposal's state as a pill. Colour is never the only signal: the label
/// always says it.
class ProposalStatusPill extends StatelessWidget {
  const ProposalStatusPill({super.key, required this.status});
  final ProposalStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      ProposalStatus.live => (
        AppColors.successContainer,
        AppColors.onSuccessContainer,
      ),
      ProposalStatus.approved || ProposalStatus.publishing => (
        AppColors.primaryContainer,
        AppColors.onPrimaryContainer,
      ),
      ProposalStatus.pendingReview => (
        AppColors.warningContainer,
        AppColors.onWarningContainer,
      ),
      ProposalStatus.rejected => (
        AppColors.errorContainer,
        AppColors.onErrorContainer,
      ),
      ProposalStatus.withdrawn || ProposalStatus.expired => (
        AppColors.surfaceVariant,
        AppColors.textSecondary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// One proposal in a list: category, state, the full question, its close.
class ProposalTile extends StatelessWidget {
  const ProposalTile({super.key, required this.proposal, required this.onTap});
  final MarketProposal proposal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  proposal.categoryLabel.toUpperCase(),
                  style: AppTextStyles.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: .6,
                  ),
                ),
                ProposalStatusPill(status: proposal.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(proposal.question, style: AppTextStyles.marketRowQuestion),
            const SizedBox(height: 8),
            Text(
              [
                CallsFormat.untilClose(proposal.closesAt),
                if (proposal.proposer != null && !proposal.viewerIsProposer)
                  'by ${proposal.proposer!.atHandle}',
              ].join(' · '),
              style: AppTextStyles.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Powered by Panta", as Panta's terms require beside market creation.
class PoweredByPanta extends StatelessWidget {
  const PoweredByPanta({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Powered by Panta',
    style: AppTextStyles.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    ),
  );
}
