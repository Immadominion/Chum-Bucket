import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../data/panta_trading_models.dart';
import '../panta_trade_controller.dart';

/// The caller retains the controller, including after an uncertain submission.
/// Dismissal before submit cancels locally; after submit it only closes the UI.
Future<PantaVenueOrder?> showPantaTradeSheet({
  required BuildContext context,
  required PantaTradeController controller,
  required String marketQuestion,
}) => showChumbucketWavySheet<PantaVenueOrder>(
  context: context,
  builder:
      (_) => PantaTradeSheet(
        controller: controller,
        marketQuestion: marketQuestion,
      ),
);

class PantaTradeSheet extends StatefulWidget {
  const PantaTradeSheet({
    super.key,
    required this.controller,
    required this.marketQuestion,
  });
  final PantaTradeController controller;
  final String marketQuestion;

  @override
  State<PantaTradeSheet> createState() => _PantaTradeSheetState();
}

class _PantaTradeSheetState extends State<PantaTradeSheet> {
  late final _amount = TextEditingController(
    text: widget.controller.amountText,
  );
  PantaTradeController get controller => widget.controller;
  final _scroll = ScrollController();
  late PantaTradePhase _lastPhase;

  @override
  void initState() {
    super.initState();
    _lastPhase = controller.phase;
    controller.addListener(_changed);
    unawaited(controller.loadStatus());
  }

  void _changed() {
    if (!mounted) return;
    if (_lastPhase != controller.phase) {
      _lastPhase = controller.phase;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    if (controller.canCancel) controller.cancel();
    _amount.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _close() {
    if (controller.canCancel) controller.cancel();
    Navigator.of(context).pop(controller.order);
  }

  @override
  Widget build(BuildContext context) {
    final phase = controller.phase;
    return ChumbucketWavySheet(
      title: phase == PantaTradePhase.order ? 'Order status' : 'Review trade',
      // The full question is in the scrollable review, never ellipsized by the
      // shared sheet header. Reserve enough wave height at large text.
      headerHeight:
          (MediaQuery.textScalerOf(context).scale(22) > 33 ? 162.0 : 122.0) /
          ScreenUtil().scaleHeight,
      height: MediaQuery.sizeOf(context).height * 0.86,
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BasilIcon(
                'lock-outline',
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Private position · Panta · Solana',
                  style: AppTextStyles.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'BUY ${controller.side.wire}',
                style: AppTextStyles.textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.marketQuestion,
            style: AppTextStyles.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          if (phase == PantaTradePhase.amount ||
              phase == PantaTradePhase.preparing)
            _amountEntry()
          else if (phase == PantaTradePhase.cancelled)
            _notice('Approval cancelled. No funding request was submitted.')
          else ...[
            _notice(switch (phase) {
              PantaTradePhase.review =>
                controller.quoteExpired
                    ? 'This quote expired. Cancel it or edit the amount to get a fresh quote.'
                    : 'Review these amounts, then approve in your wallet.',
              PantaTradePhase.approving => 'Waiting for your wallet approval…',
              PantaTradePhase.signed =>
                'Signed · confirmation unknown. The server may have submitted this order. '
                    'Retry sends the same signed transaction.',
              PantaTradePhase.submitting =>
                'Submitting · awaiting server confirmation…',
              PantaTradePhase.order => _orderCopy(),
              _ => '',
            }),
            const SizedBox(height: 16),
            if (controller.prepared != null)
              _review(controller.prepared!)
            else if (controller.order != null)
              Text(
                'Recovered from your existing account. Use Check order status for updates.',
                style: AppTextStyles.textTheme.bodyMedium,
              ),
          ],
          const SizedBox(height: 16),
          _walletContext(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warningContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'You can lose the full amount. This USDC buy is separate from your free call. '
              'Your call stays unchanged whether you trade or not. '
              'Your wallet also pays SOL transaction fees and possible account rent. '
              'In-app selling and claims are not available in this build.',
              style: AppTextStyles.textTheme.bodySmall?.copyWith(
                color: AppColors.onWarningContainer,
                height: 1.5,
              ),
            ),
          ),
          if (controller.status?.enabled == false) ...[
            const SizedBox(height: 12),
            _notice(const PantaException(PantaErrorCode.unavailable).message),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                controller.error!.message,
                key: const ValueKey('panta-error'),
                style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            pantaAttribution,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _primaryAction(),
          if (controller.canCheckOrder)
            _textAction('Check order status', controller.refreshOrder),
          if (phase == PantaTradePhase.review && controller.canEditAmount)
            _textAction('Edit amount', () {
              _amount.clear();
              controller.editAmount('');
            }),
          _textAction(controller.canCancel ? 'Cancel' : 'Close', _close),
        ],
      ),
    );
  }

  Widget _textAction(String label, VoidCallback onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.all(12),
      foregroundColor: AppColors.onPrimaryContainer,
      textStyle: AppTextStyles.textTheme.labelLarge,
    ),
    child: Text(label),
  );

