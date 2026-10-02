/// One proposal: what it says, where it stands, and the next step for the
/// person looking at it (withdraw, approve/reject, publish, open the market).
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_create.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/market_creation_models.dart';
import '../market_creation_controller.dart';
import 'create_market_screen.dart';
import 'publish_market_sheet.dart';
import 'reject_proposal_sheet.dart';
import 'widgets/proposal_widgets.dart';

/// The wallet that would pay for a publish, or null when none is connected.
/// A [PantaEmbeddedCreateWallet] port means the wallet on this phone signs.
typedef PublishWallet = ({String address, PantaWalletPort port});
typedef PublishWalletResolver = PublishWallet? Function(BuildContext context);

PublishWallet? connectedMwaWallet(BuildContext context) {
  final auth = context.read<MwaAuthProvider?>();
  final address = auth?.walletAddress;
  if (auth == null || !auth.isAuthenticated || address == null) return null;
  return (address: address, port: PantaMwaWallet(auth));
}

/// The same order as trades (`choosePantaSigner`): a connected wallet app,
/// else the account's wallet on this phone once the server has linked it.
PublishWallet? publishWalletOf(BuildContext context) {
  final app = connectedMwaWallet(context);
  if (app != null) return app;
  final onPhone = context.read<EmbeddedWalletController?>();
  final key = onPhone?.signer;
  if (onPhone == null || key == null) return null;
  return (
    address: key.address,
    port: PantaEmbeddedCreateWallet(
      signer: () => onPhone.signer,
      address: key.address,
    ),
  );
}

class ProposalDetailScreen extends StatefulWidget {
  const ProposalDetailScreen({
    super.key,
    required this.controller,
    required this.proposalId,
    this.wallet = publishWalletOf,
    this.openMarket,
  });

  final MarketCreationController controller;
  final String proposalId;
  final PublishWalletResolver wallet;

  /// Opens a live market; defaults to the catalog's MarketDetailScreen.
  final void Function(BuildContext context, String marketId)? openMarket;

  @override
  State<ProposalDetailScreen> createState() => _ProposalDetailScreenState();
}

