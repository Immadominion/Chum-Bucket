/// The money call, from tap to fill: [runMoneyCall] prepares it (the same
/// tap opens the deposit sheet when the balance is short, and carries on by
/// itself when the funds land), then [MoneyCallSheet] shows the compact
/// review — pay, about what it pays if right, the fee, all in dollars — signs
/// with the current signer, and stays on "Pending" until the server says
/// FUNDED. A failed trade offers: try again, keep it free, or discard.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart'
    show CallFeedEntry, CallFunding;
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallInlineError, callJourneyBody, callJourneyHeading;
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart'
    show PantaReviewedBuy;
import 'package:chumbucket/features/panta_trading/panta_trading.dart'
    show PantaMark, PantaMoney, PantaTradingClient;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_client.dart';
import '../data/money_models.dart';
import '../money_call_controller.dart';
import 'money_amount_row.dart' show moneyOf;
import 'money_dependencies.dart';
import 'money_deposit_sheet.dart';

/// How a money call ended for the screen that started it.
class MoneyCallOutcome {
  const MoneyCallOutcome({this.call, this.moneyCall, this.error});

  /// The person's call, when one exists (pending calls are theirs alone).
  final CallFeedEntry? call;
  final MoneyCallView? moneyCall;

  /// Why nothing happened, in words, for the sheet that asked.
  final String? error;
}

/// Runs one tap. Null: the person backed out and nothing was created.
Future<MoneyCallOutcome?> runMoneyCall(
  BuildContext context,
  MoneyCallRequest request, {
  ValueChanged<bool>? onBusy,
}) async {
  final deps = MoneyDependencies.of(context);
  if (deps == null) {
    return const MoneyCallOutcome(error: 'Money isn’t available here yet.');
  }
  final attest = deps.ensureAttestation;
  if (attest != null && !await attest(context)) return null;
  if (!context.mounted) return null;

  MoneyCallController? controller;
  final reviewed = PantaReviewedBuy(
    venueMarketId: request.venueMarketId,
    side: request.side,
    amountBaseUnits: () => controller?.prepared?.order.amountBaseUnits,
  );
  var signer = deps.buySigner(reviewed);
  if (signer == null && deps.setUpWallet != null) {
    if (!await deps.setUpWallet!(context) || !context.mounted) return null;
    signer = deps.buySigner(reviewed);
  }
  if (signer == null) {
    return const MoneyCallOutcome(error: 'Set up your wallet first.');
  }

  final client = deps.createClient();
  final trading = deps.createTradingClient();
  final created = MoneyCallController(
    client: client,
    trading: trading,
    request: request,
    signer: signer,
    topUp: deps.gasTopUp,
    pollEvery: deps.pollEvery,
  );
  controller = created;
  final money = moneyOf(context, listen: false);
  try {
    onBusy?.call(true);
    await created.prepare();
    while (created.step == MoneyCallStep.needsFunds) {
      if (!context.mounted) return null;
      onBusy?.call(false);
      final short = created.needsFunds!;
      final landed = await showMoneyDepositSheet(
        context,
        shortfall: short.shortfallBaseUnits,
        target: short.neededBaseUnits,
      );
      if (!landed || !context.mounted) return null;
      onBusy?.call(true);
      await created.continueAfterFunds();
    }
    onBusy?.call(false);
    if (!context.mounted) return null;
    switch (created.step) {
      case MoneyCallStep.review:
        final outcome = await showChumbucketWavySheet<MoneyCallOutcome>(
          context: context,
          builder: (_) => MoneyCallSheet(controller: created),
        );
        return outcome;
      case MoneyCallStep.funded || MoneyCallStep.free:
        return MoneyCallOutcome(
          call: created.call,
          moneyCall: created.moneyCall,
        );
      case MoneyCallStep.expired || MoneyCallStep.discarded:
        return null;
      default:
        return MoneyCallOutcome(
          error:
              created.error ??
              const MoneyException(MoneyErrorKind.unavailable).message,
        );
    }
  } finally {
    onBusy?.call(false);
    created.dispose();
    client.close();
    trading.close();
    unawaited(money?.refresh());
  }
}

