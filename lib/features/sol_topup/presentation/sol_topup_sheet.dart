/// "SOL for fees": swap a little of the person's own USDC into SOL through
/// Jupiter, with the network fee paid by Jupiter or the quoting market maker,
/// so a wallet with 0 SOL can trade. Reviewed in plain words, checked on this
/// phone, signed by the person's own wallet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show
        CallJourneyChoice,
        CallJourneyFact,
        CallJourneyNote,
        callJourneyBody,
        callJourneyHeading;
import 'package:chumbucket/features/deposits/data/deposits_models.dart'
    show shortAddress;
import 'package:chumbucket/features/deposits/presentation/add_funds_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_widgets.dart'
    show DepositAmountChoices, DepositReceivePanel;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/sol_topup_models.dart';
import '../domain/sol_topup_signer.dart';
import '../sol_topup_controller.dart';
import 'sol_topup_dependencies.dart';

/// Opens "SOL for fees" for [wallet] (null: the account's own wallet, as the
/// server picks it). Resolves true when SOL landed during this visit.
Future<bool> showSolTopUpSheet(BuildContext context, {String? wallet}) async {
  final deps = SolTopUpDependencies.of(context);
  if (deps == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Swapping for SOL isn’t available in this version.'),
      ),
    );
    return false;
  }
  final landed = await showChumbucketWavySheet<bool>(
    context: context,
    builder: (_) => SolTopUpSheetHost(dependencies: deps, wallet: wallet),
  );
  return landed ?? false;
}

/// Owns one visit: the client and controller live and die with the sheet.
class SolTopUpSheetHost extends StatefulWidget {
  const SolTopUpSheetHost({super.key, required this.dependencies, this.wallet});
  final SolTopUpDependencies dependencies;
  final String? wallet;

  @override
  State<SolTopUpSheetHost> createState() => _SolTopUpSheetHostState();
}

class _SolTopUpSheetHostState extends State<SolTopUpSheetHost> {
  late final _client = widget.dependencies.createClient();
  late final _controller = SolTopUpController(
    client: _client,
    signerFor: widget.dependencies.signerFor,
    wallet: widget.wallet,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SolTopUpSheet(controller: _controller);
}

class SolTopUpSheet extends StatefulWidget {
  const SolTopUpSheet({super.key, required this.controller});
  final SolTopUpController controller;

  @override
  State<SolTopUpSheet> createState() => _SolTopUpSheetState();
}

class _SolTopUpSheetState extends State<SolTopUpSheet> {
  SolTopUpController get c => widget.controller;
  final _scroll = ScrollController();
  late SolTopUpStage _last = c.stage;

  bool get _onPhone => c.signer?.kind == TopUpSignerKind.thisPhone;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (c.stage != _last) {
      _last = c.stage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    setState(() {});
  }

  void _close() => Navigator.of(context).pop(c.stage == SolTopUpStage.done);

  (String, String?) get _header {
    final review = c.order?.review;
    return switch (c.stage) {
      SolTopUpStage.review ||
      SolTopUpStage.signing ||
      SolTopUpStage.sending => (
        'You get about',
        review == null ? null : '${solLabel(review.solOutLamports)} SOL',
      ),
      SolTopUpStage.done => (
        'SOL added',
        c.result?.solReceivedLamports != null
            ? '+${solLabel(c.result!.solReceivedLamports!)} SOL'
            : null,
      ),
      _ => ('SOL for fees', null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, value) = _header;
    return ChumbucketWavySheet(
      title: title,
      value: value,
      subtitle:
          c.stage == SolTopUpStage.done || c.stage == SolTopUpStage.failed
              ? null
              : 'Your own USDC, swapped by Jupiter',
      canDismiss: c.canDismiss,
      onClose: _close,
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: DefaultTextStyle(
          style: callJourneyBody(),
          child: Column(
            key: ValueKey('sol-topup-stage-${c.stage.name}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: switch (c.stage) {
              SolTopUpStage.loading => _loading(),
              SolTopUpStage.unavailable => _unavailable(),
              SolTopUpStage.notNeeded => _notNeeded(),
              SolTopUpStage.needsUsdc => _needsUsdc(),
              SolTopUpStage.noSigner => _noSigner(),
              SolTopUpStage.choose || SolTopUpStage.preparing => _choose(),
              SolTopUpStage.review ||
              SolTopUpStage.signing ||
              SolTopUpStage.sending => _review(),
              SolTopUpStage.done => _done(),
              SolTopUpStage.failed => _failed(),
            },
          ),
        ),
      ),
    );
  }

