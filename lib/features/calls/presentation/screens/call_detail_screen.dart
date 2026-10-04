/// One call, opened from the feed or from a shared link.
///
/// A shared link lands here for a signed-out visitor too: reading never needs
/// an account. Only answering does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/embedded_wallet/presentation/embedded_wallet_sheet.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/mwa_connect_button.dart'
    show reconnectWalletApp;
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';
import 'package:chumbucket/features/chumbucket_wallet/presentation/chumbucket_wallet_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/sign_in_methods_sheet.dart'
    show showSignInMethodsSheet;
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/features/money/presentation/money_amount_row.dart'
    show moneyOf;
import 'package:chumbucket/features/money/presentation/money_pending_card.dart';
import 'package:chumbucket/features/money/presentation/money_winnings_card.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/presentation/widgets/thesis_thread.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:chumbucket/features/trust/presentation/funded_trading_attestation_sheet.dart';
import 'package:chumbucket/features/trust/presentation/safety_actions_sheet.dart';

class CallDetailScreen extends StatefulWidget {
  final String callId;

  /// Attribution from a shared link's `?ref=`. Display only.
  final String? sharedByHandle;
  final VoidCallback? onSignInRequested;

  const CallDetailScreen({
    super.key,
    required this.callId,
    this.sharedByHandle,
    this.onSignInRequested,
  });

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  bool _followBusy = false;
  String? _followError;
  PantaTradeController? _trade;
  PantaTradingClient? _tradingClient;

  PantaTradingClient? _statusClient;

  /// A read-only client for the owner's order row. Null when signed out or
  /// when this build has no secure calls server.
  PantaTradingClient? _orderStatusClient() {
    if (_statusClient != null) return _statusClient;
    final account = context.read<ChumbucketSession?>();
    if (account == null || !account.isReady) return null;
    try {
      return _statusClient = PantaTradingClient(
        baseUri: Uri.parse(resolveCallsBffBaseUrl()),
        session: () async {
          final token = await account.bffAuthToken();
          final id = account.userId;
          return token != null && id != null && account.isReady
              ? PantaSession(accountId: id, accessToken: token)
              : null;
        },
      );
    } on ArgumentError {
      return null;
    }
  }

  @override
  void dispose() {
    _trade?.dispose();
    _tradingClient?.close();
    _statusClient?.close();
    super.dispose();
  }