/// Picks up the owner's pending call from its own screen: finish (a fresh
/// quote, then sign), keep it free, or discard it.
Future<MoneyCallOutcome?> resumeMoneyCall(
  BuildContext context, {
  required CallFeedEntry call,
}) async {
  final deps = MoneyDependencies.of(context);
  if (deps == null) return null;
  final MoneyClient client = deps.createClient();
  final MoneyCallStatus status;
  try {
    status = await client.callStatus(call.call.id);
  } on MoneyException catch (e) {
    client.close();
    return MoneyCallOutcome(error: e.message);
  }
  if (!context.mounted) {
    client.close();
    return null;
  }
  final moneyCall = status.moneyCall;
  MoneyCallController? controller;
  final signer = deps.buySigner(
    PantaReviewedBuy(
      venueMarketId: call.market.venueMarketId,
      side: moneyCall.side,
      amountBaseUnits: () => controller?.prepared?.order.amountBaseUnits,
    ),
  );
  if (signer == null || signer.address != moneyCall.wallet) {
    client.close();
    return const MoneyCallOutcome(error: 'Open the wallet that pays for this.');
  }
  final PantaTradingClient trading = deps.createTradingClient();
  final created = MoneyCallController.resume(
    client: client,
    trading: trading,
    moneyCall: moneyCall,
    call: call,
    signer: signer,
    topUp: deps.gasTopUp,
    pollEvery: deps.pollEvery,
  );
  controller = created;
  final money = moneyOf(context, listen: false);
  try {
    return await showChumbucketWavySheet<MoneyCallOutcome>(
      context: context,
      builder:
          (_) => MoneyCallSheet(controller: created, discardOnClose: false),
    );
  } finally {
    created.dispose();
    client.close();
    trading.close();
    unawaited(money?.refresh());
  }
}

class MoneyCallSheet extends StatefulWidget {
  const MoneyCallSheet({
    super.key,
    required this.controller,
    this.discardOnClose = true,
  });
  final MoneyCallController controller;

  /// From the tap that made it: closing before signing lets the call go.
  /// Picked up from its own screen: closing leaves it as it was.
  final bool discardOnClose;

  @override
  State<MoneyCallSheet> createState() => _MoneyCallSheetState();
}