  // ── pieces ───────────────────────────────────────────────────────────────

  Widget _balanceLine() {
    final p = c.plan;
    if (p == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('sol-topup-balance'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const BasilIcon(
            'wallet-outline',
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your wallet ${shortAddress(p.wallet)} · '
              '${usdcLabel(p.usdcBaseUnits)} USDC · '
              '${solLabel(p.lamports)} SOL',
              style: callJourneyBody(13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _why() {
    final p = c.plan!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Trades on Panta pay their Solana network fee in SOL — about '
        '${solLabel(p.perTradeLamports)} SOL the first time you trade a '
        'market, most of it account rent. '
        '${p.tradesCoveredNow == 0 ? 'This wallet doesn’t have enough SOL for one yet.' : 'This wallet has enough for about ${p.tradesCoveredNow} more.'}',
        style: callJourneyBody(13),
      ),
    );
  }

  Widget _messageNote() =>
      c.message == null
          ? const SizedBox.shrink()
          : Semantics(
            liveRegion: true,
            child: CallJourneyNote(
              c.message!,
              key: const ValueKey('sol-topup-message'),
              icon: 'info-triangle-outline',
              error: true,
            ),
          );

  Widget _receive() {
    // The server's read first; before any read (swaps off), the wallet this
    // sheet was opened for, so "send SOL yourself" always has an address.
    final wallet = c.plan?.wallet ?? c.order?.review.wallet ?? c.wallet;
    if (wallet == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DepositReceivePanel(
        address: wallet,
        title: 'Or send SOL yourself',
        subtitle: 'From another wallet or an exchange, on Solana.',
      ),
    );
  }

  List<Widget> _loading() => [
    Semantics(
      liveRegion: true,
      child: Text(
        'Checking your wallet…',
        textAlign: TextAlign.center,
        style: callJourneyBody(13),
      ),
    ),
    const SizedBox(height: 12),
    const LinearProgressIndicator(minHeight: 2),
    const SizedBox(height: 12),
  ];

  List<Widget> _unavailable() => [
    CallJourneyNote(
      c.message ?? 'Swapping USDC for SOL isn’t available right now.',
      key: const ValueKey('sol-topup-unavailable'),
      icon: 'info-circle-outline',
    ),
    Text(
      'You can still send a little SOL to your wallet from another wallet '
      'or an exchange.',
      style: callJourneyBody(13),
    ),
    _receive(),
    const SizedBox(height: 16),
    ChumbucketPrimaryButton(label: 'Done', onPressed: _close),
  ];

  List<Widget> _notNeeded() {
    final p = c.plan;
    return [
      const Center(
        child: ChumbucketStateArt.compact(ChumbucketStateArtwork.success),
      ),
      Text(
        p == null
            ? 'This wallet already has SOL for network fees.'
            : 'This wallet has SOL for about ${p.tradesCoveredNow} new '
                'trades. No swap needed.',
        key: const ValueKey('sol-topup-not-needed'),
        textAlign: TextAlign.center,
        style: callJourneyHeading(context, 17),
      ),
      const SizedBox(height: 12),
      _balanceLine(),
      const SizedBox(height: 16),
      ChumbucketPrimaryButton(label: 'Done', onPressed: _close),
    ];
  }

  List<Widget> _needsUsdc() {
    final p = c.plan;
    return [
      _balanceLine(),
      if (p != null) _why(),
      const SizedBox(height: 12),
      CallJourneyNote(
        c.message ??
            'The swap uses about \$${usdcLabel(p?.minBaseUnits ?? BigInt.from(1000000))} '
                'of your USDC, and this wallet has less. Add funds first, '
                'then come back.',
        key: const ValueKey('sol-topup-needs-usdc'),
        icon: 'info-circle-outline',
      ),
      const SizedBox(height: 4),
      ChumbucketPrimaryButton(
        label: 'Add funds',
        leading: const BasilIcon('add-outline', size: 18),
        onPressed: () async {
          final added = await showAddFundsSheet(context, fundWallet: p?.wallet);
          if (added && mounted) unawaited(c.load());
        },
      ),
      ChumbucketTextAction(
        label: 'Not now',
        color: AppColors.textSecondary,
        onPressed: _close,
      ),
      _receive(),
    ];
  }

  List<Widget> _noSigner() {
    final p = c.plan;
    final end =
        p == null ? '' : ' ending ${p.wallet.substring(p.wallet.length - 4)}';
    return [
      _balanceLine(),
      if (p != null) _why(),
      const SizedBox(height: 12),
      CallJourneyNote(
        'To swap, this phone needs the wallet$end: connect it in your '
        'wallet app, or open the wallet on this phone and link it to your '
        'account. Then come back here.',
        key: const ValueKey('sol-topup-no-signer'),
        icon: 'lock-outline',
      ),
      ChumbucketPrimaryButton(label: 'Done', onPressed: _close),
      _receive(),
    ];
  }

  List<Widget> _choose() {
    final p = c.plan!;
    final preparing = c.stage == SolTopUpStage.preparing;
    final options = c.amountOptions;
    final s = p.suggestion;
    final isSuggested = s != null && c.amount == s.amountBaseUnits;
    return [
      _balanceLine(),
      _why(),
      const SizedBox(height: 16),
      Text('Swap from your USDC', style: callJourneyHeading(context, 16)),
      const SizedBox(height: 10),
      DepositAmountChoices(
        children: [
          for (final option in options)
            CallJourneyChoice(
              key: ValueKey('sol-topup-amount-$option'),
              label: '\$${usdcLabel(option)}',
              selected: c.amount == option,
              onTap: preparing ? null : () => c.selectAmount(option),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (isSuggested)
        CallJourneyNote(
          'About ${solLabel(s.estimatedLamports)} SOL at today’s price — '
          'enough for about ${s.tradesCovered} new trades. Jupiter pays the '
          'network fee, so it works with 0 SOL.',
          key: const ValueKey('sol-topup-estimate'),
          icon: 'check-outline',
          quiet: true,
        )
      else
        const CallJourneyNote(
          'You’ll see exactly how much SOL you get before you sign. Jupiter '
          'pays the network fee, so it works with 0 SOL.',
          icon: 'info-circle-outline',
          quiet: true,
        ),
      _messageNote(),
      const SizedBox(height: 4),
      ChumbucketPrimaryButton(
        key: const ValueKey('sol-topup-get-quote'),
        label: 'Review swap',
        busy: preparing,
        busyLabel: 'Getting a quote…',
        onPressed: c.amount == null || preparing ? null : c.prepare,
      ),
      ChumbucketTextAction(
        label: 'Not now',
        color: AppColors.textSecondary,
        onPressed: preparing ? null : _close,
      ),
      _receive(),
    ];
  }

  List<Widget> _review() {
    final order = c.order!;
    final r = order.review;
    final checked = c.checked!;
    final signing = c.stage == SolTopUpStage.signing;
    final sending = c.stage == SolTopUpStage.sending;
    final fee = r.feeBps / 100;
    return [
      Container(
        key: const ValueKey('sol-topup-review'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CallJourneyFact('You swap', '${usdcLabel(r.usdcInBaseUnits)} USDC'),
            CallJourneyFact(
              'You get',
              'About ${solLabel(r.solOutLamports)} SOL · at least '
                  '${solLabel(checked.minOutLamports)} SOL',
            ),
            CallJourneyFact(
              'Network fee',
              r.paidByJupiter
                  ? 'Paid by Jupiter, not you'
                  : 'Paid by the market maker filling this swap, not you',
            ),
            CallJourneyFact(
              'Jupiter’s fee',
              '${fee.toStringAsFixed(fee < 1 ? 2 : 1)}% · already in the '
                  'amount above',
            ),
            CallJourneyFact('Covers', 'About ${r.tradesCovered} new trades'),
            CallJourneyFact('Goes to', 'Your wallet ${shortAddress(r.wallet)}'),
          ],
        ),
      ),
      const SizedBox(height: 12),
      CallJourneyNote(
        _onPhone
            ? 'Checked on this phone: only your USDC goes out, only SOL comes '
                'back, to this same wallet. Signing with the wallet on this '
                'phone sends this exact swap — there is no second screen.'
            : 'Checked on this phone: only your USDC goes out, only SOL comes '
                'back, to this same wallet. Your wallet app shows the same '
                'swap to approve.',
        icon: 'shield-outline',
        quiet: true,
      ),
      _messageNote(),
      ChumbucketPrimaryButton(
        key: const ValueKey('sol-topup-approve'),
        label: _onPhone ? 'Sign and swap' : 'Approve in wallet',
        busy: signing || sending,
        busyLabel:
            sending
                ? 'Swapping…'
                : _onPhone
                ? 'Signing…'
                : 'Waiting for your wallet…',
        onPressed: c.busy ? null : c.approve,
      ),
      if (!c.busy) ...[
        ChumbucketTextAction(
          label: 'Change amount',
          color: AppColors.textSecondary,
          onPressed: () => c.selectAmount(r.usdcInBaseUnits),
        ),
        Text(
          'Swaps are made by Jupiter on Solana. Prices move: the quote is '
          'good for about a minute.',
          textAlign: TextAlign.center,
          style: callJourneyBody(11).copyWith(color: AppColors.textTertiary),
        ),
      ],
    ];
  }

  List<Widget> _done() {
    final result = c.result;
    final explorer = result?.explorerUri;
    // Jupiter's reported amount when it sent one; otherwise only what the
    // signed swap guaranteed, said as a minimum.
    final exact = result?.solReceivedLamports;
    final atLeast = exact == null ? c.checked?.minOutLamports : null;
    return [
      const Center(
        child: ChumbucketStateArt.compact(ChumbucketStateArtwork.success),
      ),
      Semantics(
        liveRegion: true,
        child: Text(
          exact != null
              ? '${solLabel(exact)} SOL landed in your wallet.'
              : atLeast != null
              ? 'At least ${solLabel(atLeast)} SOL landed in your wallet.'
              : 'SOL landed in your wallet.',
          key: const ValueKey('sol-topup-done'),
          textAlign: TextAlign.center,
          style: callJourneyHeading(context, 18),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'That covers network fees for your next trades.',
        textAlign: TextAlign.center,
        style: callJourneyBody(),
      ),
      if (explorer != null)
        Align(
          child: TextButton.icon(
            key: const ValueKey('sol-topup-explorer'),
            onPressed: () async {
              try {
                await launchUrl(explorer, mode: LaunchMode.externalApplication);
              } catch (_) {
                /* The on-screen state is the receipt. */
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(48, 48),
            ),
            icon: const BasilIcon('globe-outline', size: 16),
            label: const Text('View on Solana Explorer'),
          ),
        ),
      const SizedBox(height: 12),
      ChumbucketPrimaryButton(
        key: const ValueKey('sol-topup-finish'),
        label: 'Done',
        onPressed: _close,
      ),
    ];
  }

  List<Widget> _failed() => [
    const Center(
      child: ChumbucketStateArt.compact(ChumbucketStateArtwork.error),
    ),
    CallJourneyNote(
      c.message ?? 'The swap didn’t go through. Nothing was swapped.',
      key: const ValueKey('sol-topup-failed'),
      icon: c.unknown ? 'clock-outline' : 'info-triangle-outline',
      error: !c.unknown,
    ),
    const SizedBox(height: 4),
    ChumbucketPrimaryButton(
      key: const ValueKey('sol-topup-retry'),
      label: c.unknown ? 'Check my wallet' : 'Try again',
      onPressed: c.load,
    ),
    ChumbucketTextAction(
      label: 'Close',
      color: AppColors.textSecondary,
      onPressed: _close,
    ),
  ];
}
