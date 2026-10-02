/// One call, opened from the feed or from a shared link.
///
/// A shared link lands here for a signed-out visitor too: reading never needs
/// an account. Only answering does.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/embedded_wallet/presentation/embedded_wallet_sheet.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

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
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';

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

  @override
  void dispose() {
    _trade?.dispose();
    _tradingClient?.close();
    super.dispose();
  }

  /// Opens the private Panta trade for the viewer's own call.
  ///
  /// Signs with the wallet app when one is connected (as before). An account
  /// without one — Google or X — signs with the wallet that lives on this
  /// phone, once it exists and the server has confirmed it is theirs; until
  /// then, this opens that wallet's sheet to make or link it.
  Future<void> _fund(CallFeedEntry entry) async {
    final auth = context.read<MwaAuthProvider>();
    final account = context.read<ChumbucketSession>();
    final onPhone = context.read<EmbeddedWalletController?>();
    if (!account.isReady) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final choice = choosePantaSigner(
      walletApp: auth,
      onPhone: onPhone,
      reviewed: PantaReviewedBuy(
        venueMarketId: entry.market.venueMarketId,
        side: entry.call.side,
        amountBaseUnits: () => _trade?.prepared?.order.amountBaseUnits,
      ),
    );
    if (choice == null) {
      if (onPhone == null) return;
      await showEmbeddedWalletSheet(context);
      return;
    }
    final wallet = choice.address;
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
        const SnackBar(
          content: Text('Invitation sent. No call or position was created.'),
        ),
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
      await provider.setFollowing(person, !person.viewerIsFollowing);
    } on CallsException catch (error) {
      if (mounted) setState(() => _followError = error.message);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
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
              return IconButton(
                tooltip: 'Share call',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => _shareReceipt(entry),
                icon: const BasilIcon(
                  'share-outline',
                  color: AppColors.textPrimary,
                ),
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
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (widget.sharedByHandle != null)
                CallJourneyNote(
                  'Shared with you by @${widget.sharedByHandle}.',
                  icon: 'share-outline',
                ),
              if (provider.isOffline) ...[
                const CallJourneyNote('Offline — showing what we already had.'),
                CallJourneyButton(
                  label: 'Retry',
                  onPressed:
                      () => provider.loadCall(widget.callId, force: true),
                ),
              ],
              if (entry.market.venue.isDemo)
                const CallJourneyNote(
                  'DEMO DATA · Sample market, not a live call.',
                ),
              if (own) _LockedBanner(lockedAt: entry.call.lockedAtUtc),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CallJourneyPerson(
                      person: entry.author,
                      subtitle:
                          '@${entry.author.handle} · ${CallsFormat.timestampShortUtc(entry.call.createdAtUtc)}',
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => CallPersonScreen(
                                    personRef: entry.author.id,
                                    onSignInRequested: widget.onSignInRequested,
                                  ),
                            ),
                          ),
                      trailing:
                          own
                              ? null
                              : TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  foregroundColor: _pinkInk,
                                ),
                                onPressed:
                                    _followBusy ||
                                            provider.isFollowBusy(
                                              entry.author.id,
                                            )
                                        ? null
                                        : () => _follow(entry),
                                child: Text(
                                  _followBusy ||
                                          provider.isFollowBusy(entry.author.id)
                                      ? 'Updating…'
                                      : following == true
                                      ? 'Following'
                                      : 'Follow',
                                  style: callJourneyBody(13).copyWith(
                                    color: _pinkInk,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                    ),
                    if (_followError != null)
                      Semantics(
                        liveRegion: true,
                        child: CallJourneyNote(_followError!, error: true),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SidePill(side: entry.call.side),
                        Text(
                          entry.call.visibility == CallVisibility.followers
                              ? 'Free call · locked · Followers only'
                              : 'Free call · locked',
                          style: callJourneyBody(12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    if (entry.market.labelFor(entry.call.side).toUpperCase() !=
                        entry.call.side.wire) ...[
                      const SizedBox(height: 8),
                      Text(
                        entry.market.labelFor(entry.call.side),
                        style: callJourneyBody(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      entry.call.thesis?.isNotEmpty == true
                          ? entry.call.thesis!
                          : 'No reason added.',
                      style: callJourneyBody(
                        14,
                      ).copyWith(color: AppColors.textPrimary, height: 1.75),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 18, bottom: 14),
                      child: Divider(
                        height: 1,
                        color: AppColors.outlineVariant,
                      ),
                    ),
                    // Readable here; the receipt carries the exact ISO
                    // timestamps and venue strings as its proof.
                    CallJourneyFact(
                      'Locked',
                      CallsFormat.timestampUtc(entry.call.lockedAtUtc),
                    ),
                    if (entry.call.confidence != null)
                      CallJourneyFact(
                        'Their confidence',
                        '${CallsFormat.probability(entry.call.confidence)} · self-reported',
                      ),
                    CallJourneyFact(
                      '${entry.call.side.wire} when called',
                      entry.call.entryPrice != null
                          ? CallsFormat.sharePrice(switch (entry
                              .call
                              .entryPrice!
                              .priceFor(entry.call.side)) {
                            final price? => CallsFormat.displayPrice(price),
                            null => null,
                          })
                          : entry.market.venue == MarketVenue.panta ||
                              entry.call.entryProbability == null
                          ? 'Price not captured'
                          : CallsFormat.probability(
                            entry.call.entryProbability,
                          ),
                    ),
                    CallJourneyFact(
                      'Source',
                      CallsFormat.venueAttribution(entry.market),
                    ),
                    if (entry.call.entryPrice?.priceFor(entry.call.side)
                        case final exact?
                        when CallsFormat.priceWasRounded(exact))
                      CallJourneyFact('Exact price', exact),
                    if (entry.call.entryPrice case final price?)
                      CallJourneyFact(
                        'Price observed',
                        CallsFormat.timestampUtc(price.observedAtUtc),
                      ),
                    CallJourneyFact(
                      'Closes',
                      entry.market.closesAtUtc == null
                          ? 'No close time published'
                          : CallsFormat.timestampUtc(entry.market.closesAtUtc!),
                    ),
                    CallJourneyFact('Market status', entry.market.status.label),
                    CallJourneyFact(
                      'Result',
                      entry.outcome == CallOutcome.pending
                          ? 'Awaiting ${entry.market.venue.isDemo ? 'the demo venue' : entry.market.venue.label}'
                          : CallsFormat.outcomeSentence(entry.outcome),
                    ),
                    if (entry.outcome == CallOutcome.pending)
                      Text(
                        'Closing time alone does not settle this call.',
                        style: callJourneyBody(12),
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                          foregroundColor: _pinkInk,
                        ),
                        iconAlignment: IconAlignment.end,
                        onPressed: () => _openMarket(entry),
                        icon: const BasilIcon(
                          'arrow-right-outline',
                          size: 16,
                          color: _pinkInk,
                        ),
                        label: Text(
                          'View market & rules',
                          style: callJourneyHeading(
                            context,
                            13,
                          ).copyWith(color: _pinkInk),
                        ),
                      ),
                    ),
                    if (entry.outcome.isSettled) ...[
                      const SizedBox(height: 8),
                      CallJourneyButton(
                        label: 'View & share receipt',
                        icon: 'share-outline',
                        onPressed: () => _shareReceipt(entry),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (detail.parent case final parent?) ...[
                Text('In response to', style: callJourneyHeading(context, 18)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CallJourneyPerson(
                        person: parent.author,
                        subtitle:
                            '${entry.call.side == parent.call.side ? 'Backed' : 'Faded'} @${parent.author.handle} · they called ${parent.call.side.wire}',
                        onTap:
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => CallPersonScreen(
                                      personRef: parent.author.id,
                                    ),
                              ),
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        parent.market.question,
                        style: callJourneyHeading(context, 18),
                      ),
                      const SizedBox(height: 12),
                      CallJourneyButton(
                        label: 'Open original call',
                        onPressed: () => _openCall(parent.call.id),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              CallJourneyNote(
                hasCalled
                    ? 'Your call is locked. Eligible community opinion is available on the market.'
                    : 'Your opinion first. The community split appears after you lock a call.',
                icon: 'lock-outline',
                quiet: true,
              ),
              if (!provider.isSignedIn)
                Text(
                  'You can read this without an account. Sign in to answer it.',
                  style: callJourneyBody(12),
                ),
              if (!own) ...[
                const SizedBox(height: 12),
                Text(
                  'Disagree with a friend?',
                  style: callJourneyHeading(context, 18),
                ),
                const SizedBox(height: 12),
                CallJourneyButton(
                  label: 'Invite a challenge',
                  icon: 'arrow-right-outline',
                  onPressed: () => _respond(entry, CallResponseKind.challenge),
                ),
                const SizedBox(height: 8),
                Text(
                  'A free invitation to take a side. No pot or payment is created.',
                  style: callJourneyBody(12),
                ),
              ],
              // Only the owner sees the established private Panta trade entry.
              if (own && entry.market.venue == MarketVenue.panta) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Want a position too?',
                        style: callJourneyHeading(context, 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your call is already made. A trade is optional, private, and needs a separate wallet approval.',
                        style: callJourneyBody(),
                      ),
                      const SizedBox(height: 12),
                      CallJourneyButton(
                        label:
                            _trade?.isFunded == true
                                ? 'View your Panta funding'
                                : 'Review a ${entry.call.side.wire} trade',
                        onPressed: () => _fund(entry),
                      ),
                      const SizedBox(height: 8),
                      Text('Powered by Panta', style: callJourneyBody(12)),
                    ],
                  ),
                ),
              ],
              // Response kinds/counts disclose the split, so they stay gated too.
              if (hasCalled && detail.responses.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Responses', style: callJourneyHeading(context, 18)),
                const SizedBox(height: 12),
                for (final response in detail.responses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${response.kind.label} · ${CallsFormat.relative(response.createdAtUtc)}',
                          style: callJourneyBody(),
                        ),
                        if (response.resultingCallId != null)
                          CallJourneyButton(
                            label: 'Open their call',
                            onPressed:
                                () => _openCall(response.resultingCallId!),
                          )
                        else
                          Text(
                            'Invitation sent · no call created',
                            style: callJourneyBody(12),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (!own)
          SafeArea(
            top: false,
            child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final back = CallJourneyButton(
                        label: 'Back · ${entry.call.side.wire}',
                        primary: true,
                        onPressed:
                            entry.market.status.acceptsNewCalls
                                ? () => _respond(entry, CallResponseKind.back)
                                : null,
                      );
                      final fade = CallJourneyButton(
                        label: 'Fade · ${entry.call.side.opposite.wire}',
                        onPressed:
                            entry.market.status.acceptsNewCalls
                                ? () => _respond(entry, CallResponseKind.fade)
                                : null,
                      );
                      return Row(
                        children: [
                          Expanded(child: back),
                          const SizedBox(width: 8),
                          Expanded(child: fade),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.market.status.acceptsNewCalls
                        ? 'Review your own free call. Neither button places a trade.'
                        : '${entry.market.status.label} · no new calls.',
                    textAlign: TextAlign.center,
                    style: callJourneyBody(12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
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
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(13),
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
              const SizedBox(height: 4),
              Text(
                '${CallsFormat.timestampUtc(lockedAt)} · side, reason and time can’t be edited',
                style: callJourneyBody(12).copyWith(color: _ink),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
