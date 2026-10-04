/// Add funds, one icon-led sheet (`money.depositOptions`):
///
///  * From your wallet app — a USDC transfer from one of the account's own
///    wallets, one approval (`money.depositFromWalletPrepare`, checked on
///    this phone before the wallet app opens);
///  * Send USDC — the trading wallet's address and its QR, with copy;
///  * Card / Apple Pay / Google Pay through Crossmint, only when the server
///    offers it, and labelled "Test" every time it is staging.
///
/// While it is open it watches the balance (`money.wallet`); when the funds
/// land it closes itself, and a call waiting on them carries on.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallInlineError, callJourneyBody, callJourneyHeading;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_client.dart';
import '../data/money_models.dart';
import '../domain/usdc_transfer_check.dart' show usdcMint;
import '../money_controller.dart';
import '../money_transfer_controller.dart';
import 'money_amount_row.dart' show moneyOf;
import 'money_dependencies.dart';

/// Resolves true when funds landed while it was open.
///
/// [shortfall] is what a call in progress is short by; [target] the balance
/// it needs. Without them, any increase in the balance counts as landed.
Future<bool> showMoneyDepositSheet(
  BuildContext context, {
  BigInt? shortfall,
  BigInt? target,
}) async {
  final deps = MoneyDependencies.of(context);
  if (deps == null) return false;
  final landed = await showChumbucketWavySheet<bool>(
    context: context,
    builder:
        (_) => MoneyDepositSheet(
          dependencies: deps,
          shortfall: shortfall,
          target: target,
          money: moneyOf(context, listen: false),
        ),
  );
  return landed ?? false;
}

enum _Stage { options, sendUsdc, fromWallet }

class MoneyDepositSheet extends StatefulWidget {
  const MoneyDepositSheet({
    super.key,
    required this.dependencies,
    this.shortfall,
    this.target,
    this.money,
  });

  final MoneyDependencies dependencies;
  final BigInt? shortfall;
  final BigInt? target;
  final MoneyController? money;

  @override
  State<MoneyDepositSheet> createState() => _MoneyDepositSheetState();
}

class _MoneyDepositSheetState extends State<MoneyDepositSheet> {
  late final MoneyClient _client = widget.dependencies.createClient();
  late final MoneyTransferController _transfer = MoneyTransferController(
    client: _client,
    kind: MoneyTransferKind.fromWallet,
    signerFor: widget.dependencies.transferSigner,
    topUp: widget.dependencies.gasTopUp,
    pollEvery: widget.dependencies.pollEvery,
  )..addListener(_changed);

  DepositOptions? _options;

  /// The trading wallet as money.wallet reported it: the only destination.
  String? _tradingWallet;
  bool _loading = true;
  String? _loadError;
  BigInt? _baseline;
  Timer? _watch;
  bool _closed = false;

  /// The account has no trading wallet yet: set one up first.
  bool _noWallet = false;
  _Stage _stage = _Stage.options;
  BigInt? _amount;

  @override
  void initState() {
    super.initState();
    _amount = _suggested();
    unawaited(_load());
  }

  @override
  void dispose() {
    _watch?.cancel();
    _transfer
      ..removeListener(_changed)
      ..dispose();
    _client.close();
    super.dispose();
  }

  MoneyTransferStep? _lastStep;

  void _changed() {
    if (!mounted) return;
    final step = _transfer.step;
    // The chain confirmed it: read the balance now (once), not on the tick.
    if (step == MoneyTransferStep.confirmed && _lastStep != step) {
      unawaited(_check());
    }
    _lastStep = step;
    setState(() {});
  }

