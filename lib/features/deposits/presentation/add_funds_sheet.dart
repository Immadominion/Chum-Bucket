import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show
        CallJourneyButton,
        CallJourneyChoice,
        CallJourneyFact,
        CallJourneyNote,
        callJourneyBody,
        callJourneyHeading;
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_dependencies.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_prompt.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../add_funds_controller.dart';
import '../data/deposits_client.dart';
import '../data/deposits_models.dart';
import 'add_funds_widgets.dart';
import 'crossmint_checkout_screen.dart';
import 'deposit_copy.dart';
import 'deposits_dependencies.dart';

/// Opens Add funds. Resolves true when USDC arrived during this visit.
///
/// [requiredUsdcBaseUnits] is what a trade in progress needs; the sheet then
/// shows the gap against the wallet's real balance and suggests an amount
/// that covers it. [fundWallet] is the wallet that trade spends from: funds
/// go there when the account has proven it (the server re-checks).
Future<bool> showAddFundsSheet(
  BuildContext context, {
  BigInt? requiredUsdcBaseUnits,
  String? fundWallet,
}) async {
  final deps = DepositsDependencies.of(context);
  if (deps == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Adding funds isn\'t available in this version.'),
      ),
    );
    return false;
  }
  final added = await showChumbucketWavySheet<bool>(
    context: context,
    builder:
        (_) => AddFundsSheetHost(
          dependencies: deps,
          requiredUsdcBaseUnits: requiredUsdcBaseUnits,
          fundWallet: fundWallet,
        ),
  );
  return added ?? false;
}

/// Owns one visit: the client and controller live and die with the sheet.
/// A payment still in flight survives closing it (see DepositOrderMemory).
class AddFundsSheetHost extends StatefulWidget {
  const AddFundsSheetHost({
    super.key,
    required this.dependencies,
    this.requiredUsdcBaseUnits,
    this.fundWallet,
  });

  final DepositsDependencies dependencies;
  final BigInt? requiredUsdcBaseUnits;
  final String? fundWallet;

  @override
  State<AddFundsSheetHost> createState() => _AddFundsSheetHostState();
}

class _AddFundsSheetHostState extends State<AddFundsSheetHost> {
  late final DepositsClient _client = widget.dependencies.createClient();
  late final AddFundsController _controller = AddFundsController(
    client: _client,
    walletSource: widget.dependencies.walletSource,
    memory: widget.dependencies.memory,
    accountId: widget.dependencies.accountId,
    requiredUsdcBaseUnits: widget.requiredUsdcBaseUnits,
    preferredWallet: widget.fundWallet,
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
  Widget build(BuildContext context) => AddFundsSheet(
    controller: _controller,
    openCheckout: widget.dependencies.openCheckout ?? pushCrossmintCheckout,
  );
}

class AddFundsSheet extends StatefulWidget {
  const AddFundsSheet({
    super.key,
    required this.controller,
    this.openCheckout = pushCrossmintCheckout,
  });

  final AddFundsController controller;
  final DepositCheckoutOpener openCheckout;

  @override
  State<AddFundsSheet> createState() => _AddFundsSheetState();
}

class _AddFundsSheetState extends State<AddFundsSheet> {
  final _custom = TextEditingController();
  final _customFocus = FocusNode();
  final _email = TextEditingController();
  final _scroll = ScrollController();
  late AddFundsStage _lastStage;

  AddFundsController get c => widget.controller;
  bool get _forTrade => c.requiredUsdcBaseUnits != null;

  /// Whether "Get SOL for fees" exists on this server, for the copy only.
  bool _swapForSol = SolTopUpAvailability.cached?.available ?? false;

