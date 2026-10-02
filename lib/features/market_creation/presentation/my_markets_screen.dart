/// "Your markets": what you proposed and where each stands. Reviewers also
/// get the review queue (pending, and approved ones waiting for a wallet).
///
/// This screen owns the market-creation controller and its BFF client for
/// the whole flow (create, detail, publish), and closes them when it goes.
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/market_creation_client.dart';
import '../data/market_creation_models.dart';
import '../market_creation_controller.dart';
import 'create_market_screen.dart';
import 'proposal_detail_screen.dart';
import 'widgets/proposal_widgets.dart';

/// Opens "Your markets", optionally going straight to the create form.
Future<void> openMarketCreation(BuildContext context, {bool create = false}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyMarketsScreen(startWithCreate: create),
      ),
    );

class MyMarketsScreen extends StatefulWidget {
  const MyMarketsScreen({
    super.key,
    this.controller,
    this.startWithCreate = false,
    this.wallet = publishWalletOf,
  });

  /// Injected by tests; otherwise built on the session's BFF token.
  final MarketCreationController? controller;
  final bool startWithCreate;
  final PublishWalletResolver wallet;

  @override
  State<MyMarketsScreen> createState() => _MyMarketsScreenState();
}

class _MyMarketsScreenState extends State<MyMarketsScreen> {
  late final MarketCreationController _controller;
  MarketCreationClient? _ownedClient;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      final session = context.read<ChumbucketSession>();
      _ownedClient = MarketCreationClient.bff(authToken: session.bffAuthToken);
      _controller = MarketCreationController(client: _ownedClient!);
    }
    _controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(_controller.loadMine());
      await _controller.loadStatus();
      if (!mounted) return;
      unawaited(_controller.loadQueue());
      if (widget.startWithCreate) unawaited(_create());
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) {
      _controller.dispose();
      _ownedClient?.close();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<MarketProposal>(
      MaterialPageRoute(
        builder: (_) => CreateMarketScreen(controller: _controller),
      ),
    );
    if (created != null && mounted) {
      setState(() => _tab = 0);
      unawaited(_openProposal(created.id));
    }
  }

  Future<void> _openProposal(String id) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder:
          (_) => ProposalDetailScreen(
            controller: _controller,
            proposalId: id,
            wallet: widget.wallet,
          ),
    ),
  );

  Future<void> _reload() async {
    await Future.wait([_controller.loadMine(), _controller.loadQueue()]);
  }

  @override
  Widget build(BuildContext context) {
    final reviewer = _controller.isReviewer;
    final tab = reviewer ? _tab : 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Your markets', style: AppTextStyles.textTheme.titleLarge),
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
            tooltip: 'Create a market',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _create,
            icon: const BasilIcon('add-outline', color: AppColors.textPrimary),
          ),
        ],
      ),
      body: Column(
        children: [
          if (reviewer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ChumbucketTabs(
                labels: [
                  'Mine',
                  'To review (${_controller.queue?.pending.length ?? 0})',
                ],
                selectedIndex: tab,
                onSelected: (i) => setState(() => _tab = i),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: tab == 0 ? _mine() : _queue(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mine() {
    final c = _controller;
    if (c.loadingMine && c.mine.isEmpty) return const CallsLoadingView(rows: 2);
    if (c.mine.isEmpty && c.mineError != null) {
      return ListView(
        children: [CallsErrorView(message: c.mineError!, onRetry: c.loadMine)],
      );
    }
    if (c.mine.isEmpty) {
      return ListView(
        children: [
          CallsEmptyView(
            artwork: ChumbucketStateArtwork.search,
            title: 'No markets yet',
            message:
                'Can’t find the question you want to call? Propose it. Chumbucket reviews it, then it’s published on Panta.',
            actionLabel: 'Create a market',
            onAction: _create,
          ),
        ],
      );
    }
    return _list(c.mine);
  }

  Widget _queue() {
    final c = _controller;
    final q = c.queue;
    if (c.loadingQueue && q == null) return const CallsLoadingView(rows: 2);
    if (q == null && c.queueError != null) {
      return ListView(
        children: [
          CallsErrorView(message: c.queueError!, onRetry: c.loadQueue),
        ],
      );
    }
    final pending = q?.pending ?? const [];
    final approved = q?.approved ?? const [];
    if (pending.isEmpty && approved.isEmpty) {
      return ListView(
        children: const [
          CallsEmptyView(
            artwork: ChumbucketStateArtwork.success,
            title: 'Nothing to review',
            message: 'New market proposals show up here.',
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (pending.isNotEmpty) _heading('Waiting for review'),
        for (final p in pending) _tile(p),
        if (approved.isNotEmpty) _heading('Approved, not yet live'),
        for (final p in approved) _tile(p),
      ],
    );
  }

  Widget _list(List<MarketProposal> rows) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
    children: [for (final p in rows) _tile(p), const PoweredByPanta()],
  );

  Widget _tile(MarketProposal p) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ProposalTile(proposal: p, onTap: () => _openProposal(p.id)),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: AppTextStyles.textTheme.titleMedium),
    ),
  );
}
