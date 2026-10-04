/// The owner's order on their own call, refreshed on its own while it is
/// still being confirmed.
///
/// It reads the private ledger through `pantaTrading.callOrder`, which never
/// asks Panta, so polling is cheap and safe; the server reconciler does the
/// actual verification. "Check now" asks the server to verify immediately.
/// Only a server FILLED reads "Funded". Nothing here is shared publicly.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/panta_lifecycle_models.dart';
import '../data/panta_trading_client.dart';
import '../data/panta_trading_models.dart';
import 'panta_market_link.dart';

class PantaOrderStatusRow extends StatefulWidget {
  const PantaOrderStatusRow({
    super.key,
    required this.callId,
    required this.client,
    this.pollEvery = const Duration(seconds: 8),
    this.slowPollEvery = const Duration(seconds: 30),
    this.slowAfter = const Duration(minutes: 5),
    this.opener = defaultPantaUrlOpener,
    this.now = DateTime.now,
  });

  final String callId;
  final PantaTradingClient client;
  final Duration pollEvery;
  final Duration slowPollEvery;

  /// After this long pending, poll less often (the reconciler keeps checking).
  final Duration slowAfter;
  final PantaUrlOpener opener;
  final DateTime Function() now;

  @override
  State<PantaOrderStatusRow> createState() => _PantaOrderStatusRowState();
}

class _PantaOrderStatusRowState extends State<PantaOrderStatusRow> {
  PantaVenueOrder? _order;
  bool _checking = false;
  DateTime? _checkedAt;
  DateTime? _pendingSince;
  Timer? _timer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PantaOrderStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.callId != widget.callId ||
        oldWidget.client != widget.client) {
      _order = null;
      _load();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    try {
      final session = await widget.client.currentSession();
      if (session == null) return;
      final order = await widget.client.callOrder(
        callId: widget.callId,
        accountId: session.accountId,
      );
      if (_disposed) return;
      setState(() {
        _order = order;
        _checkedAt = widget.now();
        if (order?.fundingState == PantaFundingState.submitted) {
          _pendingSince ??= widget.now();
        } else {
          _pendingSince = null;
        }
      });
    } catch (_) {
      // A missed refresh keeps the last state; the next tick tries again.
    } finally {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || _order?.fundingState != PantaFundingState.submitted) {
      return;
    }
    final since = _pendingSince ?? widget.now();
    final slow = widget.now().difference(since) >= widget.slowAfter;
    _timer = Timer(slow ? widget.slowPollEvery : widget.pollEvery, _load);
  }

  /// Asks the server to verify this order with Panta and Solana now.
  Future<void> _checkNow() async {
    final order = _order;
    if (order == null || _checking) return;
    setState(() => _checking = true);
    try {
      final session = await widget.client.currentSession();
      if (session != null) {
        await widget.client.order(
          orderId: order.orderId,
          accountId: session.accountId,
        );
      }
    } catch (_) {
      // The reconciler keeps checking either way.
    } finally {
      if (!_disposed) setState(() => _checking = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    if (order == null) return const SizedBox.shrink();
    final amount = PantaMoney.dollars(BigInt.parse(order.amountBaseUnits));
    final styles = AppTextStyles.textTheme;
    final (fill, ink, icon, title, body) = switch (order.fundingState) {
      PantaFundingState.filled => (
        AppColors.successContainer,
        AppColors.onSuccessContainer,
        'check-outline',
        'Funded · $amount on ${order.side.wire}',
        'Panta and Solana confirmed this buy. It is in your Positions.',
      ),
      PantaFundingState.failed => (
        AppColors.errorContainer,
        AppColors.onErrorContainer,
        'cross-outline',
        'Order didn’t go through',
        'Nothing was funded. You can review a new trade for this call.',
      ),
      _ => (
        AppColors.warningContainer,
        AppColors.onWarningContainer,
        'clock-outline',
        'Order submitted · $amount on ${order.side.wire}',
        'Confirming with Panta and Solana. This updates on its own; it is '
            'not funded until confirmed.',
      ),
    };
    final pending = order.fundingState == PantaFundingState.submitted;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey('panta-order-${order.fundingState.wire}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (pending)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink,
                    ),
                  )
                else
                  BasilIcon(icon, size: 16, color: ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: styles.titleSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: styles.bodySmall?.copyWith(color: ink, height: 1.45),
            ),
            if (pending || order.fundingState == PantaFundingState.filled) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (pending)
                    TextButton(
                      onPressed: _checking ? null : _checkNow,
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        minimumSize: const Size(48, 40),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(_checking ? 'Checking…' : 'Check now'),
                    ),
                  if (_checkedAt != null && pending)
                    Text(
                      'Last checked ${_clock(_checkedAt!)}',
                      style: styles.bodySmall?.copyWith(color: ink),
                    ),
                  if (order.fundingState == PantaFundingState.filled)
                    PantaMarketLink(
                      venueMarketId: order.venueMarketId,
                      label: 'View on Panta',
                      opener: widget.opener,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _clock(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