class _ProposalDetailScreenState extends State<ProposalDetailScreen> {
  MarketCreationController get c => widget.controller;
  MarketProposal? get proposal => c.find(widget.proposalId);
  String? _error;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    await c.refresh(widget.proposalId, onError: _fail);
  }

  Future<void> _withdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Withdraw this market?'),
            content: const Text(
              'It won’t be reviewed or published. This can’t be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep it'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Withdraw'),
              ),
            ],
          ),
    );
    if (ok == true) await c.withdraw(widget.proposalId, onError: _fail);
  }

  Future<void> _reject() async {
    final decision = await showRejectProposalSheet(context);
    if (decision == null || !mounted) return;
    await c.reject(
      widget.proposalId,
      reason: decision.reason,
      note: decision.note,
      onError: _fail,
    );
  }

  Future<void> _publish(MarketProposal current) async {
    final wallet = widget.wallet(context);
    if (wallet == null) {
      _fail(
        'Publishing needs a Solana wallet with USDC: connect your wallet app, '
        'or make one on this phone in Profile → My wallet. The wallet that '
        'publishes pays Panta’s creation fee.',
      );
      return;
    }
    final publish = PublishMarketController(
      client: c.client,
      proposal: current,
      wallet: wallet.address,
      walletPort: wallet.port,
    );
    final port = wallet.port;
    // The on-phone signer only signs the create for the market reviewed.
    if (port is PantaEmbeddedCreateWallet) {
      port.reviewedEvent = () => publish.review?.eventAddress;
    }
    try {
      final result = await showPublishMarketSheet(
        context: context,
        controller: publish,
        onPhone: port is PantaEmbeddedCreateWallet,
      );
      if (result != null) c.accept(result);
    } finally {
      publish.dispose();
    }
    if (mounted) unawaited(_refresh());
  }

  /// A rejected or expired market, proposed again with its text prefilled.
  Future<void> _proposeAgain(MarketProposal p) async {
    final created = await Navigator.of(context).push<MarketProposal>(
      MaterialPageRoute(
        builder:
            (_) => CreateMarketScreen(
              controller: c,
              initial: MarketDraft(
                question: p.question,
                category:
                    MarketCategory.fromWire(p.category) ?? MarketCategory.other,
                closesAt: p.closesAt,
                resolvesAt: p.resolvesAt,
                rules: p.rules,
                sources: p.sources,
                description: p.description,
              ),
            ),
      ),
    );
    if (created == null || !mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder:
              (_) => ProposalDetailScreen(
                controller: c,
                proposalId: created.id,
                wallet: widget.wallet,
                openMarket: widget.openMarket,
              ),
        ),
      ),
    );
  }

  void _open(String marketId) {
    final open = widget.openMarket;
    if (open != null) return open(context, marketId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MarketDetailScreen(marketId: marketId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          p == null || p.viewerIsProposer ? 'Your market' : 'Market proposal',
          style: AppTextStyles.textTheme.titleLarge,
        ),
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
            tooltip: 'Refresh',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _refresh,
            icon: const BasilIcon(
              'refresh-outline',
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      body:
          p == null
              ? Center(
                child:
                    c.isBusy(widget.proposalId)
                        ? const CircularProgressIndicator()
                        : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error ?? 'This market proposal isn’t available.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.textTheme.bodyMedium,
                          ),
                        ),
              )
              : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _surface([
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            p.categoryLabel.toUpperCase(),
                            style: AppTextStyles.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              letterSpacing: .6,
                            ),
                          ),
                          ProposalStatusPill(status: p.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(p.question, style: AppTextStyles.questionTitle),
                      const SizedBox(height: 10),
                      _meta('Outcomes', 'YES · NO'),
                      _meta('Trading closes', localTime(p.closesAt)),
                      _meta('Result known by', localTime(p.resolvesAt)),
                      if (p.proposer != null)
                        _meta('Proposed by', p.proposer!.atHandle),
                    ]),
                    const SizedBox(height: 12),
                    _next(p),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _surface([
                      Text(
                        'How it resolves',
                        style: AppTextStyles.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(p.rules, style: AppTextStyles.textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      Text(
                        'Sources',
                        style: AppTextStyles.textTheme.titleMedium,
                      ),
                      for (final source in p.sources)
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed:
                              () => launchUrl(
                                Uri.parse(source),
                                mode: LaunchMode.externalApplication,
                              ),
                          child: Text(
                            source,
                            style: AppTextStyles.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      if (p.description != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Description',
                          style: AppTextStyles.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p.description!,
                          style: AppTextStyles.textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 12),
                      const PoweredByPanta(),
                    ]),
                  ],
                ),
              ),
    );
  }

  /// The one thing that happens next, for this viewer.
  Widget _next(MarketProposal p) {
    final busy = c.isBusy(p.id);
    final reviewer = c.isReviewer;
    final children = <Widget>[];
    void say(String title, String body) {
      children
        ..add(Text(title, style: AppTextStyles.textTheme.titleMedium))
        ..add(const SizedBox(height: 6))
        ..add(
          Text(
            body,
            style: AppTextStyles.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        );
    }

    switch (p.status) {
      case ProposalStatus.pendingReview:
        say(
          'Waiting for review',
          'Chumbucket checks that the question is clear and the result can be verified from the sources. The decision shows up here.',
        );
        if (reviewer) {
          children.addAll([
            const SizedBox(height: 14),
            ChumbucketPrimaryButton(
              label: 'Approve',
              busy: busy,
              onPressed: () => c.approve(p.id, onError: _fail),
            ),
            ChumbucketTextAction(
              label: 'Reject',
              onPressed: busy ? null : _reject,
            ),
          ]);
        }
      case ProposalStatus.approved:
        say(
          'Approved',
          'Publish it on Panta to make it callable. Publish before ${localTime(p.publishDeadline)}, or trading closes too soon for Panta to accept it.',
        );
        children.add(const SizedBox(height: 14));
        if (p.canPublish) {
          children.add(
            ChumbucketPrimaryButton(
              label:
                  p.viewerIsProposer
                      ? 'Publish on Panta'
                      : 'Sponsor and publish',
              busy: busy,
              onPressed: () => _publish(p),
            ),
          );
        } else {
          children.add(
            Text(
              'Publishing to Panta isn’t switched on yet. Your approved market is saved.',
              style: AppTextStyles.textTheme.bodySmall?.copyWith(
                color: AppColors.onWarningContainer,
              ),
            ),
          );
        }
        if (reviewer && !p.viewerIsProposer) {
          children.add(
            ChumbucketTextAction(
              label: 'Reject',
              onPressed: busy ? null : _reject,
            ),
          );
        }
      case ProposalStatus.publishing:
        say(
          'Publishing on Panta',
          'The create was signed and sent from ${p.publishingWallet ?? 'the publishing wallet'}. It goes live once Solana confirms it and Panta registers it. Don’t publish it again.',
        );
        children.addAll([
          const SizedBox(height: 14),
          ChumbucketPrimaryButton(
            label: 'Check status',
            busy: busy,
            onPressed: _refresh,
          ),
        ]);
      case ProposalStatus.live:
        say('Live on Panta', 'Anyone can make a call on it now.');
        if (p.live != null) {
          children.addAll([
            const SizedBox(height: 14),
            ChumbucketPrimaryButton(
              label: 'Open market',
              onPressed: () => _open(p.live!.marketId),
            ),
          ]);
        }
      case ProposalStatus.rejected:
        say(
          'Not approved',
          [
            p.review?.reason?.label ?? 'This market wasn’t approved.',
            if (p.review?.note != null) '“${p.review!.note}”',
            if (p.viewerIsProposer) 'You can propose a clearer version.',
          ].join('\n'),
        );
      case ProposalStatus.withdrawn:
        say('Withdrawn', 'This proposal won’t be reviewed or published.');
      case ProposalStatus.expired:
        say(
          'Too late to publish',
          'Trading closes too soon for Panta to accept this market. Propose it again with a later close.',
        );
    }
    if (p.viewerIsProposer &&
        (p.status == ProposalStatus.rejected ||
            p.status == ProposalStatus.expired)) {
      children.addAll([
        const SizedBox(height: 14),
        ChumbucketPrimaryButton(
          label: 'Propose it again',
          onPressed: () => _proposeAgain(p),
        ),
      ]);
    }
    if (p.canWithdraw) {
      children.add(
        ChumbucketTextAction(
          label: 'Withdraw proposal',
          color: AppColors.textSecondary,
          onPressed: busy ? null : _withdraw,
        ),
      );
    }
    return _surface(children);
  }

  Widget _surface(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _meta(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      spacing: 8,
      children: [
        Text(
          '$label:',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(value, style: AppTextStyles.textTheme.bodySmall),
      ],
    ),
  );
}