  /// Opens the private Panta trade for the viewer's own call.
  ///
  /// Without the Chumbucket wallet: signs with the wallet app when one is
  /// connected (as before). An account without one — Google or X — signs
  /// with the wallet that lives on this phone, once it exists and the server
  /// has confirmed it is theirs; until then, this opens that wallet's sheet
  /// to make or link it.
  ///
  /// With the Chumbucket wallet (`CHUMBUCKET_WALLET_ENABLED`): it signs by
  /// default and is set up here on first need; a wallet app is the explicit
  /// "Use wallet app" choice ([useWalletApp]); a wallet already on this phone
  /// keeps working.
  Future<void> _fund(CallFeedEntry entry, {bool useWalletApp = false}) async {
    final auth = context.read<MwaAuthProvider>();
    final account = context.read<ChumbucketSession>();
    final onPhone = context.read<EmbeddedWalletController?>();
    final chumbucket = context.read<ChumbucketWalletController?>();
    if (!account.isReady) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    if (chumbucket != null && useWalletApp && !auth.isAuthenticated) {
      if (!await reconnectWalletApp(context) || !mounted) return;
    }
    PantaSignerChoice? choose() => choosePantaSigner(
      walletApp: auth,
      onPhone: onPhone,
      chumbucket: chumbucket,
      useWalletApp: useWalletApp,
      reviewed: PantaReviewedBuy(
        venueMarketId: entry.market.venueMarketId,
        side: entry.call.side,
        amountBaseUnits: () => _trade?.prepared?.order.amountBaseUnits,
      ),
    );
    var choice = choose();
    if (choice == null && chumbucket != null && !useWalletApp) {
      // First need: make and link the Chumbucket wallet, then trade from it.
      if (!await showChumbucketWalletSheet(context, setUp: true) || !mounted) {
        return;
      }
      choice = choose();
    }
    if (choice == null) {
      if (chumbucket != null) return;
      if (onPhone == null) {
        // No wallet on this phone in this build: a wallet app is the way.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Connect your wallet app to trade on Panta.'),
          ),
        );
        return;
      }
      await showEmbeddedWalletSheet(context);
      return;
    }
    final wallet = choice.address;
    // 18+, eligibility and venue terms, recorded server-side before the first
    // funded trade. The BFF refuses a prepare without it regardless.
    if (!await ensureFundedTradingAttestation(context)) return;
    if (!mounted) return;
    if (_trade == null ||
        _trade!.phase == PantaTradePhase.cancelled ||
        _trade!.wallet != wallet) {
      _trade?.dispose();
      _tradingClient?.close();
      _tradingClient = PantaTradingClient(
        baseUri: Uri.parse(resolveCallsBffBaseUrl()),
        session: () async {
          final token = await account.bffAuthToken();
          final id = account.userId;
          return token != null && id != null && account.isReady
              ? PantaSession(accountId: id, accessToken: token)
              : null;
        },
      );
      _trade = PantaTradeController(
        callId: entry.call.id,
        marketId: entry.market.id,
        venueMarketId: entry.market.venueMarketId,
        side: entry.call.side,
        wallet: wallet,
        client: _tradingClient!,
        walletPort: choice.port,
        selectedWallet: choice.selectedWallet,
      );
    }
    await showPantaTradeSheet(
      context: context,
      controller: _trade!,
      marketQuestion: entry.market.question,
      signer: choice.kind,
      // The Chumbucket wallet is the default; a wallet app stays a choice.
      payInstead:
          chumbucket != null && choice.kind != PantaSigner.walletApp
              ? PantaPayInstead(
                label: 'Use wallet app',
                onSelected: () => _fund(entry, useWalletApp: true),
              )
              : null,
      // Settings → Sign-in methods, where a wallet is linked with its proof.
      onLinkWallet: () => showSignInMethodsSheet(context),
    );
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDetail();
    });
  }

  Future<void> _loadDetail() async {
    final provider = context.read<CallsProvider>();
    final detail = await provider.loadCall(widget.callId);
    if (!mounted || detail == null) return;
    await provider.loadPerson(detail.entry.author.id);
  }

  Future<void> _respond(CallFeedEntry entry, CallResponseKind kind) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final existing = provider.marketDetail(entry.market.id)?.viewerCall;
    if (kind.createsOwnCall && existing != null) {
      _openCall(existing.call.id);
      return;
    }
    final result = await showCallResponseSheet(
      context: context,
      entry: entry,
      initialKind: kind,
    );
    if (result == null || !mounted) return;
    if (result.resultingCall case final own?) {
      _openCall(own.call.id);
    } else if (result.invitation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dare sent to @${entry.author.handle}.')),
      );
    }
    await provider.loadCall(widget.callId, force: true);
  }

  void _openCall(String id) => Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => CallDetailScreen(
            callId: id,
            onSignInRequested: widget.onSignInRequested,
          ),
    ),
  );

  void _openMarket(CallFeedEntry entry) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MarketDetailScreen(marketId: entry.market.id),
    ),
  );

  Future<void> _follow(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    if (_followBusy || provider.isFollowBusy(entry.author.id)) return;
    setState(() {
      _followBusy = true;
      _followError = null;
    });
    try {
      final person =
          provider.personDetail(entry.author.id) ??
          await provider.loadPerson(entry.author.id, force: true);
      if (!mounted) return;
      if (person == null) {
        setState(
          () =>
              _followError =
                  provider.personError(entry.author.id) ??
                  'Could not load this person. Try again.',
        );
        return;
      }
      final following = !person.viewerIsFollowing;
      await provider.setFollowing(person, following);
      if (following && mounted) {
        unawaited(PushRegistration.afterSocialAction(context));
      }
    } on CallsException catch (error) {
      if (mounted) setState(() => _followError = error.message);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _addUpdate(CallDetail detail) async {
    final posted = await showThesisUpdateSheet(
      context: context,
      detail: detail,
    );
    if (posted == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Update posted. Your original call is unchanged.'),
      ),
    );
  }

  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      entry: entry,
      receipt: CallReceipt.fromEntry(
        entry,
        shareUrl: provider.shareLinkForCall(entry.call.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const BasilIcon(
            'arrow-left-outline',
            size: 24,
            color: AppColors.textPrimary,
          ),
        ),
        title: Text(
          'The call',
          style: callJourneyHeading(
            context,
            17,
          ).copyWith(fontWeight: FontWeight.w400),
        ),
        actions: [
          Consumer<CallsProvider>(
            builder: (context, provider, _) {
              final entry = provider.callDetail(widget.callId)?.entry;
              if (entry == null) return const SizedBox.shrink();
              final own = entry.author.id == provider.viewerUserId;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Share call',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => _shareReceipt(entry),
                    icon: const BasilIcon(
                      'share-outline',
                      color: AppColors.textPrimary,
                    ),
                  ),
                  // Report, mute or block — never on your own call.
                  if (!own)
                    IconButton(
                      tooltip: 'More',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed:
                          () => showSafetyActions(
                            context,
                            SafetyTarget(
                              personId: entry.author.id,
                              handle: entry.author.handle,
                              displayName: entry.author.displayName,
                              callId: entry.call.id,
                              hasThesis: entry.call.thesis?.isNotEmpty == true,
                            ),
                          ),
                      icon: const BasilIcon(
                        'other-1-outline',
                        color: AppColors.textPrimary,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          final detail = provider.callDetail(widget.callId);
          if (detail == null) {
            if (provider.isLoadingCall(widget.callId)) {
              return const CallsLoadingView(rows: 1);
            }
            if (provider.isOffline) {
              return CallsOfflineView(
                onRetry: () => provider.loadCall(widget.callId, force: true),
              );
            }
            return CallsErrorView(
              message:
                  provider.callError(widget.callId) ??
                  'We couldn\'t open that call.',
              onRetry: () => provider.loadCall(widget.callId, force: true),
            );
          }
          return _body(provider, detail);
        },
      ),
    );
  }

  Widget _body(CallsProvider provider, CallDetail detail) {
    final entry = detail.entry;
    final own = entry.author.id == provider.viewerUserId;
    final hasCalled =
        own ||
        entry.viewerHasCalled ||
        provider.marketDetail(entry.market.id)?.viewerHasCalled == true;
    final following = provider.personDetail(entry.author.id)?.viewerIsFollowing;
    final followBusy = _followBusy || provider.isFollowBusy(entry.author.id);
    final sideLabel = entry.market.labelFor(entry.call.side);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            // Pull to refresh, quietly: nothing on screen says how old it is.
            onRefresh: () => provider.loadCall(widget.callId, force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (widget.sharedByHandle != null)
                  _QuietLine(
                    'Shared by @${widget.sharedByHandle}',
                    icon: 'share-outline',
                  ),
                if (provider.isOffline)
                  const _QuietLine('You’re offline', icon: 'cloud-off-outline'),
                if (own) _LockedBanner(lockedAt: entry.call.lockedAtUtc),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CallJourneyPerson(
                        person: entry.author,
                        // Your own call's banner already carries the instant.
                        subtitle:
                            own
                                ? '@${entry.author.handle}'
                                : '@${entry.author.handle} · ${CallsFormat.relative(entry.call.createdAtUtc)}',
                        onTap:
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => CallPersonScreen(
                                      personRef: entry.author.id,
                                      onSignInRequested:
                                          widget.onSignInRequested,
                                    ),
                              ),
                            ),
                        trailing:
                            own
                                ? null
                                : _FollowPill(
                                  following: following == true,
                                  busy: followBusy,
                                  onPressed:
                                      followBusy ? null : () => _follow(entry),
                                ),
                      ),
                      if (_followError != null) CallInlineError(_followError!),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SidePill(side: entry.call.side),
                          CallFundingMark(entry: entry, quiet: true),
                          if (entry.call.visibility == CallVisibility.followers)
                            const CallBadge(
                              label: 'Followers only',
                              color: AppColors.textSecondary,
                              icon: 'eye-outline',
                              quiet: true,
                            ),
                          DemoVenueBadge(venue: entry.market.venue),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        header: true,
                        child: Text(
                          entry.market.question,
                          style: callJourneyHeading(
                            context,
                            24,
                          ).copyWith(letterSpacing: -.5),
                        ),
                      ),
                      if (sideLabel.toUpperCase() != entry.call.side.wire) ...[
                        const SizedBox(height: 6),
                        Text(sideLabel, style: callJourneyBody()),
                      ],
                      if (entry.call.thesis?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(
                          entry.call.thesis!,
                          style: callJourneyBody(
                            14,
                          ).copyWith(color: AppColors.textPrimary, height: 1.6),
                        ),
                      ],
                      // The thread hangs under the original reason and never
                      // replaces it. Only the author may add to it.
                      ThesisThread(
                        detail: detail,
                        isAuthor: own,
                        onAddUpdate:
                            own && provider.supportsPeople
                                ? () => _addUpdate(detail)
                                : null,
                      ),
                      const SizedBox(height: 14),
                      // Readable here; the receipt carries the exact ISO
                      // timestamps and venue strings as its proof.
                      _FactGrid(facts: _facts(entry)),
                      const SizedBox(height: 4),
                      _LinkRow(
                        icon: 'book-check-outline',
                        label: 'Market & rules',
                        onTap: () => _openMarket(entry),
                      ),
                    ],
                  ),
                ),
                if (detail.parent case final parent?) ...[
                  const SizedBox(height: 12),
                  _ParentCall(
                    parent: parent,
                    backed: entry.call.side == parent.call.side,
                    onTap: () => _openCall(parent.call.id),
                  ),
                ],
                // Money v1, the owner's alone: a call whose money is still
                // pending (never stamped funded), and winnings to collect.
                if (own && entry.money?.pending == true) ...[
                  const SizedBox(height: 12),
                  MoneyPendingCard(
                    entry: entry,
                    onChanged:
                        () => provider.loadCall(widget.callId, force: true),
                  ),
                ],
                if (own &&
                    (moneyOf(context)?.winnings.forCall(entry.call.id) !=
                        null)) ...[
                  const SizedBox(height: 12),
                  MoneyWinningsCard(callId: entry.call.id),
                ],
                // Only the owner sees the established private Panta trade
                // entry, and only on a market Chumbucket can trade (a
                // SOL-quoted Panta market takes calls, never trades).
                if (own && entry.market.tradable && entry.money == null) ...[
                  const SizedBox(height: 12),
                  _TradeCard(
                    side: entry.call.side,
                    funded: _trade?.isFunded == true,
                    onPressed: () => _fund(entry),
                    // The latest order on this call, refreshing itself
                    // until Panta and Solana confirm or fail it.
                    status: switch (_orderStatusClient()) {
                      final client? => PantaOrderStatusRow(
                        // A new order from the sheet re-reads the row.
                        key: ValueKey(
                          'order-status-${_trade?.order?.orderId}-${_trade?.order?.fundingState.wire}',
                        ),
                        callId: entry.call.id,
                        client: client,
                      ),
                      null => null,
                    },
                  ),
                ],
                // Response kinds/counts disclose the split, so they stay gated.
                if (hasCalled && detail.responses.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: Text(
                      'Responses',
                      style: callJourneyHeading(context, 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final response in detail.responses)
                    _ResponseRow(
                      response: response,
                      onTap:
                          response.resultingCallId == null
                              ? null
                              : () => _openCall(response.resultingCallId!),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (!own)
          _AnswerBar(
            entry: entry,
            onBack: () => _respond(entry, CallResponseKind.back),
            onFade: () => _respond(entry, CallResponseKind.fade),
            onDare: () => _respond(entry, CallResponseKind.challenge),
          ),
      ],
    );
  }

  /// The call's facts as label/value tiles: when it locked, what its side
  /// cost then, when the market closes, and where the result stands.
  List<_Fact> _facts(CallFeedEntry entry) {
    final call = entry.call;
    // The odds its side had when it locked, as a percent (USDC and SOL
    // markets alike), weighed against the other side's price.
    final price = switch (call.entryPrice) {
      final snapshot? => CallsFormat.sideOdds(snapshot, call.side),
      null =>
        entry.market.venue != MarketVenue.panta && call.entryProbability != null
            ? CallsFormat.probability(call.entryProbability)
            : null,
    };
    // When it locked is said once: beside the name (and, on your own call,
    // in the "You're on record" banner), never again as a tile.
    return [
      if (price != null) _Fact('chart-pie-outline', call.side.wire, price),
      if (entry.market.closesAtUtc case final closes?)
        switch (CallsFormat.timeLeft(closes)) {
          final left? => _Fact('clock-outline', 'Closes', 'in $left'),
          null => _Fact(
            'clock-outline',
            'Closed',
            CallsFormat.shortWhen(closes),
          ),
        },
      _Fact(
        entry.outcome.isSettled ? 'award-outline' : 'timer-outline',
        'Result',
        switch (entry.outcome) {
          CallOutcome.pending => 'Pending',
          CallOutcome.correct => 'Correct',
          CallOutcome.incorrect => 'Incorrect',
          CallOutcome.voided => 'Void',
        },
      ),
      if (call.confidence != null)
        _Fact(
          'star-outline',
          own(entry) ? 'Your confidence' : 'Their confidence',
          CallsFormat.probability(call.confidence),
        ),
    ];
  }

  bool own(CallFeedEntry entry) =>
      entry.author.id == context.read<CallsProvider>().viewerUserId;
}