class _MoneyCallSheetState extends State<MoneyCallSheet> {
  MoneyCallController get c => widget.controller;
  bool _depositOpen = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // A retry that comes back short opens the deposit sheet, as a first
    // tap does, and carries on when the funds land.
    if (c.step == MoneyCallStep.needsFunds && !_depositOpen) {
      _depositOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final short = c.needsFunds;
        if (!mounted || short == null) return;
        final landed = await showMoneyDepositSheet(
          context,
          shortfall: short.shortfallBaseUnits,
          target: short.neededBaseUnits,
        );
        _depositOpen = false;
        if (landed && mounted) unawaited(c.continueAfterFunds());
      });
    }
  }

  /// Closing before anything was signed lets the call go: nothing is left
  /// behind that the person didn't choose. Once signed, it stays theirs.
  Future<void> _close() async {
    if (!c.canClose) return;
    final navigator = Navigator.of(context);
    switch (c.step) {
      case MoneyCallStep.review ||
          MoneyCallStep.failed ||
          MoneyCallStep.needsFunds:
        if (widget.discardOnClose && (c.moneyCall?.canDiscard ?? false)) {
          await c.discard();
        }
        navigator.pop();
      case MoneyCallStep.pending ||
          MoneyCallStep.sent ||
          MoneyCallStep.funded ||
          MoneyCallStep.free:
        navigator.pop(
          MoneyCallOutcome(call: c.call, moneyCall: c.moneyCall),
        );
      default:
        navigator.pop();
    }
  }

  /// Lets this call go and returns to where the call was made.
  Future<void> _newCall() async {
    final navigator = Navigator.of(context);
    if (c.moneyCall?.canDiscard ?? false) await c.discard();
    navigator.pop();
  }

  String get _sideLabel => 'Call ${c.request.side.wire}';
  String get _amount => moneyDollars(c.request.amountBaseUnits);

  @override
  Widget build(BuildContext context) {
    return ChumbucketWavySheet(
      title: switch (c.step) {
        MoneyCallStep.funded => 'On record',
        MoneyCallStep.pending || MoneyCallStep.sent => 'Pending',
        MoneyCallStep.failed => 'Didn’t go through',
        _ => _sideLabel,
      },
      canDismiss: c.canClose,
      onClose: () => unawaited(_close()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              c.request.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: callJourneyHeading(context, 17),
            ),
            const SizedBox(height: 14),
            ..._body(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final error = c.error;
    switch (c.step) {
      case MoneyCallStep.review ||
          MoneyCallStep.signing ||
          MoneyCallStep.submitting ||
          MoneyCallStep.preparing:
        return [
          if (c.prepared case final prepared?)
            _ReviewRows(
              pay: PantaMoney.dollarsOf(prepared.review.amountUsdc),
              ifRight: _ifRight(prepared.review.expectedShares),
              fee: PantaMoney.dollarsOf(prepared.review.feeUsdc),
            ),
          if (error != null) ...[
            const SizedBox(height: 12),
            CallInlineError(error),
          ],
          const SizedBox(height: 12),
          // Panta's compact mark, beside the trade it attributes.
          const Align(alignment: Alignment.centerRight, child: PantaMark()),
          const SizedBox(height: 10),
          ChumbucketPrimaryButton(
            key: const ValueKey('money-sign'),
            label: '$_sideLabel · $_amount',
            busy: c.busy,
            busyLabel: switch (c.step) {
              MoneyCallStep.signing =>
                c.signer.opensWalletApp ? 'Approve in your wallet…' : 'Signing…',
              MoneyCallStep.submitting => 'Sending…',
              _ => 'Please wait…',
            },
            onPressed:
                c.step == MoneyCallStep.review && !c.busy ? c.sign : null,
          ),
        ];
      case MoneyCallStep.sent:
        return [
          _StateLine(
            icon: 'clock-outline',
            badge: const _PendingBadge(),
            child: Text(
              moneyOnSide(c.request.amountBaseUnits, c.request.side),
              style: callJourneyHeading(context, 18),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            CallInlineError(error),
          ],
          const SizedBox(height: 16),
          // The identical signed bytes; nothing is signed again.
          ChumbucketPrimaryButton(
            key: const ValueKey('money-resend'),
            label: 'Send again',
            busy: c.busy,
            onPressed: c.busy ? null : c.resend,
          ),
        ];
      case MoneyCallStep.pending:
        return [
          _StateLine(
            icon: 'clock-outline',
            badge: const _PendingBadge(),
            child: Text(
              moneyOnSide(c.request.amountBaseUnits, c.request.side),
              style: callJourneyHeading(context, 18),
            ),
          ),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Done',
            neutral: true,
            onPressed: () => unawaited(_close()),
          ),
        ];
      case MoneyCallStep.funded:
        final money = c.moneyCall!;
        return [
          const Center(
            child: ChumbucketStateArt(ChumbucketStateArtwork.success, size: 96),
          ),
          const SizedBox(height: 8),
          Center(
            child: FundedMarker(
              key: const ValueKey('money-funded'),
              // The confirmed fill; "Funded" when its amount is unknown.
              amount: switch (money.filledBaseUnits) {
                // Below $1 a fill earns no amount stamp.
                final filled? when filled >= CallFunding.minStampBaseUnits =>
                  moneyOnSide(filled, money.side),
                _ => null,
              },
              large: true,
            ),
          ),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Done',
            neutral: true,
            onPressed: () => unawaited(_close()),
          ),
        ];
      case MoneyCallStep.failed || MoneyCallStep.needsFunds:
        final money = c.moneyCall;
        final notSent =
            money != null &&
            (money.trade == MoneyTradeState.none ||
                money.trade == MoneyTradeState.quoted);
        return [
          const Center(
            child: ChumbucketStateArt(ChumbucketStateArtwork.error, size: 96),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? (notSent ? 'Not sent yet.' : 'The trade didn’t fill.'),
            key: const ValueKey('money-failed'),
            textAlign: TextAlign.center,
            style: callJourneyBody(13),
          ),
          const SizedBox(height: 16),
          if (c.retryRefused)
            // The price moved past the slippage (or time is up): a new call
            // at today's price is the way on. This one goes.
            ChumbucketPrimaryButton(
              key: const ValueKey('money-new-call'),
              label: 'New call',
              neutral: true,
              busy: c.busy,
              onPressed: c.busy ? null : _newCall,
            )
          else if (money?.canRetry ?? false)
            ChumbucketPrimaryButton(
              key: const ValueKey('money-retry'),
              label: 'Try again · $_amount',
              busy: c.busy,
              onPressed: c.busy ? null : c.retry,
            ),
          if (money?.canKeepFree ?? false)
            ChumbucketTextAction(
              key: const ValueKey('money-keep-free'),
              label: 'Keep it free',
              color: AppColors.textPrimary,
              onPressed: c.busy ? null : c.keepFree,
            ),
          if (money?.canDiscard ?? false)
            ChumbucketTextAction(
              key: const ValueKey('money-discard'),
              label: 'Discard',
              color: AppColors.textMuted,
              onPressed: c.busy ? null : c.discard,
            ),
        ];
      case MoneyCallStep.free:
        return [
          const Center(child: FreeMarker(large: true)),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Done',
            neutral: true,
            onPressed: () => unawaited(_close()),
          ),
        ];
      case MoneyCallStep.discarded ||
          MoneyCallStep.expired ||
          MoneyCallStep.stopped ||
          MoneyCallStep.idle:
        return [
          const Center(
            child: ChumbucketStateArt(ChumbucketStateArtwork.record, size: 96),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: callJourneyBody(13),
            ),
          ],
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Done',
            neutral: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ];
    }
  }
}