  Widget _walletContext() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.outlineVariant),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your connected wallet',
          style: AppTextStyles.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(controller.wallet, style: AppTextStyles.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(
          'Solana · network fees paid in SOL',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _amountEntry() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        key: const ValueKey('panta-amount'),
        controller: _amount,
        enabled: controller.canEditAmount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [LengthLimitingTextInputFormatter(32)],
        onChanged: controller.editAmount,
        style: AppTextStyles.textTheme.headlineSmall?.copyWith(fontSize: 28),
        decoration: InputDecoration(
          labelText: 'Amount in USDC',
          labelStyle: AppTextStyles.textTheme.bodyMedium,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.all(16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Up to 100 USDC · up to 6 decimal places · maximum slippage 1%',
        style: AppTextStyles.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      if (controller.amountText.isNotEmpty && !controller.validAmount)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            const PantaException(PantaErrorCode.invalidAmount).message,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.onErrorContainer,
            ),
          ),
        ),
    ],
  );

  Widget _review(PantaPreparedTrade prepared) {
    final review = prepared.review;
    final order = prepared.order;
    final expiry =
        order.expiresAt < order.transaction.expiresAt
            ? order.expiresAt
            : order.transaction.expiresAt;
    String timestamp(int ms) => DateTime.fromMillisecondsSinceEpoch(
      ms,
      isUtc: true,
    ).toIso8601String().replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
    return Column(
      key: const ValueKey('panta-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('USDC to spend', style: AppTextStyles.textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          '${review.amountUsdc} USDC',
          style: AppTextStyles.textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _reviewRow(
                'Estimated shares',
                '${review.expectedShares} ${controller.side.wire}',
              ),
              _reviewRow('Average price', '${review.avgPrice} USDC/share'),
              _reviewRow('Venue fee', '${review.feeUsdc} USDC'),
              _reviewRow('Maximum slippage', '${review.maxSlippageBps / 100}%'),
              const Divider(color: AppColors.divider),
              // The existing contract has no all-in max-spend or SOL fee estimate.
              // Do not derive either from illustrative arithmetic.
              _reviewRow(
                'Maximum total spend',
                'Not supplied in this quote. Check the wallet request.',
              ),
              _reviewRow(
                'Network fee (SOL)',
                'Estimate not supplied. Check the wallet request.',
              ),
              _reviewRow('Quote created', timestamp(order.createdAt)),
              _reviewRow('Quote expires', timestamp(expiry)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Wallet approval is not a confirmed fill.',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _notice(String text) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            controller.isFunded
                ? AppColors.successContainer
                : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BasilIcon(
            controller.isFunded ? 'check-outline' : 'clock-outline',
            color:
                controller.isFunded
                    ? AppColors.onSuccessContainer
                    : AppColors.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('panta-state'),
              style: AppTextStyles.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );

  String _orderCopy() {
    final order = controller.order!;
    return switch (order.fundingState) {
      PantaFundingState.filled => 'Funded · fill confirmed by the server.',
      PantaFundingState.partial =>
        'Partially filled · check again for the final result.',
      PantaFundingState.submitted => 'Submitted · awaiting fill confirmation.',
      PantaFundingState.quoted => 'Quote ready · no fill has been confirmed.',
      _ => order.fundingState.label,
    };
  }

  Widget _primaryAction() {
    final phase = controller.phase;
    final label = switch (phase) {
      PantaTradePhase.review =>
        controller.quoteExpired ? 'Cancel expired quote' : 'Approve in wallet',
      PantaTradePhase.signed => 'Retry same signed transaction',
      PantaTradePhase.cancelled => 'Enter a new amount',
      PantaTradePhase.order => 'Done',
      PantaTradePhase.preparing => 'Preparing quote…',
      PantaTradePhase.approving => 'Awaiting wallet…',
      PantaTradePhase.submitting => 'Submitting…',
      _ => 'Review order',
    };
    final enabled = switch (phase) {
      PantaTradePhase.review => true,
      PantaTradePhase.signed => controller.canRetrySigned,
      PantaTradePhase.cancelled || PantaTradePhase.order => true,
      PantaTradePhase.amount => controller.validAmount,
      _ => false,
    };
    // Same transition guards and controller methods as the existing sheet.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.lightPrimary, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextButton(
        onPressed:
            enabled && !controller.isBusy
                ? () {
                  switch (phase) {
                    case PantaTradePhase.review:
                      if (controller.quoteExpired) {
                        controller.cancel();
                      } else {
                        unawaited(controller.approveReview());
                      }
                    case PantaTradePhase.signed:
                      unawaited(controller.retrySignedSubmit());
                    case PantaTradePhase.cancelled:
                      _amount.clear();
                      controller.editAmount('');
                    case PantaTradePhase.order:
                      _close();
                    default:
                      FocusScope.of(context).unfocus();
                      unawaited(controller.prepare());
                  }
                }
                : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(16),
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.onPrimaryContainer,
          textStyle: AppTextStyles.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
