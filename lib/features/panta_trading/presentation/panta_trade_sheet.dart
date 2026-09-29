import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../data/panta_trading_models.dart';
import '../panta_trade_controller.dart';

/// The caller retains/owns the controller, especially after a dropped submit.
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

/// An optional sheet for one existing call. Inherits the existing AppTheme;
/// no routes, providers, identity creation, receipt sharing, or social metadata.
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
      title:
          phase == PantaTradePhase.review
              ? 'Review Panta funding'
              : 'Panta funding',
      subtitle: widget.marketQuestion,
      height: MediaQuery.sizeOf(context).height * 0.86,
      headerLeading: BasilIcon(
        'wallet-solid',
        size: 28.sp,
        color: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 8.h),
              children: [
                _walletContext(),
                SizedBox(height: 16.h),
                if (phase == PantaTradePhase.amount ||
                    phase == PantaTradePhase.preparing)
                  _amountEntry()
                else if (phase == PantaTradePhase.cancelled)
                  _notice(
                    'Approval cancelled. No funding request was submitted.',
                  )
                else ...[
                  _notice(switch (phase) {
                    PantaTradePhase.review =>
                      controller.quoteExpired
                          ? 'This quote expired. Cancel it or edit the amount to get a fresh quote.'
                          : 'Review these amounts, then approve in your wallet.',
                    PantaTradePhase.approving =>
                      'Waiting for your wallet approval…',
                    PantaTradePhase.signed =>
                      'Signed · confirmation unknown. The server may have submitted this order. '
                          'Retry sends the same signed transaction.',
                    PantaTradePhase.submitting =>
                      'Submitting · awaiting server confirmation…',
                    PantaTradePhase.order => _orderCopy(),
                    _ => '',
                  }),
                  SizedBox(height: 14.h),
                  if (controller.prepared != null)
                    _review(controller.prepared!.review)
                  else if (controller.order != null)
                    Text(
                      'Recovered from your existing account. Use Check order status for updates.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.sp,
                      ),
                    ),
                ],
                SizedBox(height: 12.h),
                Text(
                  'Funding is a real USDC buy, separate from your free call. '
                  'Your wallet also pays SOL transaction fees and possible account rent. '
                  'In-app selling and claims are not available in this build.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
                if (controller.status?.enabled == false) ...[
                  SizedBox(height: 12.h),
                  _notice(
                    const PantaException(PantaErrorCode.unavailable).message,
                  ),
                ],
                if (controller.error != null) ...[
                  SizedBox(height: 12.h),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      controller.error!.message,
                      key: const ValueKey('panta-error'),
                      style: TextStyle(color: AppColors.error, fontSize: 13.sp),
                    ),
                  ),
                ],
                SizedBox(height: 14.h),
                Text(
                  pantaAttribution,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 10.h),
            child: Column(
              children: [
                _primaryAction(),
                if (controller.canCheckOrder)
                  TextButton(
                    onPressed: controller.refreshOrder,
                    child: const Text('Check order status'),
                  ),
                if (phase == PantaTradePhase.review && controller.canEditAmount)
                  TextButton(
                    onPressed: () {
                      _amount.clear();
                      controller.editAmount('');
                    },
                    child: const Text('Edit amount'),
                  ),
                TextButton(
                  onPressed: _close,
                  child: Text(controller.canCancel ? 'Cancel' : 'Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletContext() => Container(
    padding: EdgeInsets.all(14.w),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16.r),
      border: Border.all(color: AppColors.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your ${controller.side.label} call · optional funding',
          style: TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          'Wallet: ${controller.wallet}',
          maxLines: 2,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
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
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16.sp),
        decoration: const InputDecoration(
          labelText: 'Amount in USDC',
          hintText: '10.00',
        ),
      ),
      SizedBox(height: 8.h),
      Text(
        'Up to 100 USDC · up to 6 decimal places · maximum slippage 1%',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
      ),
      if (controller.amountText.isNotEmpty && !controller.validAmount)
        Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: Text(
            const PantaException(PantaErrorCode.invalidAmount).message,
            style: TextStyle(color: AppColors.error, fontSize: 12.sp),
          ),
        ),
    ],
  );

  Widget _review(PantaOrderReview review) => Container(
    key: const ValueKey('panta-review'),
    padding: EdgeInsets.all(14.w),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(16.r),
    ),
    child: Column(
      children: [
        _reviewRow('Cost', '${review.amountUsdc} USDC'),
        _reviewRow('Fee', '${review.feeUsdc} USDC'),
        _reviewRow('Estimated shares', review.expectedShares),
        _reviewRow('Average price', '${review.avgPrice} USDC/share'),
        _reviewRow('Maximum slippage', '1%'),
      ],
    ),
  );

  Widget _reviewRow(String label, String value) => Padding(
    padding: EdgeInsets.symmetric(vertical: 6.h),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
        ),
        SizedBox(height: 3.h),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _notice(String text) => Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BasilIcon(
          controller.isFunded ? 'check-outline' : 'clock-outline',
          color:
              controller.isFunded ? AppColors.success : AppColors.textSecondary,
          size: 20.sp,
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            key: const ValueKey('panta-state'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              height: 1.4,
            ),
          ),
        ),
      ],
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
      _ => 'Review funding',
    };
    final enabled = switch (phase) {
      PantaTradePhase.review => true,
      PantaTradePhase.signed => controller.canRetrySigned,
      PantaTradePhase.cancelled || PantaTradePhase.order => true,
      PantaTradePhase.amount => controller.validAmount,
      _ => false,
    };
    return ChallengeButton(
      label: label,
      blurRadius: false,
      enabled: enabled && !controller.isBusy,
      isLoading: controller.isBusy,
      createNewChallenge: () {
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
      },
    );
  }
}