  /// The shortfall to the cent above, at least a dollar; else $10.
  BigInt _suggested() {
    final short = widget.shortfall;
    if (short == null || short <= BigInt.zero) return BigInt.from(10000000);
    final cent = BigInt.from(10000);
    final up = ((short + cent - BigInt.one) ~/ cent) * cent;
    final dollar = BigInt.from(1000000);
    return up < dollar ? dollar : up;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final options = await _client.depositOptions(
        amountBaseUnits: widget.shortfall,
      );
      final wallet = await _client.wallet();
      if (!mounted) return;
      // Every address on this sheet must be the trading wallet the app knows
      // on its own (money.wallet), never only what this answer says.
      final known = wallet.wallet?.address;
      _noWallet = known == null;
      if (known == null) return;
      // The destination must be a wallet this phone itself knows is the
      // account's; otherwise nothing payable shows (no QR, card or transfer).
      final mine = widget.dependencies.phoneWallets?.call() ?? const {};
      if (!mine.contains(known)) {
        throw const MoneyException(
          MoneyErrorKind.invalidResponse,
          'We couldn’t confirm your wallet. Nothing was sent.',
        );
      }
      if (
          options.tradingWallet?.address != known ||
          (options.sendUsdc != null &&
              (options.sendUsdc!.address != known ||
                  options.sendUsdc!.mint != usdcMint))) {
        throw const MoneyException(
          MoneyErrorKind.invalidResponse,
          'We couldn’t confirm your wallet. Nothing was sent.',
        );
      }
      _tradingWallet = known;
      _options = options;
      _baseline = wallet.usdcBaseUnits;
      widget.money?.adoptWallet(wallet);
      _watch ??= Timer.periodic(
        widget.dependencies.pollEvery,
        (_) => unawaited(_check()),
      );
    } on MoneyException catch (e) {
      if (mounted) _loadError = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Watches the balance; closes the sheet once the funds are there.
  Future<void> _check() async {
    if (_closed) return;
    try {
      final wallet = await _client.wallet();
      if (!mounted || _closed) return;
      widget.money?.adoptWallet(wallet);
      final usdc = wallet.usdcBaseUnits;
      if (usdc == null) return;
      final target = widget.target;
      final baseline = _baseline;
      final landed =
          target != null ? usdc >= target : baseline != null && usdc > baseline;
      if (landed) {
        _closed = true;
        _watch?.cancel();
        Navigator.of(context).pop(true);
      }
    } on MoneyException {
      // The next tick tries again.
    }
  }

  void _close() {
    if (!_transfer.canDismiss) return;
    if (_stage != _Stage.options) {
      setState(() => _stage = _Stage.options);
      _transfer.reset();
      return;
    }
    _closed = true;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Add funds',
    value: widget.shortfall == null ? null : moneyDollars(_suggested()),
    canDismiss: _transfer.canDismiss,
    onClose: _close,
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _body(context),
      ),
    ),
  );

  List<Widget> _body(BuildContext context) {
    if (_loading) {
      return const [
        SizedBox(
          height: 120,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ];
    }
    if (_noWallet) {
      final setUp = widget.dependencies.setUpWallet;
      return [
        const Center(
          child: ChumbucketStateArt(ChumbucketStateArtwork.access, size: 96),
        ),
        const SizedBox(height: 8),
        Text(
          'Set up your wallet first.',
          textAlign: TextAlign.center,
          style: callJourneyBody(13),
        ),
        if (setUp != null) ...[
          const SizedBox(height: 12),
          ChumbucketPrimaryButton(
            key: const ValueKey('deposit-set-up-wallet'),
            label: 'Set up wallet',
            neutral: true,
            onPressed: () async {
              if (await setUp(context) && mounted) await _load();
            },
          ),
        ],
      ];
    }
    final options = _options;
    if (options == null) {
      return [
        const Center(
          child: ChumbucketStateArt(ChumbucketStateArtwork.error, size: 96),
        ),
        const SizedBox(height: 8),
        Text(
          _loadError ?? 'Couldn’t load.',
          textAlign: TextAlign.center,
          style: callJourneyBody(13),
        ),
        const SizedBox(height: 12),
        ChumbucketPrimaryButton(
          label: 'Try again',
          neutral: true,
          onPressed: _load,
        ),
      ];
    }
    return switch (_stage) {
      _Stage.options => _optionList(context, options),
      _Stage.sendUsdc => _sendUsdc(context, _tradingWallet!),
      _Stage.fromWallet => _fromWallet(context, options),
    };
  }

  List<Widget> _optionList(BuildContext context, DepositOptions options) {
    final card = options.card;
    final any =
        options.fromWallets.isNotEmpty ||
        options.sendUsdc != null ||
        card.available;
    if (!any) {
      return [
        const Center(
          child: ChumbucketStateArt(ChumbucketStateArtwork.access, size: 96),
        ),
        const SizedBox(height: 8),
        Text(
          'Adding funds isn’t open yet.',
          textAlign: TextAlign.center,
          style: callJourneyBody(13),
        ),
      ];
    }
    final pay =
        !kIsWeb && Platform.isIOS
            ? 'Apple Pay'
            : !kIsWeb && Platform.isAndroid
            ? 'Google Pay'
            : null;
    return [
      if (options.fromWallets.isNotEmpty)
        _OptionTile(
          key: const ValueKey('deposit-from-wallet'),
          icon: 'mobile-phone-outline',
          label: 'From your wallet app',
          onTap: () => setState(() => _stage = _Stage.fromWallet),
        ),
      if (options.sendUsdc != null)
        _OptionTile(
          key: const ValueKey('deposit-send-usdc'),
          icon: 'arrow-down-outline',
          label: 'Send USDC',
          onTap: () => setState(() => _stage = _Stage.sendUsdc),
        ),
      if (card.available)
        _OptionTile(
          key: const ValueKey('deposit-card'),
          icon: 'card-outline',
          // Staging money is never shown as real: it says so every time.
          label: [
            'Card',
            if (pay != null) pay,
            if (card.testMode) 'Test',
          ].join(' · '),
          onTap: () => unawaited(_card(options)),
        ),
    ];
  }

  Future<void> _card(DepositOptions options) async {
    final open = widget.dependencies.openCard;
    if (open == null) return;
    final landed = await open(
      context,
      shortfall: widget.shortfall,
      wallet: _tradingWallet,
    );
    if (landed && mounted) await _check();
  }

  /// The QR is built here, from the checked address and mainnet USDC only.
  List<Widget> _sendUsdc(BuildContext context, String address) => [
    Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: QrImageView(
          key: const ValueKey('deposit-qr'),
          data: 'solana:$address?spl-token=$usdcMint',
          size: 180,
          backgroundColor: Colors.white,
        ),
      ),
    ),
    const SizedBox(height: 12),
    Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('deposit-copy'),
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: address));
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('Copied')));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  address,
                  style: callJourneyBody(
                    12,
                  ).copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 10),
              const BasilIcon(
                'copy-outline',
                size: 20,
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 10),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Text('USDC on Solana', style: callJourneyBody(12)),
      ],
    ),
  ];

  List<Widget> _fromWallet(BuildContext context, DepositOptions options) {
    final deps = widget.dependencies;
    final app = deps.walletApp?.call();
    final known = options.fromWallets.any((w) => w.address == app);
    final to = _tradingWallet;
    final t = _transfer;
    if (app == null || !known) {
      return [
        _OptionTile(
          key: const ValueKey('deposit-connect-wallet'),
          icon: 'wallet-outline',
          label: app == null ? 'Connect your wallet app' : 'Link this wallet first',
          onTap:
              deps.connectWalletApp == null
                  ? null
                  : () async {
                    await deps.connectWalletApp!(context);
                    if (mounted) setState(() {});
                  },
        ),
      ];
    }
    final amount = _amount!;
    final suggested = _suggested();
    final presets = <BigInt>{
      suggested,
      BigInt.from(10000000),
      BigInt.from(25000000),
      BigInt.from(50000000),
    }.toList()..sort();
    final reviewing = t.step == MoneyTransferStep.review;
    final inFlight =
        t.step == MoneyTransferStep.signing ||
        t.step == MoneyTransferStep.submitting ||
        t.step == MoneyTransferStep.sent ||
        t.step == MoneyTransferStep.confirming ||
        t.step == MoneyTransferStep.confirmed;
    return [
      // Where it goes: the trading wallet this app knows, shown in full.
      if (to != null)
        _ReviewLine(
          key: const ValueKey('deposit-destination'),
          icon: 'wallet-outline',
          label: to,
        ),
      const SizedBox(height: 8),
      if (!reviewing && !inFlight)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              ChoiceChip(
                key: ValueKey('deposit-amount-$preset'),
                label: Text(moneyDollars(preset)),
                selected: preset == amount,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                onSelected: (_) => setState(() => _amount = preset),
              ),
          ],
        ),
      if (reviewing || inFlight) ...[
        _ReviewLine(icon: 'wallet-outline', label: _short(app)),
        _ReviewLine(icon: 'arrow-down-outline', label: moneyDollars(amount)),
      ],
      if (t.error != null) ...[
        const SizedBox(height: 12),
        CallInlineError(t.error!),
      ],
      const SizedBox(height: 14),
      if (t.step == MoneyTransferStep.failed)
        Text(
          'Didn’t go through.',
          textAlign: TextAlign.center,
          style: callJourneyBody(13),
        )
      else if (inFlight && t.step != MoneyTransferStep.sent)
        const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        )
      else
        ChumbucketPrimaryButton(
          key: const ValueKey('deposit-from-wallet-go'),
          label:
              t.step == MoneyTransferStep.sent
                  ? 'Send again'
                  : reviewing
                  ? 'Approve in wallet · ${moneyDollars(amount)}'
                  : 'Add ${moneyDollars(amount)}',
          busy: t.busy,
          onPressed:
              to == null || t.busy
                  ? null
                  : t.step == MoneyTransferStep.sent
                  ? t.resend
                  : reviewing
                  ? t.sign
                  : () => t.prepare(
                    from: app,
                    to: to,
                    amountBaseUnits: amount,
                  ),
        ),
    ];
  }
}

String _short(String address) =>
    address.length <= 12
        ? address
        : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: BasilIcon(
                    icon,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: callJourneyHeading(context, 15)),
                ),
                const BasilIcon(
                  'caret-right-outline',
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({super.key, required this.icon, required this.label});
  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        BasilIcon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: callJourneyHeading(context, 15)),
        ),
      ],
    ),
  );
}