/// The prototype's pink ink for text actions (#B8173B, 6.4:1 on white).
const _pinkInk = Color(0xFFB8173B);

/// Your own call, from the prototype: a green "on record" banner with the
/// instant it locked.
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.lockedAt});
  final DateTime lockedAt;

  static const _ink = Color(0xFF07644C);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFE6F6EF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const BasilIcon('lock-outline', size: 20, color: _ink),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You’re on record',
                style: callJourneyHeading(context, 14).copyWith(color: _ink),
              ),
              const SizedBox(height: 2),
              Text(
                '${CallsFormat.timestampShortUtc(lockedAt)} · can’t be edited',
                style: callJourneyBody(12).copyWith(color: _ink),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuietLine extends StatelessWidget {
  const _QuietLine(this.text, {required this.icon});
  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Row(
      children: [
        BasilIcon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: callJourneyBody(12))),
      ],
    ),
  );
}

/// Follow as a small pill beside the name.
class _FollowPill extends StatelessWidget {
  const _FollowPill({
    required this.following,
    required this.busy,
    required this.onPressed,
  });
  final bool following;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label =
        busy
            ? 'Updating…'
            : following
            ? 'Following'
            : 'Follow';
    final icon = BasilIcon(
      following ? 'check-outline' : 'user-plus-outline',
      size: following ? 16 : 18,
      color: following ? AppColors.textMuted : _pinkInk,
    );
    final fill =
        following ? const Color(0xFFF6F6F7) : AppColors.primaryContainer;
    // On a narrow phone or at large text the name needs the room: the pill
    // becomes its icon, and says its words to a screen reader.
    final cramped =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(13) > 18;
    if (cramped) {
      return Tooltip(
        message: label,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(backgroundColor: fill),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: Semantics(label: label, excludeSemantics: true, child: icon),
        ),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: _pinkInk,
        backgroundColor: fill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      icon: icon,
      label: Text(
        label,
        style: callJourneyBody(13).copyWith(
          color: following ? AppColors.textMuted : _pinkInk,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Fact {
  const _Fact(this.icon, this.label, this.value);
  final String icon;
  final String label;
  final String value;
}

/// Facts as compact tiles, two to a row when they fit.
class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.facts});
  final List<_Fact> facts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final two =
          constraints.maxWidth >= 280 &&
          MediaQuery.textScalerOf(context).scale(13) <= 18;
      final width =
          two ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final fact in facts)
            SizedBox(
              width: width,
              child: MergeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      BasilIcon(
                        fact.icon,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fact.label, style: callJourneyBody(11)),
                            Text(
                              fact.value,
                              style: callJourneyBody(13).copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// A whole-row link with a chevron.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, this.onTap});
  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            BasilIcon(icon, size: 18, color: _pinkInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: callJourneyHeading(
                  context,
                  13,
                ).copyWith(color: _pinkInk),
              ),
            ),
            const BasilIcon('arrow-right-outline', size: 16, color: _pinkInk),
          ],
        ),
      ),
    ),
  );
}

