import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show callJourneyBody, callJourneyHeading;
import 'package:chumbucket/features/panta_trading/data/panta_trading_models.dart';
import 'package:chumbucket/features/panta_trading/panta_trade_controller.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_prompt.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/deposits_client.dart';
import '../data/deposits_models.dart';
import 'add_funds_sheet.dart';
import 'deposits_dependencies.dart';

/// Below the amount in the Panta trade review: the trading wallet's real
/// USDC and SOL, read by the server from mainnet; when the buy is bigger than
/// the USDC there, a way to add funds without leaving the trade; and when the
/// wallet's SOL can't pay for the trade, "Get SOL for fees" (a gasless swap
/// of a little of its own USDC), or — where swaps are off — how to send SOL.
///
/// Says nothing at all when it can't read a balance: a guessed "you have
/// enough" is worse than silence. Never blocks the trade; the venue's own
/// checks still apply.
class TradeFundsCheck extends StatefulWidget {
  const TradeFundsCheck({super.key, required this.controller});
  final PantaTradeController controller;

  @override
  State<TradeFundsCheck> createState() => _TradeFundsCheckState();
}

class _TradeFundsCheckState extends State<TradeFundsCheck> {
  DepositsClient? _client;
  WalletBalance? _balance;
  int _revision = 0;

  PantaTradeController get trade => widget.controller;

  @override
  void initState() {
    super.initState();
    trade.addListener(_changed);
    final deps = DepositsDependencies.of(context);
    if (deps != null) {
      try {
        _client = deps.createClient();
      } catch (_) {
        _client = null;
      }
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    trade.removeListener(_changed);
    _client?.close();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _read() async {
    final client = _client;
    if (client == null) return;
    final revision = ++_revision;
    try {
      final read = await client.balance(wallet: trade.wallet);
      if (!mounted || revision != _revision || read.wallet != trade.wallet) {
        return;
      }
      setState(() => _balance = read);
    } on DepositsException {
      /* Silence over a guess. */
    }
  }

  /// The buy's size: the reviewed quote's when there is one, else what's typed.
  BigInt? get _amount {
    final reviewed = trade.prepared?.order.amountBaseUnits;
    if (reviewed != null) return BigInt.tryParse(reviewed);
    try {
      return BigInt.parse(PantaUsdcAmount.parse(trade.amountText).baseUnits);
    } on PantaException {
      return null;
    }
  }

  Future<void> _addFunds(BigInt? need) async {
    await showAddFundsSheet(
      context,
      requiredUsdcBaseUnits: need,
      fundWallet: trade.wallet,
    );
    if (mounted) await _read();
  }

  @override
  Widget build(BuildContext context) {
    final b = _balance;
    final visible = switch (trade.phase) {
      PantaTradePhase.amount ||
      PantaTradePhase.preparing ||
      PantaTradePhase.review => true,
      _ => false,
    };
    if (b == null || !visible) return const SizedBox.shrink();
    final amount = _amount;
    final short =
        amount != null && amount > b.usdcBaseUnits
            ? amount - b.usdcBaseUnits
            : null;
    final noSol = b.hasNoSol;
    final warn = short != null;
    final ink = warn ? AppColors.onWarningContainer : AppColors.textSecondary;
    final balance = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        container: true,
        liveRegion: warn,
        child: Container(
          key: const ValueKey('trade-funds-check'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: warn ? AppColors.warningContainer : const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BasilIcon('wallet-outline', size: 18, color: ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'In your wallet: ${b.usdcLabel} USDC · ${b.solLabel} SOL',
                      key: const ValueKey('trade-funds-balance'),
                      style: callJourneyBody(13).copyWith(color: ink),
                    ),
                  ),
                ],
              ),
              if (short != null) ...[
                const SizedBox(height: 6),
                Text(
                  'This buy is ${formatBaseUnits(amount!, usdcDecimals)} USDC, '
                  '${formatBaseUnits(short, usdcDecimals)} more than you have.',
                  key: const ValueKey('trade-funds-short'),
                  style: callJourneyHeading(context, 14).copyWith(color: ink),
                ),
              ],
              if (warn) ...[
                const SizedBox(height: 8),
                _button(
                  'trade-add-funds',
                  'Add funds',
                  () => _addFunds(amount),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        balance,
        // The server's own count of what this wallet's SOL pays for. With
        // swaps switched off, the old honest path: send SOL in.
        SolTopUpPrompt(
          key: ValueKey('trade-sol-topup-${trade.wallet}'),
          wallet: trade.wallet,
          onToppedUp: _read,
          fallback: noSol ? _noSol() : null,
        ),
      ],
    );
  }

  Widget _noSol() => Container(
    key: const ValueKey('trade-funds-no-sol'),
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Network fees are paid in SOL, and this wallet has none. '
          'Send a little SOL to it before you trade.',
          style: callJourneyBody(
            12,
          ).copyWith(color: AppColors.onWarningContainer),
        ),
        const SizedBox(height: 8),
        // A card buys USDC only: the sheet leads with this wallet's address.
        _button('trade-add-sol', 'Add SOL', () => _addFunds(_amount)),
      ],
    ),
  );

  Widget _button(String key, String label, VoidCallback onPressed) => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      key: ValueKey(key),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        backgroundColor: AppColors.textPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const BasilIcon('add-outline', size: 18, color: Colors.white),
      label: Text(label),
    ),
  );
}
