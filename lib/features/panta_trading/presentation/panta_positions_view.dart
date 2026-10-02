/// Profile → Positions: the person's real Panta positions, from the BFF.
///
/// Figures are exact (USDC base units and Panta's decimal prices); a figure
/// whose source is missing says so instead of showing zero. Claims run in the
/// app where the BFF and the wallet allow it; selling, and anything the app
/// cannot do, opens the market on panta.market.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/panta_lifecycle_models.dart';
import '../data/panta_trading_models.dart';
import '../panta_positions_controller.dart';
import 'panta_market_link.dart';

const _ink = Color(0xFF111827);
const _gain = Color(0xFF047857);
const _loss = Color(0xFFB42318);

class PantaPositionsView extends StatefulWidget {
  const PantaPositionsView({
    super.key,
    required this.controller,
    this.onOpenCall,
    this.opener = defaultPantaUrlOpener,
  });

  final PantaPositionsController controller;
  final void Function(String callId)? onOpenCall;
  final PantaUrlOpener opener;

  @override
  State<PantaPositionsView> createState() => _PantaPositionsViewState();
}

class _PantaPositionsViewState extends State<PantaPositionsView> {
  PantaPositionsController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    if (c.page == null && !c.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PantaPositionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final page = c.page;
    final error = c.error;
    if (page == null) {
      if (error != null) return _ErrorCard(error: error, onRetry: c.load);
      return const _LoadingCard();
    }
    final children = <Widget>[
      _SummaryCard(page: page, refreshing: c.loading, onRefresh: c.load),
      if (error != null) ...[
        const SizedBox(height: 10),
        _Notice(
          icon: 'info-circle-outline',
          text: '${error.message} Showing the last positions we loaded.',
        ),
      ],
      if (page.holdings == PantaHoldingsState.unavailable) ...[
        const SizedBox(height: 10),
        const _Notice(
          icon: 'clock-outline',
          text:
              'Panta did not report claim status just now. Prices and '
              'results are current; claim status refreshes shortly.',
        ),
      ],
    ];
    if (page.positions.isEmpty) {
      children.addAll([const SizedBox(height: 12), const _EmptyCard()]);
    } else {
      for (final p in page.positions) {
        children.addAll([
          const SizedBox(height: 12),
          _PositionCard(
            key: ValueKey('panta-position-${p.orderId}'),
            position: p,
            progress: c.claimProgress(p.orderId),
            onClaim: () => c.claim(p),
            onRetrySubmit: () => c.retryClaimSubmit(p.orderId),
            onOpenCall:
                widget.onOpenCall == null
                    ? null
                    : () => widget.onOpenCall!(p.callId),
            opener: widget.opener,
          ),
        ]);
      }
    }
    children.addAll([
      const SizedBox(height: 14),
      Text(
        'Selling happens on panta.market — Panta’s API has no in-app sell. '
        'Values are marked to Panta’s latest price and are not a quote. '
        '$pantaAttribution.',
        style: AppTextStyles.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

Widget _card({required Widget child, Color color = AppColors.surface}) =>
    Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.page,
    required this.refreshing,
    required this.onRefresh,
  });
  final PantaPositionsPage page;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final pnl = page.totalPnl;
    final pnlColor =
        pnl.isNegative
            ? const Color(0xFFFDA29B)
            : pnl > BigInt.zero
            ? const Color(0xFF6CE9A6)
            : Colors.white70;
    final open = page.positions.where((p) => !p.status.isSettled).length;
    return _card(
      color: _ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your Panta positions',
                  style: styles.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Refresh positions',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: refreshing ? null : onRefresh,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child:
                        refreshing
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            )
                            : const BasilIcon(
                              'refresh-outline',
                              size: 18,
                              color: Colors.white70,
                            ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _figure(
                'Value',
                page.counted == 0 ? '—' : PantaMoney.usdc(page.totalValue),
                Colors.white,
              ),
              _figure(
                'P&L',
                page.counted == 0 ? '—' : PantaMoney.usdc(pnl, signed: true),
                pnlColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            page.positions.isEmpty
                ? 'No funded calls yet.'
                : '${page.positions.length} position${page.positions.length == 1 ? '' : 's'}'
                    ' · $open still open'
                    '${page.counted == 0 ? '' : ' · cost ${PantaMoney.usdc(page.totalCost)}'}',
            style: styles.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    ],
  );
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    super.key,
    required this.position,
    required this.progress,
    required this.onClaim,
    required this.onRetrySubmit,
    required this.onOpenCall,
    required this.opener,
  });
  final PantaPosition position;
  final PantaClaimProgress progress;
  final VoidCallback onClaim;
  final VoidCallback onRetrySubmit;
  final VoidCallback? onOpenCall;
  final PantaUrlOpener opener;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final styles = AppTextStyles.textTheme;
    final pnl = p.pnlBaseUnits;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [SidePill(side: p.side), _StatusChip(status: p.status)],
          ),
          const SizedBox(height: 10),
          Text(
            p.question ?? 'Panta market',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.questionTitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 14),
          _FiguresRow(
            figures: [
              (
                'Cost',
                PantaMoney.usdc(p.costBaseUnits).replaceAll(' USDC', ''),
              ),
              (
                'Entry',
                p.entryPrice == null ? '—' : PantaMoney.price(p.entryPrice!),
              ),
              (
                p.status.isSettled ? 'Settles' : 'Now',
                p.currentPrice == null
                    ? (p.status == PantaPositionStatus.pending
                        ? 'Pending'
                        : '—')
                    : PantaMoney.price(p.currentPrice!),
              ),
              (
                'P&L',
                pnl == null
                    ? '—'
                    : PantaMoney.usdc(
                      pnl,
                      signed: true,
                    ).replaceAll(' USDC', ''),
              ),
            ],
            pnlColor:
                pnl == null || pnl == BigInt.zero
                    ? AppColors.textPrimary
                    : pnl.isNegative
                    ? _loss
                    : _gain,
          ),
          const SizedBox(height: 6),
          Text(
            _detailLine(p),
            style: styles.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (progress.message != null) ...[
            const SizedBox(height: 10),
            _Notice(icon: 'info-circle-outline', text: progress.message!),
          ],
          const SizedBox(height: 12),
          _actions(context),
        ],
      ),
    );
  }

  String _detailLine(PantaPosition p) {
    final shares =
        p.shares == null
            ? null
            : '${PantaMoney.shares(p.shares!)} shares (Panta quote)';
    return switch (p.status) {
      PantaPositionStatus.pending =>
        'Order sent · Chumbucket is confirming it on Solana and with Panta. '
            'Nothing is funded until that check passes.',
      PantaPositionStatus.failed =>
        'This order did not go through and nothing was funded. You can fund '
            'this call again.',
      PantaPositionStatus.awaitingResult =>
        '${shares ?? 'Shares unknown'} · market closed, waiting for Panta’s published result.',
      PantaPositionStatus.wonClaimable =>
        '${shares ?? 'Winning shares'} · Panta pays about 1 USDC per winning share.',
      PantaPositionStatus.won =>
        'You won. Panta has not opened the claim for this wallet yet.',
      PantaPositionStatus.claiming =>
        'Claim sent · confirming the payout on Solana.',
      PantaPositionStatus.claimed =>
        p.claim?.payoutBaseUnits == null
            ? 'Claimed on Panta.'
            : 'Claimed ${PantaMoney.usdc(p.claim!.payoutBaseUnits!)} to your wallet.',
      PantaPositionStatus.lost => 'This side lost. Losing shares settle at 0.',
      PantaPositionStatus.voided =>
        'Panta cancelled this market. Check Panta for how it settles.',
      PantaPositionStatus.open =>
        '${shares ?? 'Shares unknown'}'
            '${p.walletShares == null ? '' : ' · wallet holds ${PantaMoney.shares(p.walletShares!)} on this side'}',
    };
  }

  Widget _actions(BuildContext context) {
    final p = position;
    final buttons = <Widget>[];
    if (p.status == PantaPositionStatus.wonClaimable) {
      final label = switch (progress.phase) {
        PantaClaimPhase.preparing => 'Preparing claim…',
        PantaClaimPhase.approving => 'Approve in your wallet…',
        PantaClaimPhase.submitting => 'Sending claim…',
        _ => progress.canRetrySubmit ? 'Retry same claim' : 'Claim winnings',
      };
      buttons.add(
        FilledButton(
          key: ValueKey('panta-claim-${p.orderId}'),
          onPressed:
              progress.busy
                  ? null
                  : progress.canRetrySubmit
                  ? onRetrySubmit
                  : onClaim,
          style: FilledButton.styleFrom(
            backgroundColor: _gain,
            minimumSize: const Size(48, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(label),
        ),
      );
    }
    final pantaLabel = switch (p.status) {
      PantaPositionStatus.open ||
      PantaPositionStatus.awaitingResult => 'Sell on Panta',
      PantaPositionStatus.won ||
      PantaPositionStatus.wonClaimable => 'Claim on Panta',
      _ => 'View on Panta',
    };
    if (p.status != PantaPositionStatus.pending &&
        p.status != PantaPositionStatus.failed) {
      buttons.add(
        OutlinedButton.icon(
          key: ValueKey('panta-open-${p.orderId}'),
          onPressed:
              () => openPantaMarket(context, p.venueMarketId, opener: opener),
          icon: const BasilIcon(
            'share-box-outline',
            size: 16,
            color: AppColors.textPrimary,
          ),
          label: Text(pantaLabel),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            minimumSize: const Size(48, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }
    if (onOpenCall != null) {
      buttons.add(
        TextButton(
          onPressed: onOpenCall,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            minimumSize: const Size(48, 44),
          ),
          child: const Text('Open call'),
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}

class _FiguresRow extends StatelessWidget {
  const _FiguresRow({required this.figures, required this.pnlColor});
  final List<(String, String)> figures;
  final Color pnlColor;

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (var i = 0; i < figures.length; i++)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              figures[i].$1,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              figures[i].$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    i == figures.length - 1 ? pnlColor : AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four columns on a phone; two by two at large text or narrow width.
        final wide =
            constraints.maxWidth >= 300 &&
            MediaQuery.textScalerOf(context).scale(15) <= 20;
        if (wide) {
          return Row(
            children: [for (final cell in cells) Expanded(child: cell)],
          );
        }
        return Wrap(
          runSpacing: 10,
          children: [
            for (final cell in cells)
              SizedBox(width: constraints.maxWidth / 2, child: cell),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final PantaPositionStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, emphasised) = switch (status) {
      PantaPositionStatus.pending => (
        AppColors.onWarningContainer,
        'clock-outline',
        false,
      ),
      PantaPositionStatus.failed => (_loss, 'cross-outline', false),
      PantaPositionStatus.open => (
        AppColors.challengeActive,
        'chart-pie-outline',
        false,
      ),
      PantaPositionStatus.awaitingResult => (
        AppColors.onWarningContainer,
        'clock-outline',
        false,
      ),
      PantaPositionStatus.wonClaimable => (_gain, 'award-outline', true),
      PantaPositionStatus.won => (_gain, 'award-outline', false),
      PantaPositionStatus.claiming => (_gain, 'clock-outline', false),
      PantaPositionStatus.claimed => (_gain, 'check-outline', false),
      PantaPositionStatus.lost => (
        AppColors.textSecondary,
        'cross-outline',
        false,
      ),
      PantaPositionStatus.voided => (
        AppColors.textTertiary,
        'info-circle-outline',
        false,
      ),
    };
    return CallBadge(
      label: status.label,
      color: color,
      icon: icon,
      emphasised: emphasised,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.warningContainer.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BasilIcon(icon, size: 16, color: AppColors.onWarningContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.onWarningContainer,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => _card(
    child: Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Loading your Panta positions…',
            style: AppTextStyles.textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();
  @override
  Widget build(BuildContext context) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BasilIcon('wallet-outline', color: AppColors.textPrimary),
        const SizedBox(height: 10),
        Text(
          'No funded positions yet',
          style: AppTextStyles.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Calls are free. Open one of your own calls on a Panta market and '
          'fund it to put real USDC behind it — it shows up here once Panta '
          'and Solana confirm the fill.',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});
  final PantaException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final unavailable = error.code == PantaErrorCode.unavailable;
    final signedOut = error.code == PantaErrorCode.signedOut;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BasilIcon(
            signedOut ? 'login-outline' : 'lock-outline',
            color: AppColors.textPrimary,
          ),
          const SizedBox(height: 10),
          Text(
            signedOut
                ? 'Sign in to see your positions'
                : unavailable
                ? 'Positions are not available yet'
                : 'Couldn’t load your positions',
            style: AppTextStyles.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            unavailable
                ? 'Funded positions are not switched on for this server yet. '
                    'Your calls are unaffected.'
                : error.message,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (!signedOut) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
