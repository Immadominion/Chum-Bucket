/// One market: the question, its time facts as icon rows, the venue's two
/// prices, then the free call. Rules and evidence wait behind one disclosure.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart'
    show CallsLoadingView;
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_state_view.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/market_creation/presentation/widgets/market_entry_widgets.dart';
import 'package:chumbucket/features/money/money_controller.dart';
import 'package:chumbucket/features/money/presentation/money_amount_row.dart';
import 'package:chumbucket/features/panta_trading/presentation/panta_market_link.dart';
import 'package:chumbucket/features/panta_trading/presentation/panta_mark.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class MarketDetailScreen extends StatefulWidget {
  final String marketId;
  final VoidCallback? onSignInRequested;

  const MarketDetailScreen({
    super.key,
    required this.marketId,
    this.onSignInRequested,
  });

  /// How often an open detail checks whether its price is due a re-read.
  static const tick = Duration(seconds: 30);

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen>
    with WidgetsBindingObserver {
  Timer? _ticker;
  bool _started = false;

  /// The amount for "Make a call", carried into the composer.
  MoneyAmount? _amount;
  bool _foreground = true;
  bool _current = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CallsProvider>();
      _started = true;
      // A market already loaded shows at once and is re-read behind it, so
      // the viewer's own call and the crowd split are current too.
      provider.loadMarketDetail(
        widget.marketId,
        force: provider.marketDetail(widget.marketId) != null,
      );
    });
    _ticker = Timer.periodic(MarketDetailScreen.tick, (_) => _keepCurrent());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _keepCurrent();
  }

  /// Silent: the price on screen stays until a newer one lands.
  void _keepCurrent() {
    if (!mounted || !_foreground || !_current) return;
    context.read<CallsProvider>().refreshPriceIfStale(widget.marketId);
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
      // This screen has no refresh button: a price that lapsed is read again
      // by Lock itself, once, rather than asking the person to refresh a
      // screen that offers no way to.
      refreshPrice: () => _freshPrice(provider),
      initialAmount: _amount,
    );
    // Back to the amount last used (the composer remembers it).
    if (mounted) setState(() => _amount = null);
    if (entry != null && mounted) {
      await _openCall(entry.call.id);
      if (mounted) {
        await provider.loadMarketDetail(widget.marketId, force: true);
      }
    }
  }

  /// Money on, a market that can be traded and is taking calls.
  MoneyController? _moneyFor(VenueMarket market, bool acceptsCalls) =>
      market.tradable && acceptsCalls ? moneyOf(context) : null;

  Future<SharePriceSnapshot?> _freshPrice(CallsProvider provider) async {
    final detail = await provider.loadMarketDetail(
      widget.marketId,
      force: true,
    );
    // A read superseded by another returns null; the cache then holds the
    // newest price either way.
    final price =
        (detail ?? provider.marketDetail(widget.marketId))?.sharePrice;
    return price?.marketId == widget.marketId ? price : null;
  }

  Future<void> _openCall(String callId) => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => CallDetailScreen(callId: callId)),
  );

  @override
  Widget build(BuildContext context) {
    _current = ModalRoute.of(context)?.isCurrent ?? true;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
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
      ),
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          final detail = provider.marketDetail(widget.marketId);
          if (detail == null) {
            if (!_started || provider.isLoadingMarket(widget.marketId)) {
              return const CallsLoadingView(rows: 2);
            }
            return MarketStateView(
              artwork:
                  provider.isOffline
                      ? ChumbucketStateArtwork.offline
                      : ChumbucketStateArtwork.error,
              line:
                  provider.isOffline
                      ? 'You\'re offline'
                      : 'This market didn\'t load',
              actionLabel: 'Try again',
              onAction: _refresh,
            );
          }
          return _body(provider, detail);
        },
      ),
    );
  }

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
    // A SOL-quoted Panta market takes calls but is never offered a trade:
    // no Trade button at all, not a disabled one, even beside your own call.
    final canTrade = market.tradable && isOwnCall;
    final status =
        closedByTime && market.status == MarketStatus.open
            ? 'Closed · awaiting result'
            : market.status.label;
    final close = market.closesAtUtc;
    final window = _callWindow(detail, now);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The market's mark, its category, and where it stands.
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
                                  marketCategoryLabel(market.category),
                                  style: GoogleFonts.montserrat(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
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
                      // Time facts as icon rows: when the market closes, and
                      // when it stops taking calls.
                      _Fact(
                        icon: 'clock-outline',
                        text:
                            close == null
                                ? 'No close time published'
                                : closedByTime
                                ? 'Closed ${CallsFormat.timestampShortUtc(close)}'
                                : 'Closes ${CallsFormat.timestampShortUtc(close)}'
                                    ' · ${marketTimeLeft(close, now: now)}',
                      ),
                      if (window != null)
                        _Fact(
                          key: const ValueKey('market-call-window'),
                          icon: 'lock-time-outline',
                          text: window,
                          warn: insideCutoff,
                        ),
                      // People-first: a market someone proposed here says who.
                      if (market.venue == MarketVenue.panta)
                        MarketProposerLine(
                          venueMarketId: market.venueMarketId,
                          onOpenPerson:
                              (proposer) => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder:
                                      (_) => CallPersonScreen(
                                        personRef: proposer.id,
                                        onSignInRequested:
                                            widget.onSignInRequested,
                                      ),
                                ),
                              ),
                        ),
                      const SizedBox(height: 14),
                      if (market.venue == MarketVenue.panta)
                        MarketSharePrices(
                          snapshot:
                              detail.sharePrice?.marketId == market.id
                                  ? detail.sharePrice
                                  : null,
                          expanded: true,
                        )
                      else if (market.venue.isDemo && detail.snapshot != null)
                        _DemoPrices(snapshot: detail.snapshot!)
                      else
                        Text(
                          'Price unavailable',
                          style: AppTextStyles.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
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
                if (isOwnCall && detail.crowdSplit != null) ...[
                  _CrowdBlock(split: detail.crowdSplit!, market: market),
                  const SizedBox(height: 14),
                ] else if (!isOwnCall) ...[
                  const _LockNote('Call it to see how others called'),
                  const SizedBox(height: 14),
                ],
                _DetailsBlock(market: market),
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
                if (isOwnCall && canTrade)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final view = ChumbucketPrimaryButton(
                        label: 'View your call',
                        onPressed: () => _openCall(ownCall.call.id),
                      );
                      // The native trade flow is bound to the person's call
                      // ID. Reuse that route; never create a call on a trade
                      // tap or duplicate the wallet/controller lifetime here.
                      final trade = OutlinedButton(
                        onPressed: () => _openCall(ownCall.call.id),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 57),
                          padding: const EdgeInsets.all(14),
                          foregroundColor: AppColors.textPrimary,
                          textStyle: AppTextStyles.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ChumbucketPrimaryButton.radius,
                            ),
                          ),
                        ),
                        child: const Text('Trade'),
                      );
                      return MediaQuery.textScalerOf(context).scale(14) > 21
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [view, const SizedBox(height: 8), trade],
                          )
                          : Row(
                            children: [
                              Expanded(child: view),
                              const SizedBox(width: 8),
                              Expanded(child: trade),
                            ],
                          );
                    },
                  )
                else if (isOwnCall)
                  ChumbucketPrimaryButton(
                    label: 'View your call',
                    onPressed: () => _openCall(ownCall.call.id),
                  )
                else if (_moneyFor(market, acceptsCalls) case final money?) ...[
                  MoneyAmountRow.of(
                    money,
                    value: _amount ??= money.defaultAmount,
                    onChanged: (amount) => setState(() => _amount = amount),
                  ),
                  const SizedBox(height: 10),
                  // Free: ink with the Free marker. An amount: pink.
                  MoneyCallButton(
                    label: 'Make a call',
                    amount: _amount!,
                    onPressed: () => _compose(detail),
                  ),
                ] else
                  // A free call: the ink button with its Free marker.
                  CallJourneyButton(
                    label: 'Make a call',
                    primary: true,
                    free: true,
                    onPressed: acceptsCalls ? () => _compose(detail) : null,
                  ),
                // Panta's terms (§6) ask for attribution on the market
                // module: its compact mark, beside the trade it attributes.
                if (isOwnCall && canTrade) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: PantaMark(),
                  ),
                ],
                if (!acceptsCalls && !isOwnCall) ...[
                  const SizedBox(height: 8),
                  Text(
                    insideCutoff
                        ? 'Calls close '
                            '${((detail.callCutoffMs ?? 0) / 60000).round()} min '
                            'before the market does.'
                        : status,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.textTheme.bodySmall?.copyWith(
                      color: AppColors.onWarningContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Calls close 4 Oct, 14:30 UTC" while the window is open, "Calls closed"
/// once it has passed (M14), or null when the server published no window.
String? _callWindow(MarketDetail detail, DateTime now) {
  final closeAt = detail.callsCloseAtUtc;
  final cutoff = detail.callCutoffMs;
  if (closeAt == null || cutoff == null || cutoff <= 0) return null;
  if (!closeAt.isAfter(now)) return 'Calls closed';
  return 'Calls close ${CallsFormat.timestampShortUtc(closeAt)}';
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

/// Open in green; closed-awaiting or paused in amber; a resolved or cancelled
/// market neutral. Only an open market is ever green.
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

/// One fact as an icon and a few words.
class _Fact extends StatelessWidget {
  const _Fact({
    super.key,
    required this.icon,
    required this.text,
    this.warn = false,
  });
  final String icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final ink = warn ? AppColors.onWarningContainer : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: BasilIcon(icon, size: 16, color: ink),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                height: 1.35,
                fontWeight: warn ? FontWeight.w500 : FontWeight.w400,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixture data's probability snapshot, never presented as a live venue.
class _DemoPrices extends StatelessWidget {
  const _DemoPrices({required this.snapshot});
  final MarketSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'YES ${CallsFormat.probability(snapshot.yesProbability)} · '
        'NO ${CallsFormat.probability(snapshot.noProbability)}',
        style: AppTextStyles.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      const MarketDemoTag(label: 'Demo data · not a live venue or trade'),
    ],
  );
}

/// A rule of the screen rather than an alert: a quiet grey note.
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
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Everything a careful reader checks, behind one disclosure: the venue's
/// exact rules (never summarised — no rule-summary field exists, and none is
/// invented), who resolves it, when, and the IDs.
class _DetailsBlock extends StatelessWidget {
  const _DetailsBlock({required this.market});
  final VenueMarket market;

  @override
  Widget build(BuildContext context) {
    final muted = AppTextStyles.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: muted),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.textTheme.bodyMedium),
        ],
      ),
    );
    final panta =
        market.venue == MarketVenue.panta && market.venueMarketId.isNotEmpty;
    return _surface(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('market-details'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          trailing: const BasilIcon(
            'caret-down-outline',
            color: AppColors.textPrimary,
          ),
          title: Row(
            children: [
              const BasilIcon(
                'book-open-outline',
                size: 20,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rules & details',
                  style: AppTextStyles.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                market.rulesText,
                key: const ValueKey('market-rules'),
                style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Panta's public market page; never its authenticated API URL.
            if (panta)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Resolved by ', style: muted),
                  PantaMarketLink(
                    venueMarketId: market.venueMarketId,
                    style: AppTextStyles.textTheme.bodySmall,
                  ),
                ],
              )
            else
              Text(
                'Resolution source: '
                '${market.resolutionSource ?? 'Not published'}',
                style: muted,
              ),
            fact(
              'Resolves',
              market.resolvesAt == null
                  ? 'Not published'
                  : CallsFormat.timestampUtc(
                    DateTime.fromMillisecondsSinceEpoch(
                      market.resolvesAt!,
                      isUtc: true,
                    ),
                  ),
            ),
            fact('Venue market ID', market.venueMarketId),
            fact('Chumbucket market ID', market.id),
          ],
        ),
      ),
    );
  }
}

/// How people who called it split. Shown only once the viewer has a call of
/// their own (the server withholds it until then). Calls, not venue odds.
class _CrowdBlock extends StatelessWidget {
  const _CrowdBlock({required this.split, required this.market});
  final CrowdSplit split;
  final VenueMarket market;

  @override
  Widget build(BuildContext context) {
    final share = split.yesShare;
    const yesInk = Color(0xFF07644C);
    const noInk = Color(0xFF334155);
    Widget side(String label, int count, Color ink) => Text(
      '$label $count',
      style: GoogleFonts.montserrat(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
    );
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'How people called',
                  style: AppTextStyles.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${split.total} ${split.total == 1 ? 'call' : 'calls'}',
                style: AppTextStyles.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (share != null)
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (share * 1000).round().clamp(1, 999),
                        child: const ColoredBox(color: Color(0xFF7FCFAE)),
                      ),
                      Expanded(
                        flex: ((1 - share) * 1000).round().clamp(1, 999),
                        child: const ColoredBox(color: Color(0xFFC5CBD5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              side(market.labelFor(Side.yes), split.yesCalls, yesInk),
              side(market.labelFor(Side.no), split.noCalls, noInk),
            ],
          ),
        ],
      ),
    );
  }
}
