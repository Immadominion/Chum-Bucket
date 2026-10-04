/// `Collect $9.20`, on Home and on the call that won. One tap per collect;
/// never signed without the person.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show callJourneyBody, callJourneyHeading;
import 'package:chumbucket/features/panta_trading/panta_trading.dart'
    show PantaTradingClient;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_models.dart';
import '../money_controller.dart';
import '../money_winnings_controller.dart';
import 'money_amount_row.dart' show moneyOf;
import 'money_dependencies.dart';

class MoneyWinningsCard extends StatefulWidget {
  const MoneyWinningsCard({super.key, this.callId});

  /// On a call: only that call's winnings. Home: all of them.
  final String? callId;

  @override
  State<MoneyWinningsCard> createState() => _MoneyWinningsCardState();
}

class _MoneyWinningsCardState extends State<MoneyWinningsCard> {
  PantaTradingClient? _client;
  MoneyWinningsController? _controller;
  MoneyController? _money;

  MoneyWinningsController? _ensure() {
    if (_controller != null) return _controller;
    final deps = MoneyDependencies.of(context);
    if (deps == null) return null;
    _client = deps.createTradingClient();
    _controller = MoneyWinningsController(
      client: _client!,
      signerFor: deps.claimSigners,
      pollEvery: deps.pollEvery,
      onCollected: () => unawaited(_money?.refresh()),
    )..addListener(_changed);
    return _controller;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_changed)
      ..dispose();
    _client?.close();
    super.dispose();
  }

  List<MoneyWinning> _items(MoneyController money) {
    final callId = widget.callId;
    final all = money.winnings.items;
    return callId == null
        ? all
        : [
          for (final item in all)
            if (item.callId == callId) item,
        ];
  }

  Future<void> _collect(List<MoneyWinning> items) async {
    final controller = _ensure();
    if (controller == null) return;
    for (final item in items) {
      if (!mounted) return;
      await controller.collect(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = _money = moneyOf(context);
    if (money == null) return const SizedBox.shrink();
    final items = _items(money);
    if (items.isEmpty) return const SizedBox.shrink();
    final controller = _controller;
    final progress = [
      for (final item in items)
        controller?.progress(item.orderId) ?? const MoneyCollectProgress(),
    ];
    final busy = progress.any((p) => p.busy);
    final collecting = progress.any(
      (p) =>
          p.step == MoneyCollectStep.collecting ||
          p.step == MoneyCollectStep.done,
    );
    final open = [
      for (var i = 0; i < items.length; i++)
        if (!items[i].collecting &&
            progress[i].step != MoneyCollectStep.collecting &&
            progress[i].step != MoneyCollectStep.done)
          items[i],
    ];
    final total = open.fold<BigInt>(
      BigInt.zero,
      (sum, item) => sum + item.amountBaseUnits,
    );
    final message = progress
        .map((p) => p.message)
        .whereType<String>()
        .firstOrNull;
    return Container(
      key: const ValueKey('money-winnings-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const BasilIcon(
                  'award-outline',
                  size: 22,
                  color: AppColors.pinkInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  items.length == 1
                      ? (items.single.question ?? 'You called it')
                      : 'You called it',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: callJourneyHeading(context, 14),
                ),
              ),
              if (collecting && open.isEmpty)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message, style: callJourneyBody(12)),
          ],
          if (open.isNotEmpty) ...[
            const SizedBox(height: 12),
            ChumbucketPrimaryButton(
              key: const ValueKey('money-collect'),
              label: 'Collect ${moneyDollars(total)}',
              busy: busy,
              busyLabel: 'Collecting…',
              onPressed: busy ? null : () => unawaited(_collect(open)),
            ),
          ],
        ],
      ),
    );
  }
}
