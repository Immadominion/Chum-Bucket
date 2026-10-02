/// Exact market evidence, followed by separate free-call and trade controls.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/panta_trading/presentation/panta_market_link.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class MarketDetailScreen extends StatefulWidget {
  final String marketId;
  final VoidCallback? onSignInRequested;

  const MarketDetailScreen({
    super.key,
    required this.marketId,
    this.onSignInRequested,
  });

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CallsProvider>().loadMarketDetail(widget.marketId);
      }
    });
  }

  Future<void> _refresh() => context.read<CallsProvider>().loadMarketDetail(
    widget.marketId,
    force: true,
  );

  Future<void> _compose(MarketDetail detail) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final entry = await showCallComposer(
      context: context,
      market: detail.market,
      snapshot: detail.snapshot,
      sharePrice: detail.sharePrice,
    );
    if (entry != null && mounted) {
      await _openCall(entry.call.id);
      if (mounted) {
        await provider.loadMarketDetail(widget.marketId, force: true);
      }
    }
  }

  Future<void> _openCall(String callId) => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => CallDetailScreen(callId: callId)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
      title: Text('Market', style: AppTextStyles.textTheme.titleLarge),
      leading: IconButton(
        tooltip: 'Back',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const BasilIcon(
          'arrow-left-outline',
          color: AppColors.textPrimary,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh market',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: _refresh,
          icon: const BasilIcon(
            'refresh-outline',
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
    body: Consumer<CallsProvider>(
      builder: (context, provider, _) {
        final detail = provider.marketDetail(widget.marketId);
        if (detail == null) {
          if (provider.isLoadingMarket(widget.marketId)) {
            return const CallsLoadingView(rows: 2);
          }
          return SingleChildScrollView(
            child:
                provider.isOffline
                    ? CallsOfflineView(onRetry: _refresh)
                    : CallsErrorView(
                      message:
                          provider.marketError(widget.marketId) ??
                          'We couldn’t load this market.',
                      onRetry: _refresh,
                    ),
          );
        }
        return _body(provider, detail);
      },
    ),
  );

  Widget _body(CallsProvider provider, MarketDetail detail) {
    final market = detail.market;
    final now = DateTime.now().toUtc();
    final closedByTime =
        market.closesAtUtc != null && !market.closesAtUtc!.isAfter(now);
    // M14: the server closes calls a window before the market closes.
    final callsCloseAt = detail.callsCloseAtUtc;
    final insideCutoff =
        !closedByTime && callsCloseAt != null && !callsCloseAt.isAfter(now);
    final acceptsCalls =
        market.status.acceptsNewCalls &&
        !closedByTime &&
        !insideCutoff &&
        (market.opensAt == null ||
            market.opensAt! <= now.millisecondsSinceEpoch);
    final ownCall = detail.viewerCall;
    final isOwnCall =
        ownCall != null && ownCall.call.userId == provider.viewerUserId;
    final canTrade = market.venue == MarketVenue.panta && isOwnCall;
    final status =
        closedByTime && market.status == MarketStatus.open
            ? 'Closed · awaiting result'
            : market.status.label;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (provider.isOffline || detail.fromCache)
                  _notice(
                    'Showing cached market data. Refresh to check the venue.',
                  ),
                if (provider.marketError(widget.marketId) != null)
                  _notice(provider.marketError(widget.marketId)!),
                if (market.venue.isDemo)
                  _notice(
                    'DEMO DATA · Sample market, not a live venue or trade.',
                  ),
                _surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The prototype's head: the market's mark, its category,
                      // and where it stands. The venue is named with its
                      // prices below.
                      Row(
                        children: [
                          MarketGlyph(market: market),
                          const SizedBox(width: 10),
                          // Category left, state right; at large text or on
                          // a narrow phone the pills drop below, never clip.
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Text(
                                  market.category.toUpperCase(),
                                  style: AppTextStyles.textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                        letterSpacing: .6,
                                      ),
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (market.venue.isDemo)
                                      _tag('Demo catalog'),
                                    _statusPill(
                                      status,
                                      tone:
                                          acceptsCalls
                                              ? _StatusTone.open
                                              : market.status ==
                                                      MarketStatus.resolved ||
                                                  market.status ==
                                                      MarketStatus.cancelled
                                              ? _StatusTone.settled
                                              : _StatusTone.waiting,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        market.question,
                        style: AppTextStyles.textTheme.headlineSmall?.copyWith(
                          height: 1.24,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        market.closesAtUtc == null
                            ? 'Close time unavailable'
                            : 'Closes ${CallsFormat.timestampUtc(market.closesAtUtc!)}',
                        style: AppTextStyles.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (_callWindowLine(detail, now) case final line?) ...[
                        const SizedBox(height: 4),
                        Text(
                          line,
                          key: const ValueKey('market-call-window'),
                          style: AppTextStyles.textTheme.bodySmall?.copyWith(
                            color:
                                insideCutoff
                                    ? AppColors.onWarningContainer
                                    : AppColors.textSecondary,
                            fontWeight:
                                insideCutoff
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (market.venue == MarketVenue.panta)
                        MarketSharePrices(
                          snapshot:
                              detail.sharePrice?.marketId == market.id
                                  ? detail.sharePrice
                                  : null,
                          expanded: true,
                        )
                      else if (market.venue.isDemo &&
                          detail.snapshot != null) ...[
                        Text(
                          'Demo probability snapshot',
                          style: AppTextStyles.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'YES ${CallsFormat.probability(detail.snapshot!.yesProbability)} · NO ${CallsFormat.probability(detail.snapshot!.noProbability)}',
                          style: AppTextStyles.textTheme.bodyMedium,
                        ),
                        Text(
                          '${CallsFormat.dataAge(detail.snapshot!.ageAt(now))} · demo source',
                          style: AppTextStyles.textTheme.bodySmall,
                        ),
                        if (provider.isSnapshotStale(market.id))
                          Text(
                            'Stale',
                            style: AppTextStyles.textTheme.bodySmall?.copyWith(
                              color: AppColors.onWarningContainer,
                            ),
                          ),
                      ] else
                        Text(
                          'Price unavailable',
                          style: AppTextStyles.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _RulesBlock(market: market),
                const SizedBox(height: 14),
                if (isOwnCall) ...[
                  Text('Your call', style: AppTextStyles.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  CallCard(
                    entry: ownCall,
                    showAuthor: false,
                    onOpenCall: () => _openCall(ownCall.call.id),
                  ),
                  const SizedBox(height: 14),
                ],
                if (isOwnCall && detail.crowdSplit != null)
                  _CrowdBlock(split: detail.crowdSplit!, market: market)
                else if (!isOwnCall)
                  const _LockNote(
                    'Make your call first. The community split unlocks afterwards.',
                  ),
                const SizedBox(height: 14),
                _FactsBlock(market: market),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final call = _callAction(
                      label: isOwnCall ? 'View your call' : 'Make a call',
                      onPressed:
                          isOwnCall
                              ? () => _openCall(ownCall.call.id)
                              : acceptsCalls
                              ? () => _compose(detail)
                              : null,
                    );
                    final trade = OutlinedButton(
                      // The existing native flow is bound to a user's call ID.
                      // Reuse that route; never create a call on a trade tap or
                      // duplicate the wallet/controller lifetime here.
                      onPressed:
                          canTrade ? () => _openCall(ownCall.call.id) : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.all(14),
                        foregroundColor: AppColors.textPrimary,
                        textStyle: AppTextStyles.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Trade'),
                    );
                    return MediaQuery.textScalerOf(context).scale(14) > 21
                        ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [call, const SizedBox(height: 8), trade],
                        )
                        : Row(
                          children: [
                            Expanded(child: call),
                            const SizedBox(width: 8),
                            Expanded(child: trade),
                          ],
                        );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  canTrade
                      ? 'Calling is free. Open your call to review a separate Panta trade.'
                      : market.venue.isDemo
                      ? 'Demo market. Trading is unavailable.'
                      : market.venue != MarketVenue.panta
                      ? 'Trading is available only through Panta.'
                      : 'Calling is free. Trading currently requires your own existing call.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (!acceptsCalls && !isOwnCall)
                  Text(
                    insideCutoff
                        ? 'Calls are closed: they close '
                            '${((detail.callCutoffMs ?? 0) / 60000).round()} min '
                            'before the market does.'
                        : status,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.textTheme.bodySmall?.copyWith(
                      color: AppColors.onWarningContainer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // The shared call to action: white label on the vertical gradient.
  Widget _callAction({required String label, VoidCallback? onPressed}) =>
      ChumbucketPrimaryButton(label: label, onPressed: onPressed);
}

/// "Calls close 14:30 UTC · 30 min before the market closes" (M14), or null
/// when the server did not publish a window.
String? _callWindowLine(MarketDetail detail, DateTime now) {
  final closeAt = detail.callsCloseAtUtc;
  final cutoff = detail.callCutoffMs;
  if (closeAt == null || cutoff == null || cutoff <= 0) return null;
  final minutes = (cutoff / 60000).round();
  if (!closeAt.isAfter(now)) {
    return 'Calls closed $minutes min before the market closes.';
  }
  return 'Calls close ${CallsFormat.timestampUtc(closeAt)} · '
      '$minutes min before the market closes';
}

Widget _surface({required Widget child}) => SizedBox(
  width: double.infinity,
  child: Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

Widget _tag(String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: AppColors.primaryContainer,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    label,
    style: AppTextStyles.textTheme.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: AppColors.onPrimaryContainer,
    ),
  ),
);

enum _StatusTone { open, waiting, settled }

/// Open in the prototype's green; closed-awaiting or paused in amber; a
/// resolved or cancelled market neutral. Only an open market is ever green.
Widget _statusPill(String label, {required _StatusTone tone}) {
  final (fill, ink) = switch (tone) {
    _StatusTone.open => (const Color(0xFFE6F6EF), const Color(0xFF07644C)),
    _StatusTone.waiting => (const Color(0xFFFFF3D8), const Color(0xFF78350F)),
    _StatusTone.settled => (const Color(0xFFEEF0F4), const Color(0xFF334155)),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'PPNeueMachina',
        fontSize: 12,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: ink,
      ),
    ),
  );
}

/// A rule of the screen rather than an alert: the prototype's grey note.
class _LockNote extends StatelessWidget {
  const _LockNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFECEFF2),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: BasilIcon('lock-outline', size: 17, color: Color(0xFF525D6E)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF525D6E),
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _notice(String message) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: AppTextStyles.textTheme.bodySmall?.copyWith(
        color: AppColors.onPrimaryContainer,
        height: 1.5,
      ),
    ),
  ),
);

class _RulesBlock extends StatelessWidget {
  const _RulesBlock({required this.market});
  final VenueMarket market;

  @override
  Widget build(BuildContext context) => _surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What decides this?',
          style: AppTextStyles.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        // No rule-summary field exists. Do not invent a settlement interpretation.
        Text(
          'The venue’s exact rules and published result determine settlement. Closing time alone does not settle a call.',
          style: AppTextStyles.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            trailing: const BasilIcon(
              'caret-down-outline',
              color: AppColors.textPrimary,
            ),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: Text(
              'Read the full market rules',
              style: AppTextStyles.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  market.rulesText,
                  style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
                ),
              ),
              // Panta's public market page; never its authenticated API URL.
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child:
                    market.venue == MarketVenue.panta &&
                            market.venueMarketId.isNotEmpty
                        ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Resolved by ',
                              style: AppTextStyles.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            PantaMarketLink(
                              venueMarketId: market.venueMarketId,
                              style: AppTextStyles.textTheme.bodySmall,
                            ),
                          ],
                        )
                        : Text(
                          'Resolution source: ${market.resolutionSource ?? 'Not published'}',
                          style: AppTextStyles.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
              ),
            ],
          ),
        ),
        Text(
          market.venue.isDemo
              ? 'Resolution: sample data, never a live result.'
              : 'Resolution: ${market.venue.label}’s published result.',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _FactsBlock extends StatelessWidget {
  const _FactsBlock({required this.market});
  final VenueMarket market;

  @override
  Widget build(BuildContext context) {
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 12),
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
          Text(value, style: AppTextStyles.textTheme.bodyMedium),
        ],
      ),
    );
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Market evidence',
            style: AppTextStyles.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          fact('Venue', market.venue.label),
          fact('Venue status', market.rawStatus),
          fact(
            'Resolution time (venue)',
            market.resolvesAt == null
                ? 'Not published'
                : CallsFormat.timestampUtc(
                  DateTime.fromMillisecondsSinceEpoch(
                    market.resolvesAt!,
                    isUtc: true,
                  ),
                ),
          ),
          fact('Last synced', CallsFormat.timestampUtc(market.lastSyncedAtUtc)),
          if (market.venue == MarketVenue.panta &&
              market.venueMarketId.isNotEmpty) ...[
            const SizedBox(height: 8),
            PantaMarketLink(
              venueMarketId: market.venueMarketId,
              label: 'Open this market on Panta',
              style: AppTextStyles.textTheme.bodySmall,
            ),
          ],
          // Raw identifiers, for anyone checking, behind a disclosure.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('market-record-ids'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              trailing: const BasilIcon(
                'caret-down-outline',
                color: AppColors.textPrimary,
              ),
              title: Text(
                'Market IDs',
                style: AppTextStyles.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              children: [
                fact('Venue market ID', market.venueMarketId),
                fact('Chumbucket market ID', market.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CrowdBlock extends StatelessWidget {
  const _CrowdBlock({required this.split, required this.market});
  final CrowdSplit split;
  final VenueMarket market;

  @override
  Widget build(BuildContext context) => _surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Community opinion',
          style: AppTextStyles.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${split.total} calls returned for this market · not venue odds',
          style: AppTextStyles.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              '${market.labelFor(Side.yes)} · ${split.yesCalls}',
              style: AppTextStyles.textTheme.bodyMedium,
            ),
            Text(
              '${market.labelFor(Side.no)} · ${split.noCalls}',
              style: AppTextStyles.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    ),
  );
}
