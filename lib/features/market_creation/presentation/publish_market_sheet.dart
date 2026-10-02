/// The paid Panta create, reviewed before the wallet opens.
///
/// Header value is the exact creation fee from Panta's live quote. The body
/// says where it goes, what else it costs, who pays, that it is not
/// refundable, and that the market becomes public. The sheet cannot be
/// dismissed while the wallet is open or the create is being submitted.
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';

import '../data/market_creation_models.dart';
import '../market_creation_controller.dart';
import 'widgets/proposal_widgets.dart';

/// Returns the latest proposal after a submit, or null when nothing was sent.
Future<MarketProposal?> showPublishMarketSheet({
  required BuildContext context,
  required PublishMarketController controller,
}) => showChumbucketWavySheet<MarketProposal>(
  context: context,
  builder: (_) => PublishMarketSheet(controller: controller),
);

class PublishMarketSheet extends StatefulWidget {
  const PublishMarketSheet({super.key, required this.controller});
  final PublishMarketController controller;

  @override
  State<PublishMarketSheet> createState() => _PublishMarketSheetState();
}

class _PublishMarketSheetState extends State<PublishMarketSheet> {
  PublishMarketController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    if (c.phase == PublishPhase.idle) unawaited(c.prepare());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(c.submitted ? c.proposal : null);

  String _short(String address) =>
      address.length <= 10
          ? address
          : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

  @override
  Widget build(BuildContext context) {
    final review = c.review;
    final fee =
        review == null
            ? null
            : '${formatUsdcBaseUnits(review.feeBaseUnits)} USDC';
    return ChumbucketWavySheet(
      title: c.phase == PublishPhase.done ? 'Market submitted' : 'Creation fee',
      value: c.phase == PublishPhase.done ? null : fee,
      subtitle: c.proposal.question,
      canDismiss: c.canDismiss,
      onClose: _close,
      // The shell's contract: bodies shrink-wrap and scroll, so 2x text or a
      // short screen never clips the fee breakdown.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._body(review),
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(
                c.error!,
                style: AppTextStyles.sheetStatement.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const PoweredByPanta(),
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: _actions()),
      ),
    );
  }

  List<Widget> _body(PublishReview? review) {
    switch (c.phase) {
      case PublishPhase.idle:
      case PublishPhase.preparing:
        return [
          _statement(
            'Getting Panta’s live creation fee. Nothing is signed yet.',
          ),
        ];
      case PublishPhase.done:
        final live = c.proposal.status == ProposalStatus.live;
        return [
          _statement(
            live
                ? 'Your market is live on Panta. Anyone can now make a call on it.'
                : 'Your wallet approved the create and it was sent. Waiting for Solana and Panta to confirm. Check its status from the market’s page.',
          ),
        ];
      case PublishPhase.review:
      case PublishPhase.signing:
      case PublishPhase.submitting:
      case PublishPhase.failed:
        if (review == null) {
          return [
            _statement(
              'No fee is reviewed yet. Get a fresh quote to continue.',
            ),
          ];
        }
        return [
          _row(
            'Seeds the market’s liquidity',
            '${formatUsdcBaseUnits(review.liquidityBaseUnits)} USDC',
          ),
          _row(
            'Panta platform fee',
            '${formatUsdcBaseUnits(review.platformBaseUnits)} USDC',
          ),
          _row('Solana network fee and account rent', 'Small SOL amount'),
          _row('Paid from', _short(review.wallet)),
          const SizedBox(height: 10),
          _statement(
            'The fee is not refundable. The market goes into Panta’s public catalog and the paying wallet is its on-chain creator. '
            'It closes ${localTime(c.proposal.closesAt)}.',
          ),
          if (c.phase == PublishPhase.signing)
            _statement('Approve in your wallet…')
          else if (c.phase == PublishPhase.submitting)
            _statement('Publishing on Panta…'),
        ];
    }
  }

  List<Widget> _actions() {
    final close = ChumbucketTextAction(
      label: c.phase == PublishPhase.done ? 'Done' : 'Not now',
      color: AppColors.textSecondary,
      onPressed: c.canDismiss ? _close : null,
    );
    switch (c.phase) {
      case PublishPhase.idle:
      case PublishPhase.preparing:
        return [
          const ChumbucketPrimaryButton(
            label: 'Getting fee…',
            busy: true,
            onPressed: null,
          ),
          close,
        ];
      case PublishPhase.review:
        return [
          ChumbucketPrimaryButton(
            label: c.reviewExpired ? 'Get a fresh fee' : 'Approve in wallet',
            onPressed: c.reviewExpired ? c.prepare : c.approveAndSubmit,
          ),
          close,
        ];
      case PublishPhase.signing:
      case PublishPhase.submitting:
        return [
          ChumbucketPrimaryButton(
            label: 'Approve in wallet',
            busy: true,
            busyLabel:
                c.phase == PublishPhase.signing
                    ? 'Waiting for wallet…'
                    : 'Publishing…',
            onPressed: null,
          ),
        ];
      case PublishPhase.failed:
        return [
          ChumbucketPrimaryButton(
            // Signed bytes are retried as-is; otherwise a fresh quote.
            label: c.submitted ? 'Try sending again' : 'Get a fresh fee',
            onPressed: c.submitted ? c.submit : c.prepare,
          ),
          close,
        ];
      case PublishPhase.done:
        return [ChumbucketPrimaryButton(label: 'Done', onPressed: _close)];
    }
  }

  Widget _statement(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppTextStyles.sheetStatement),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 2,
      children: [
        Text(
          label,
          style: AppTextStyles.sheetStatement.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.sheetStatement.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