  @override
  void initState() {
    super.initState();
    _lastStage = c.stage;
    c.addListener(_changed);
    final topUp = SolTopUpDependencies.of(context);
    if (topUp != null && !_swapForSol) {
      unawaited(
        SolTopUpAvailability.read(topUp).then((status) {
          if (mounted && (status?.available ?? false)) {
            setState(() => _swapForSol = true);
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _custom.dispose();
    _customFocus.dispose();
    _email.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (c.stage != _lastStage) {
      _lastStage = c.stage;
      // A new stage starts at its top: its headline is the news.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    if (c.isCustomAmount &&
        _custom.text != c.customText &&
        !_customFocus.hasFocus) {
      _custom.text = c.customText;
    }
    setState(() {});
  }

  void _close() =>
      Navigator.of(context).pop(c.stage == AddFundsStage.delivered);

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    final ok = await c.startCheckout();
    if (!ok || !mounted) return;
    // Crossmint can ask the receiving wallet to sign before anyone pays. The
    // sheet collects that signature first; the checkout opens after it.
    if (c.stage == AddFundsStage.walletProof) return;
    await _showCheckout();
  }

  Future<void> _sign() async {
    final signed = await c.signOwnershipProof();
    if (!signed || !mounted) return;
    // Signed and accepted: carry straight on to paying when the order allows.
    if (c.stage != AddFundsStage.walletProof &&
        c.canReturnToCheckout &&
        !c.isCheckoutOpen) {
      await _showCheckout();
    }
  }

  Future<void> _showCheckout() async {
    if (c.checkoutUri == null) return;
    c.checkoutOpened();
    try {
      await widget.openCheckout(context, c);
    } finally {
      if (mounted) unawaited(c.checkoutClosed());
    }
  }

  Future<void> _openExplorer(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* Nothing to recover: the receipt is the on-screen state. */
    }
  }

  // ── header ───────────────────────────────────────────────────────────────

  (String, String?, String?) get _header {
    final order = c.order;
    return switch (c.stage) {
      AddFundsStage.choose || AddFundsStage.starting => (
        'Add funds',
        c.amount?.label ?? '\$0',
        _forTrade ? 'Top up for this trade' : 'Card, Apple Pay or Google Pay',
      ),
      AddFundsStage.checkout ||
      AddFundsStage.tracking ||
      AddFundsStage.walletProof => (
        'Adding funds',
        order?.totalUsd != null ? '\$${order!.totalUsd}' : c.amount?.label,
        null,
      ),
      AddFundsStage.delivered => (
        order?.isDevnet ?? false ? 'Test funds added' : 'Funds added',
        order?.receiveLabel != null
            ? '+${order!.receiveLabel} ${order.isDevnet ? 'test ' : ''}USDC'
            : null,
        null,
      ),
      AddFundsStage.failed => ('Payment didn\'t finish', null, null),
      _ => ('Add funds', null, null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, value, subtitle) = _header;
    return ChumbucketWavySheet(
      title: title,
      value: value,
      subtitle: subtitle,
      canDismiss: !c.busy,
      onClose: _close,
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: DefaultTextStyle(
          style: callJourneyBody(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: switch (c.stage) {
              AddFundsStage.loading => _loading(),
              AddFundsStage.signedOut => _signedOut(),
              AddFundsStage.unavailable => _unavailable(),
              AddFundsStage.choose || AddFundsStage.starting => _choose(),
              AddFundsStage.checkout ||
              AddFundsStage.tracking ||
              AddFundsStage.walletProof => _progress(),
              AddFundsStage.delivered => _delivered(),
              AddFundsStage.failed => _failed(),
            },
          ),
        ),
      ),
    );
  }

  // ── stages ───────────────────────────────────────────────────────────────

  Widget _balance() => DepositBalanceCard(
    address: c.destination,
    balance: c.balance,
    loading: c.balanceLoading,
    error: c.balanceError,
    available: c.status?.balanceAvailable ?? true,
    onRefresh: c.refreshBalance,
  );

  List<Widget> _loading() => [
    const DepositBalanceCard(
      address: null,
      balance: null,
      loading: true,
      error: null,
      onRefresh: null,
    ),
    const SizedBox(height: 20),
    Semantics(
      liveRegion: true,
      child: Text(
        'Checking how you can pay…',
        textAlign: TextAlign.center,
        style: callJourneyBody(13),
      ),
    ),
    const SizedBox(height: 12),
  ];

  List<Widget> _signedOut() => [
    const Center(
      child: ChumbucketStateArt.compact(ChumbucketStateArtwork.access),
    ),
    const SizedBox(height: 8),
    Text(
      'Sign in to add funds',
      textAlign: TextAlign.center,
      style: callJourneyHeading(context, 20),
    ),
    const SizedBox(height: 6),
    Text(
      'Funds go to the wallet on your Chumbucket account, so we need to know it\'s you.',
      textAlign: TextAlign.center,
      style: callJourneyBody(),
    ),
    const SizedBox(height: 20),
    ChumbucketPrimaryButton(
      label: 'Sign in',
      onPressed: () async {
        await showChumbucketWavySheet<void>(
          context: context,
          builder: (_) => const ChumbucketSignInSheet(),
        );
        // Back from signing in: read the account again, here, in place.
        if (mounted) unawaited(c.load());
      },
    ),
  ];

  List<Widget> _unavailable() {
    final wallets = c.status?.account?.wallets ?? const [];
    final destination = c.destination;
    final retryable =
        c.statusError != null &&
        (c.statusError!.kind == DepositsErrorKind.connection ||
            c.statusError!.kind == DepositsErrorKind.provider ||
            c.statusError!.kind == DepositsErrorKind.invalidResponse);
    return [
      if (wallets.isNotEmpty) ...[_balance(), const SizedBox(height: 16)],
      DepositStatusCard(
        copy: DepositStateCopy(
          retryable
              ? 'We couldn\'t reach Chumbucket'
              : wallets.isEmpty && c.status?.account != null
              ? 'Your account needs a wallet first'
              : 'Card payments aren\'t available right now',
          c.unavailableMessage ?? 'Adding funds isn\'t available right now.',
          retryable ? 'globe-outline' : 'info-circle-outline',
        ),
      ),
      if (destination != null && wallets.isNotEmpty) ...[
        const SizedBox(height: 16),
        DepositReceivePanel(address: destination, initiallyOpen: true),
      ],
      const SizedBox(height: 20),
      if (retryable) ...[
        ChumbucketPrimaryButton(label: 'Try again', onPressed: c.load),
        const SizedBox(height: 4),
        ChumbucketTextAction(
          label: 'Close',
          onPressed: _close,
          color: AppColors.textSecondary,
        ),
      ] else
        ChumbucketPrimaryButton(label: 'Done', onPressed: _close),
    ];
  }

  List<Widget> _choose() {
    final starting = c.stage == AddFundsStage.starting;
    final gap = c.shortfallBaseUnits;
    final need = c.requiredUsdcBaseUnits;
    final status = c.status;
    return [
      if (c.localWalletNotLinked && c.destination != null)
        CallJourneyNote(
          'Funds go to your account\'s wallet ${shortAddress(c.destination!)}, '
          '${c.preferredWallet != null ? 'not the wallet this trade uses' : 'not the wallet connected on this phone'}.',
          icon: 'info-circle-outline',
        ),
      _balance(),
      if (c.needsSol) ...[
        const SizedBox(height: 12),
        CallJourneyNote(
          _swapForSol
              ? 'This wallet has no SOL, and every trade needs a little for '
                  'network fees. A card buys USDC only — once it lands, you '
                  'can swap about \$1 of it for SOL right here, with the fee '
                  'paid for you.'
              : 'This wallet has no SOL, and every trade needs a little for '
                  'network fees. A card here buys USDC only, so send some SOL '
                  'from another wallet or an exchange. Your address is at the '
                  'bottom.',
          key: const ValueKey('deposit-needs-sol'),
          icon: 'info-circle-outline',
        ),
      ],
      if (need != null && gap != null && gap > BigInt.zero) ...[
        const SizedBox(height: 12),
        CallJourneyNote(
          'This trade needs ${formatBaseUnits(need, usdcDecimals)} USDC. '
          'You have ${c.balance!.usdcLabel}, so add at least '
          '${formatBaseUnits(gap, usdcDecimals)} USDC.',
          icon: 'info-circle-outline',
        ),
      ] else if (need != null && gap == BigInt.zero) ...[
        const SizedBox(height: 12),
        const CallJourneyNote(
          'You already have enough USDC for this trade. You can add more anyway.',
          icon: 'check-outline',
          quiet: true,
        ),
      ],
      const SizedBox(height: 20),
      Text('How much?', style: callJourneyHeading(context, 16)),
      const SizedBox(height: 10),
      DepositAmountChoices(
        children: [
          for (final preset in c.presets)
            CallJourneyChoice(
              key: ValueKey('deposit-preset-${preset.wire}'),
              label: preset.label,
              selected: !c.isCustomAmount && c.amount == preset,
              onTap: starting ? null : () => c.selectPreset(preset),
            ),
        ],
      ),
      const SizedBox(height: 2),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _rangeText,
            style: callJourneyBody(12).copyWith(color: AppColors.textTertiary),
          ),
          if (!c.isCustomAmount)
            TextButton.icon(
              key: const ValueKey('deposit-preset-other'),
              onPressed:
                  starting
                      ? null
                      : () {
                        c.useCustomAmount();
                        _custom.text = c.customText;
                        _customFocus.requestFocus();
                      },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: callJourneyBody(
                  13,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              icon: const BasilIcon('edit-outline', size: 16),
              label: const Text('Other amount'),
            ),
        ],
      ),
      if (c.isCustomAmount) ...[
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('deposit-custom-amount'),
          controller: _custom,
          focusNode: _customFocus,
          enabled: !starting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?')),
          ],
          onChanged: c.editCustomAmount,
          style: callJourneyHeading(context, 22),
          decoration: _inputDecoration(
            label: 'Amount in US dollars',
            prefix: '\$ ',
            error:
                _custom.text.isNotEmpty && !c.amountInRange
                    ? _rangeError
                    : null,
          ),
        ),
      ],
      if (c.needsEmail) ...[
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('deposit-email'),
          controller: _email,
          enabled: !starting,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: c.editEmail,
          decoration: _inputDecoration(
            label: 'Email for your receipt',
            helper:
                'Crossmint emails your receipt here. Chumbucket doesn\'t keep it.',
            error:
                _email.text.isNotEmpty && !c.emailValid
                    ? 'Check this email address.'
                    : null,
          ),
        ),
      ],
      const SizedBox(height: 16),
      _quoteCard(),
      if (status?.isTestMode ?? false) ...[
        const SizedBox(height: 12),
        const CallJourneyNote(
          'Test mode, not real money. Pay with card 4242 4242 4242 4242, any future date and CVC. '
          'Crossmint sends devnet test USDC, which won\'t show up in your trading balance.',
          icon: 'info-rect-outline',
          quiet: true,
        ),
      ],
      if (c.error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: CallJourneyNote(
            c.error!.message,
            key: const ValueKey('deposit-error'),
            icon: 'info-triangle-outline',
            error: true,
          ),
        ),
      ],
      const SizedBox(height: 16),
      ChumbucketPrimaryButton(
        key: const ValueKey('deposit-continue'),
        label: 'Continue to payment',
        busy: starting,
        busyLabel: 'Opening secure checkout…',
        leading: const BasilIcon('lock-solid', size: 18),
        onPressed: c.canStart ? _continue : null,
      ),
      const SizedBox(height: 12),
      const DepositPaymentMethods(),
      const SizedBox(height: 10),
      Text(
        'Payments by Crossmint. Your card and ID details go to Crossmint, never to Chumbucket.',
        textAlign: TextAlign.center,
        style: callJourneyBody(11).copyWith(color: AppColors.textTertiary),
      ),
      if (c.destination != null) ...[
        const SizedBox(height: 16),
        DepositReceivePanel(
          // Re-mounts open once the balance shows the wallet has no SOL.
          key: ValueKey('deposit-receive-${c.needsSol}'),
          address: c.destination!,
          initiallyOpen: c.needsSol,
        ),
      ],
    ];
  }

  /// Short enough to share a line with "Other amount".
  String get _rangeText {
    final lo = c.minAmount, hi = c.maxAmount;
    return lo == null || hi == null
        ? 'Choose an amount.'
        : '${lo.label}–${hi.label} per payment';
  }

  String get _rangeError {
    final lo = c.minAmount, hi = c.maxAmount;
    return lo == null || hi == null
        ? 'Choose an amount.'
        : 'Choose from ${lo.label} to ${hi.label}.';
  }

  Widget _quoteCard() {
    final quote = c.quote;
    final waiting = c.quoteLoading;
    final pay =
        quote?.totalUsd != null
            ? '\$${quote!.totalUsd}'
            : waiting
            ? 'Getting a price…'
            : c.amount?.label ?? '—';
    final test = c.status?.isTestMode ?? false;
    final get =
        quote?.receiveLabel != null
            ? '≈ ${quote!.receiveLabel} ${test ? 'test ' : ''}USDC'
            : waiting
            ? 'Getting a price…'
            : 'Shown at checkout';
    final to = c.destination;
    return Container(
      key: const ValueKey('deposit-quote'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallJourneyFact('You pay', pay),
          CallJourneyFact('You get', get),
          if (quote?.networkFeeUsd != null)
            CallJourneyFact(
              'Network fee',
              '\$${quote!.networkFeeUsd} (included)',
            ),
          if (to != null)
            CallJourneyFact(
              'Goes to',
              'Your wallet ${shortAddress(to)} on Solana',
            ),
          if (c.status?.account?.receiptEmail != null)
            CallJourneyFact('Receipt', c.status!.account!.receiptEmail!),
          if (c.quoteError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                c.quoteError!.message,
                key: const ValueKey('deposit-quote-error'),
                style: callJourneyBody(
                  12,
                ).copyWith(color: AppColors.onErrorContainer),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Crossmint\'s price includes its fees. The exact USDC is fixed when you pay.',
                style: callJourneyBody(
                  11,
                ).copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _progress() {
    final order = c.order;
    if (order == null) return _loading();
    final proof = c.stage == AddFundsStage.walletProof;
    final canStartOver = switch (order.state) {
      DepositOrderState.awaitingPayment ||
      DepositOrderState.paymentFailed ||
      DepositOrderState.verifyingIdentity ||
      DepositOrderState.awaitingWalletProof => true,
      _ => false,
    };
    // A payment picked up from an earlier visit has no checkout link (its
    // client secret is never kept). Once it is payable again, e.g. after an
    // identity review, the honest next step is a fresh payment.
    final checkoutGone = canStartOver && !proof && !c.canReturnToCheckout;
    final copy =
        checkoutGone
            ? const DepositStateCopy(
              'Start a new payment to finish',
              'This payment\'s checkout closed before you paid, so nothing '
                  'was charged. A new payment picks up from here.',
              'card-outline',
              tone: DepositTone.waiting,
            )
            : depositStateCopy(order);
    return [
      DepositSteps(state: order.state),
      const SizedBox(height: 16),
      DepositStatusCard(copy: copy),
      if (proof) ...[
        const SizedBox(height: 16),
        if (c.canSignProof)
          ChumbucketPrimaryButton(
            key: const ValueKey('deposit-sign-proof'),
            label: 'Sign with your wallet',
            busy: c.busy,
            busyLabel: 'Waiting for your wallet…',
            onPressed: _sign,
          )
        else
          CallJourneyNote(
            'Open Chumbucket with the wallet ending '
            '${order.recipient.substring(order.recipient.length - 4)} connected, then come back here to sign.',
            icon: 'lock-outline',
          ),
      ] else if (c.canReturnToCheckout) ...[
        const SizedBox(height: 16),
        ChumbucketPrimaryButton(
          key: const ValueKey('deposit-return-checkout'),
          label:
              order.state == DepositOrderState.paymentFailed
                  ? 'Try another payment method'
                  : c.checkoutSeen
                  ? 'Return to checkout'
                  : 'Continue to payment',
          leading: const BasilIcon('lock-solid', size: 18),
          onPressed: _showCheckout,
        ),
      ] else if (checkoutGone) ...[
        const SizedBox(height: 16),
        ChumbucketPrimaryButton(
          key: const ValueKey('deposit-start-new'),
          label: 'Start a new payment',
          onPressed: c.startOver,
        ),
      ],
      if (c.pollGaveUp) ...[
        const SizedBox(height: 12),
        const CallJourneyNote(
          'Crossmint hasn\'t updated this payment in a while. Your money is safe either way.',
          icon: 'clock-outline',
          quiet: true,
        ),
        CallJourneyButton(
          label: 'Check again',
          icon: 'refresh-outline',
          onPressed: c.resumeChecking,
        ),
      ],
      if (c.error != null) ...[
        const SizedBox(height: 12),
        CallJourneyNote(
          c.error!.message,
          key: const ValueKey('deposit-error'),
          icon: 'info-triangle-outline',
          error: true,
        ),
      ],
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (order.totalUsd != null)
              CallJourneyFact('You pay', '\$${order.totalUsd}'),
            if (order.receiveLabel != null)
              CallJourneyFact(
                'You get',
                order.state.isInFlight ||
                        order.state == DepositOrderState.delivered
                    ? '${order.receiveLabel} ${order.isDevnet ? 'test ' : ''}USDC'
                    : '≈ ${order.receiveLabel} ${order.isDevnet ? 'test ' : ''}USDC',
              ),
            CallJourneyFact(
              'Goes to',
              'Your wallet ${shortAddress(order.recipient)}${order.isDevnet ? ' (devnet)' : ''}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'You can close this. We\'ll keep track of this payment and show where it is next time you open Add funds.',
        textAlign: TextAlign.center,
        style: callJourneyBody(12).copyWith(color: AppColors.textTertiary),
      ),
      if (canStartOver && !checkoutGone && !c.busy) ...[
        const SizedBox(height: 4),
        ChumbucketTextAction(
          label: 'Start a new payment',
          onPressed: c.startOver,
          color: AppColors.textSecondary,
        ),
      ],
    ];
  }

  List<Widget> _delivered() {
    final order = c.order;
    final explorer = order?.explorerUri;
    return [
      const Center(
        child: ChumbucketStateArt.compact(ChumbucketStateArtwork.success),
      ),
      const SizedBox(height: 4),
      Semantics(
        liveRegion: true,
        child: Text(
          order?.isDevnet ?? false
              ? order!.receiveLabel != null
                  ? '${order.receiveLabel} test USDC landed in your wallet.'
                  : 'Test USDC landed in your wallet.'
              : order?.receiveLabel != null
              ? '${order!.receiveLabel} USDC landed in your wallet.'
              : 'Your USDC landed in your wallet.',
          key: const ValueKey('deposit-delivered'),
          textAlign: TextAlign.center,
          style: callJourneyHeading(context, 18),
        ),
      ),
      const SizedBox(height: 4),
      // "Ready" only when it's true: a trade also pays a SOL network fee,
      // and a card payment never adds SOL.
      Text(
        c.needsSol
            ? 'One more step before you trade: add a little SOL for network fees.'
            : _forTrade
            ? 'You\'re ready to place your trade.'
            : 'You\'re ready to back your calls.',
        key: const ValueKey('deposit-delivered-next'),
        textAlign: TextAlign.center,
        style: callJourneyBody(),
      ),
      const SizedBox(height: 16),
      _balance(),
      // SOL for fees from the USDC that just landed (Jupiter pays the swap's
      // network fee). Where swaps are off, the old path: send SOL in.
      if (c.destination != null)
        SolTopUpPrompt(
          key: ValueKey('deposit-sol-topup-${c.destination}'),
          wallet: c.destination,
          onToppedUp: c.refreshBalance,
          fallback:
              c.needsSol
                  ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DepositReceivePanel(
                      address: c.destination!,
                      initiallyOpen: true,
                      title: 'Add SOL for network fees',
                      subtitle:
                          'Send a little SOL from another wallet or an exchange.',
                    ),
                  )
                  : null,
        ),
      if (order?.isDevnet ?? false) ...[
        const SizedBox(height: 12),
        const CallJourneyNote(
          'Test money, not real: this was devnet test USDC, so your mainnet balance above doesn\'t include it.',
          icon: 'info-rect-outline',
          quiet: true,
        ),
      ],
      if (explorer != null)
        Align(
          child: TextButton.icon(
            key: const ValueKey('deposit-explorer'),
            onPressed: () => _openExplorer(explorer),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(48, 48),
              textStyle: callJourneyBody(
                13,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            icon: const BasilIcon('globe-outline', size: 16),
            label: const Text('View on Solana Explorer'),
          ),
        ),
      const SizedBox(height: 12),
      ChumbucketPrimaryButton(
        key: const ValueKey('deposit-done'),
        label: _forTrade ? 'Back to your trade' : 'Done',
        onPressed: _close,
      ),
      ChumbucketTextAction(
        label: 'Add more',
        onPressed: c.startOver,
        color: AppColors.textSecondary,
      ),
    ];
  }

  List<Widget> _failed() {
    final order = c.order;
    final identity = order?.state == DepositOrderState.identityFailed;
    return [
      const Center(
        child: ChumbucketStateArt.compact(ChumbucketStateArtwork.error),
      ),
      const SizedBox(height: 8),
      if (order != null) DepositStatusCard(copy: depositStateCopy(order)),
      if (identity && c.destination != null) ...[
        const SizedBox(height: 16),
        DepositReceivePanel(address: c.destination!),
      ],
      const SizedBox(height: 20),
      if (identity)
        ChumbucketPrimaryButton(label: 'Done', onPressed: _close)
      else ...[
        ChumbucketPrimaryButton(
          key: const ValueKey('deposit-try-again'),
          label: 'Try again',
          onPressed: c.startOver,
        ),
        ChumbucketTextAction(
          label: 'Close',
          onPressed: _close,
          color: AppColors.textSecondary,
        ),
      ],
    ];
  }

  InputDecoration _inputDecoration({
    required String label,
    String? prefix,
    String? helper,
    String? error,
  }) => InputDecoration(
    labelText: label,
    labelStyle: callJourneyBody(13),
    prefixText: prefix,
    prefixStyle: callJourneyHeading(context, 22),
    helperText: helper,
    helperMaxLines: 2,
    helperStyle: callJourneyBody(11),
    errorText: error,
    filled: true,
    fillColor: const Color(0xFFF6F7F9),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE6E9ED)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE6E9ED)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.textPrimary, width: 1.5),
    ),
  );
}