/// About what the quoted shares pay if right ($1 each), to the cent below.
String _ifRight(String shares) {
  final parts = shares.split('.');
  final cents = parts.length > 1 ? parts[1].padRight(2, '0').substring(0, 2) : '00';
  return '~${PantaMoney.dollarsOf('${parts.first}.$cents')}';
}

class _ReviewRows extends StatelessWidget {
  const _ReviewRows({required this.pay, required this.ifRight, required this.fee});
  final String pay;
  final String ifRight;
  final String fee;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('money-review'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        _row(context, 'wallet-outline', 'Pay', pay),
        _row(context, 'award-outline', 'If right', ifRight),
        _row(context, 'info-circle-outline', 'Fee', fee),
      ],
    ),
  );

  Widget _row(BuildContext context, String icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            BasilIcon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: callJourneyBody(13))),
            Text(
              value,
              style: callJourneyHeading(context, 15),
            ),
          ],
        ),
      );
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.icon, required this.child, this.badge});
  final String icon;
  final Widget child;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          BasilIcon(icon, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(child: child),
          if (badge != null) badge!,
        ],
      ),
    ),
  );
}

/// Pending: neither free nor funded yet. Grey, never the pink of money.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) => const CallBadge(
    key: ValueKey('money-pending'),
    label: 'Pending',
    color: AppColors.textMuted,
    icon: 'clock-outline',
  );
}
