/// The inline "SOL for fees" entry: after an Add funds delivery, in the Panta
/// trade review, and in both wallet sheets.
///
/// It asks the server once (`solTopUp.plan`) what this wallet's SOL covers.
/// [alwaysShow] false (trade review, after a delivery): it appears only when
/// the wallet can't pay for a new trade. True (wallet sheets): it always says
/// what the SOL covers, and offers the swap when that helps. When swaps are
/// switched off it shows [fallback] (the "send SOL yourself" path), so the
/// person is never sent to a dead end.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show callJourneyBody, callJourneyHeading;
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/sol_topup_models.dart';
import 'sol_topup_dependencies.dart';
import 'sol_topup_sheet.dart';

class SolTopUpPrompt extends StatefulWidget {
  const SolTopUpPrompt({
    super.key,
    this.wallet,
    this.alwaysShow = false,
    this.fallback,
    this.onToppedUp,
  });

  /// The wallet to top up; null lets the server pick the account's wallet.
  final String? wallet;
  final bool alwaysShow;

  /// Shown instead when swaps are unavailable (off, unconfigured, offline).
  final Widget? fallback;

  /// After SOL landed: callers re-read their balances.
  final VoidCallback? onToppedUp;

  @override
  State<SolTopUpPrompt> createState() => _SolTopUpPromptState();
}

class _SolTopUpPromptState extends State<SolTopUpPrompt> {
  SolTopUpDependencies? _deps;
  TopUpPlan? _plan;
  bool? _available;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _deps = SolTopUpDependencies.of(context);
    if (_deps == null) {
      _available = false;
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant SolTopUpPrompt old) {
    super.didUpdateWidget(old);
    if (old.wallet != widget.wallet && _deps != null) unawaited(_load());
  }

  Future<void> _load() async {
    final deps = _deps!;
    final revision = ++_revision;
    final status = await SolTopUpAvailability.read(deps);
    if (!mounted || revision != _revision) return;
    if (status == null || !status.available) {
      setState(() => _available = false);
      return;
    }
    final client = deps.createClient();
    try {
      final plan = await client.plan(wallet: widget.wallet);
      if (!mounted || revision != _revision) return;
      setState(() {
        _available = true;
        _plan = plan;
      });
    } on TopUpException {
      if (!mounted || revision != _revision) return;
      setState(() => _available = false);
    } finally {
      client.close();
    }
  }

  Future<void> _open() async {
    final landed = await showSolTopUpSheet(context, wallet: _plan?.wallet);
    if (!mounted || !landed) return;
    widget.onToppedUp?.call();
    // The RPC can trail a landed swap by a moment.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    if (_available == false) return widget.fallback ?? const SizedBox.shrink();
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    if (!widget.alwaysShow && !plan.needsSol) return const SizedBox.shrink();
    final canSwap = plan.blocker == null && plan.suggestion != null;
    final needs = plan.needsSol;
    final ink = needs ? AppColors.onWarningContainer : AppColors.textSecondary;
    final headline =
        needs
            ? 'Not enough SOL to trade yet'
            : plan.tradesCoveredNow == 1
            ? 'SOL for about 1 more new trade'
            : 'SOL for about ${plan.tradesCoveredNow} more new trades';
    final body =
        canSwap
            ? 'Swap \$${usdcLabel(plan.suggestion!.amountBaseUnits)} of your '
                'USDC for about ${solLabel(plan.suggestion!.estimatedLamports)} '
                'SOL. Jupiter pays the network fee, so it works with 0 SOL.'
            : plan.blocker == 'NEEDS_USDC'
            ? 'Trades pay their network fee in SOL. Add USDC first and you can '
                'swap a little of it for SOL here.'
            : 'Trades pay their network fee in SOL from this wallet.';
    return Semantics(
      container: true,
      liveRegion: needs,
      child: Container(
        key: const ValueKey('sol-topup-prompt'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: needs ? AppColors.warningContainer : const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                BasilIcon('lightning-outline', size: 18, color: ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headline,
                    style: callJourneyHeading(context, 14).copyWith(color: ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(body, style: callJourneyBody(12).copyWith(color: ink)),
            if (canSwap) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey('sol-topup-open'),
                  onPressed: _open,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const BasilIcon(
                    'exchange-outline',
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text('Get SOL for fees'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