/// The call this one answers, as one tappable row.
class _ParentCall extends StatelessWidget {
  const _ParentCall({
    required this.parent,
    required this.backed,
    required this.onTap,
  });
  final CallFeedEntry parent;
  final bool backed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${backed ? 'Backed' : 'Faded'} @${parent.author.handle}, who called '
        '${parent.call.side.wire} on ${parent.market.question}. Open their call.',
    excludeSemantics: true,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CallSideColors.fill(parent.call.side),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: BasilIcon(
                  backed ? CallResponseIcons.back : CallResponseIcons.fade,
                  size: 20,
                  color: CallSideColors.ink(parent.call.side),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${backed ? 'Backed' : 'Faded'} @${parent.author.handle} · ${parent.call.side.wire}',
                      style: callJourneyBody(12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parent.market.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: callJourneyHeading(context, 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const BasilIcon(
                'arrow-right-outline',
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The optional, private Panta trade on your own call.
class _TradeCard extends StatelessWidget {
  const _TradeCard({
    required this.side,
    required this.funded,
    required this.onPressed,
    this.status,
  });
  final Side side;
  final bool funded;
  final VoidCallback onPressed;
  final Widget? status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
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
                color: Color(0xFFF6F6F7),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const BasilIcon(
                'wallet-outline',
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trade it on Panta',
                    style: callJourneyHeading(context, 15),
                  ),
                  Text(
                    'Optional · real USDC · you can lose it',
                    style: callJourneyBody(12),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (status != null) ...[const SizedBox(height: 10), status!],
        const SizedBox(height: 12),
        CallJourneyButton(
          label:
              funded
                  ? 'View your Panta funding'
                  : 'Review a ${side.wire} trade',
          onPressed: onPressed,
        ),
      ],
    ),
  );
}

/// One Back, Fade or Dare on this call.
class _ResponseRow extends StatelessWidget {
  const _ResponseRow({required this.response, this.onTap});
  final CallResponse response;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        response.resultingCallId == null
            ? '${response.kind.label} sent'
            : response.kind.label;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              BasilIcon(
                CallResponseIcons.of(response.kind),
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$label · ${CallsFormat.relative(response.createdAtUtc)}',
                  style: callJourneyBody(
                    13,
                  ).copyWith(color: AppColors.textPrimary),
                ),
              ),
              if (onTap != null)
                const BasilIcon(
                  'arrow-right-outline',
                  size: 16,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back, Fade and Dare on someone else's call, always in reach.
class _AnswerBar extends StatelessWidget {
  const _AnswerBar({
    required this.entry,
    required this.onBack,
    required this.onFade,
    required this.onDare,
  });
  final CallFeedEntry entry;
  final VoidCallback onBack;
  final VoidCallback onFade;
  final VoidCallback onDare;

  @override
  Widget build(BuildContext context) {
    final open = entry.market.status.acceptsNewCalls;
    final dare = SizedBox(
      width: ChumbucketPrimaryButton.height,
      height: ChumbucketPrimaryButton.height,
      child: Tooltip(
        message: 'Dare @${entry.author.handle}',
        child: OutlinedButton(
          onPressed: onDare,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.outlineVariant, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                ChumbucketPrimaryButton.radius,
              ),
            ),
          ),
          child: Semantics(
            label: 'Dare @${entry.author.handle}',
            excludeSemantics: true,
            // A dare is free: ink, never pink (pink is money).
            child: const BasilIcon(
              CallResponseIcons.dare,
              size: 22,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
    // Backing is a free call: the ink button with its Free marker.
    final back = CallJourneyButton(
      label: 'Back · ${entry.call.side.wire}',
      primary: true,
      free: true,
      onPressed: onBack,
    );
    final fade = CallJourneyButton(
      label: 'Fade · ${entry.call.side.opposite.wire}',
      onPressed: onFade,
    );
    // Back, with its Free marker, always takes its own row; Fade and Dare
    // share the one below.
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child:
            !open
                ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${entry.market.status.label} · no new calls',
                        style: callJourneyBody(13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    dare,
                  ],
                )
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    back,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: fade),
                        const SizedBox(width: 8),
                        dare,
                      ],
                    ),
                  ],
                ),
      ),
    );
  }
}
