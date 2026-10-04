/// The wallet sheet, from the header's balance pill: the balance, add funds,
/// cash out, and recent money activity as compact icon rows. The only money
/// chrome in the app besides the pill itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallInlineError, callJourneyBody, callJourneyHeading;
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart'
    show validatePantaWallet;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_client.dart';
import '../data/money_models.dart';
import '../money_controller.dart';
import '../money_transfer_controller.dart';
import 'money_amount_row.dart' show moneyOf;
import 'money_dependencies.dart';
import 'money_deposit_sheet.dart';

Future<void> showMoneyWalletSheet(BuildContext context) async {
  final deps = MoneyDependencies.of(context);
  final money = moneyOf(context, listen: false);
  if (deps == null || money == null) return;
  await showChumbucketWavySheet<void>(
    context: context,
    builder: (_) => MoneyWalletSheet(dependencies: deps, money: money),
  );
}

enum _Stage { home, cashOut }

class MoneyWalletSheet extends StatefulWidget {
  const MoneyWalletSheet({
    super.key,
    required this.dependencies,
    required this.money,
  });
  final MoneyDependencies dependencies;
  final MoneyController money;

  @override
  State<MoneyWalletSheet> createState() => _MoneyWalletSheetState();
}

class _MoneyWalletSheetState extends State<MoneyWalletSheet> {
  late final MoneyClient _client = widget.dependencies.createClient();
  late final MoneyTransferController _cashOut = MoneyTransferController(
    client: _client,
    kind: MoneyTransferKind.cashOut,
    signerFor: widget.dependencies.transferSigner,
    topUp: widget.dependencies.gasTopUp,
    pollEvery: widget.dependencies.pollEvery,
  )..addListener(_transferChanged);
  final _address = TextEditingController();
  final _amount = TextEditingController();

  List<MoneyActivityItem>? _activity;
  bool _activityFailed = false;
  _Stage _stage = _Stage.home;
  String? _entryError;

  MoneyController get money => widget.money;

  @override
  void initState() {
    super.initState();
    money.addListener(_changed);
    unawaited(money.refreshWallet());
    unawaited(_loadActivity());
  }

  @override
  void dispose() {
    money.removeListener(_changed);
    _cashOut
      ..removeListener(_transferChanged)
      ..dispose();
    _client.close();
    _address.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  MoneyTransferStep? _lastStep;

  /// Once the chain confirms a cash out, the balance is read again — once.
  void _transferChanged() {
    if (!mounted) return;
    final step = _cashOut.step;
    if (step == MoneyTransferStep.confirmed && _lastStep != step) {
      unawaited(money.refreshWallet());
      unawaited(_loadActivity());
    }
    _lastStep = step;
    setState(() {});
  }

  Future<void> _loadActivity() async {
    try {
      final items = await _client.activity();
      if (mounted) {
        setState(() {
          _activity = items;
          _activityFailed = false;
        });
      }
    } on MoneyException {
      if (mounted) setState(() => _activityFailed = true);
    }
  }

  Future<void> _addFunds() async {
    final landed = await showMoneyDepositSheet(context);
    if (landed && mounted) {
      await money.refreshWallet();
      await _loadActivity();
    }
  }

  void _close() {
    final step = _cashOut.step;
    if (!_cashOut.canDismiss) return;
    if (_stage == _Stage.cashOut &&
        step != MoneyTransferStep.confirmed &&
        step != MoneyTransferStep.confirming &&
        step != MoneyTransferStep.sent) {
      _cashOut.reset();
      setState(() {
        _stage = _Stage.home;
        _entryError = null;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final balance = money.balance;
    return ChumbucketWavySheet(
      title: _stage == _Stage.cashOut ? 'Cash out' : 'Balance',
      value: balance == null ? null : moneyDollars(balance),
      canDismiss: _cashOut.canDismiss,
      onClose: _close,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:
              _stage == _Stage.home ? _home(context) : _cashOutBody(context),
        ),
      ),
    );
  }

  List<Widget> _home(BuildContext context) {
    final hasWallet = money.wallet?.wallet != null;
    return [
      Row(
        children: [
          Expanded(
            child: _Action(
              key: const ValueKey('wallet-add-funds'),
              icon: 'plus-outline',
              label: 'Add',
              onTap: () => unawaited(_addFunds()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Action(
              key: const ValueKey('wallet-cash-out'),
              icon: 'arrow-up-outline',
              label: 'Cash out',
              onTap:
                  hasWallet && (money.balance ?? BigInt.zero) > BigInt.zero
                      ? () => setState(() => _stage = _Stage.cashOut)
                      : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ..._activityRows(context),
    ];
  }

  List<Widget> _activityRows(BuildContext context) {
    final items = _activity;
    if (items == null) {
      if (_activityFailed) {
        return [
          const Center(
            child: ChumbucketStateArt(ChumbucketStateArtwork.error, size: 88),
          ),
          Center(
            child: TextButton(
              onPressed: _loadActivity,
              child: Text('Try again', style: callJourneyHeading(context, 13)),
            ),
          ),
        ];
      }
      return const [
        SizedBox(
          height: 60,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        const Center(
          child: ChumbucketStateArt(ChumbucketStateArtwork.inbox, size: 88),
        ),
        const SizedBox(height: 6),
        Text(
          'No money moves yet',
          key: const ValueKey('wallet-activity-empty'),
          textAlign: TextAlign.center,
          style: callJourneyBody(13),
        ),
      ];
    }
    return [for (final item in items) _ActivityRow(item: item)];
  }

  List<Widget> _cashOutBody(BuildContext context) {
    final t = _cashOut;
    final from = money.wallet?.wallet?.address;
    final balance = money.balance ?? BigInt.zero;
    switch (t.step) {
      case MoneyTransferStep.confirmed:
        return [
          const Center(
            child: ChumbucketStateArt(ChumbucketStateArtwork.success, size: 96),
          ),
          const SizedBox(height: 8),
          Text(
            '${moneyDollars(t.transfer!.amountBaseUnits)} sent',
            key: const ValueKey('cash-out-sent'),
            textAlign: TextAlign.center,
            style: callJourneyHeading(context, 18),
          ),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Done',
            neutral: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ];
      case MoneyTransferStep.failed:
        return [
          const Center(
            child: ChumbucketStateArt(ChumbucketStateArtwork.error, size: 96),
          ),
          const SizedBox(height: 8),
          Text(
            'Didn’t go through. Nothing left your wallet.',
            textAlign: TextAlign.center,
            style: callJourneyBody(13),
          ),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Try again',
            neutral: true,
            onPressed: t.reset,
          ),
        ];
      case MoneyTransferStep.review ||
          MoneyTransferStep.signing ||
          MoneyTransferStep.submitting ||
          MoneyTransferStep.sent ||
          MoneyTransferStep.confirming:
        final ready = t.ready!;
        final amount = moneyDollars(ready.review.amountBaseUnits);
        final pending =
            t.step == MoneyTransferStep.confirming ||
            t.step == MoneyTransferStep.submitting;
        return [
          Container(
            key: const ValueKey('cash-out-review'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                // The full address and the exact amount that will be signed.
                _line(
                  context,
                  'send-outline',
                  ready.review.to,
                  key: const ValueKey('cash-out-review-to'),
                ),
                _line(
                  context,
                  'wallet-outline',
                  amount,
                  key: const ValueKey('cash-out-review-amount'),
                ),
              ],
            ),
          ),
          if (t.error != null) ...[
            const SizedBox(height: 12),
            CallInlineError(t.error!),
          ],
          const SizedBox(height: 16),
          if (pending)
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
              key: const ValueKey('cash-out-sign'),
              label:
                  t.step == MoneyTransferStep.sent
                      ? 'Send again'
                      : 'Cash out $amount',
              busy: t.busy,
              busyLabel:
                  t.opensWalletApp ? 'Approve in your wallet…' : 'Signing…',
              onPressed:
                  t.busy
                      ? null
                      : t.step == MoneyTransferStep.sent
                      ? t.resend
                      : t.sign,
            ),
        ];
      case MoneyTransferStep.idle || MoneyTransferStep.preparing:
        return [
          TextField(
            key: const ValueKey('cash-out-address'),
            controller: _address,
            enabled: !t.busy,
            autocorrect: false,
            style: callJourneyBody(13).copyWith(color: AppColors.textPrimary),
            decoration: _field(
              hint: 'Solana address',
              suffix: IconButton(
                tooltip: 'Paste',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim();
                  if (text != null && mounted) {
                    setState(() => _address.text = text);
                  }
                },
                icon: const BasilIcon(
                  'clipboard-outline',
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('cash-out-amount'),
            controller: _amount,
            enabled: !t.busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(12),
            ],
            style: callJourneyHeading(context, 18),
            decoration: _field(
              prefix: r'$ ',
              suffix: TextButton(
                key: const ValueKey('cash-out-max'),
                onPressed: () => setState(
                  () =>
                      _amount.text = moneyDollars(
                        balance,
                      ).replaceFirst(r'$', '').replaceAll(',', ''),
                ),
                child: Text(
                  'Max',
                  style: callJourneyHeading(
                    context,
                    13,
                  ).copyWith(color: AppColors.pinkInk),
                ),
              ),
            ),
          ),
          if ((_entryError ?? t.error) case final error?) ...[
            const SizedBox(height: 12),
            CallInlineError(error),
          ],
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            key: const ValueKey('cash-out-review-go'),
            label: 'Review',
            neutral: true,
            busy: t.busy,
            onPressed: from == null || t.busy ? null : () => _review(from),
          ),
        ];
    }
  }

  void _review(String from) {
    final to = _address.text.trim();
    try {
      validatePantaWallet(to);
    } catch (_) {
      setState(() => _entryError = 'Check the address.');
      return;
    }
    final units = _maxAware(_amount.text);
    final balance = money.balance ?? BigInt.zero;
    if (units == null || units <= BigInt.zero || units > balance) {
      setState(() => _entryError = 'Up to ${moneyDollars(balance)}.');
      return;
    }
    setState(() => _entryError = null);
    unawaited(_cashOut.prepare(from: from, to: to, amountBaseUnits: units));
  }

  /// "Max" keeps every base unit of the balance; typed amounts are cents.
  BigInt? _maxAware(String text) {
    final balance = money.balance;
    if (balance != null &&
        text.trim() ==
            moneyDollars(balance).replaceFirst(r'$', '').replaceAll(',', '')) {
      return balance;
    }
    return parseDollarAmount(text);
  }

  InputDecoration _field({String? hint, String? prefix, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: callJourneyBody(13),
        prefixText: prefix,
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      );

  Widget _line(BuildContext context, String icon, String text, {Key? key}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            BasilIcon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                text,
                key: key,
                style: callJourneyHeading(context, 15),
              ),
            ),
          ],
        ),
      );
}

String _short(String address) =>
    address.length <= 12
        ? address
        : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .45 : 1,
    child: Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              BasilIcon(icon, size: 22, color: AppColors.textPrimary),
              const SizedBox(height: 6),
              Text(label, style: callJourneyHeading(context, 13)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final MoneyActivityItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      MoneyActivityKind.trade => 'chart-pie-outline',
      MoneyActivityKind.claim => 'award-outline',
      MoneyActivityKind.deposit => 'arrow-down-outline',
      MoneyActivityKind.cashOut => 'arrow-up-outline',
    };
    final title = switch (item.kind) {
      MoneyActivityKind.trade || MoneyActivityKind.claim =>
        item.question ?? (item.kind == MoneyActivityKind.claim ? 'Collected' : 'Call'),
      MoneyActivityKind.deposit => 'Added',
      MoneyActivityKind.cashOut =>
        item.counterparty == null ? 'Cashed out' : _short(item.counterparty!),
    };
    final amount = moneyDollars(
      item.incoming ? item.amountBaseUnits : -item.amountBaseUnits,
      signed: true,
    );
    final side = item.side;
    return Padding(
      key: ValueKey('activity-${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: BasilIcon(icon, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: callJourneyHeading(context, 13),
                ),
                Text(
                  [
                    if (side != null) side.wire,
                    CallsFormat.shortWhen(
                      DateTime.fromMillisecondsSinceEpoch(item.at, isUtc: true),
                    ),
                  ].join(' · '),
                  style: callJourneyBody(11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.state == MoneyActivityState.pending)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: BasilIcon(
                'clock-outline',
                size: 16,
                color: AppColors.onWarningContainer,
              ),
            )
          else if (item.state == MoneyActivityState.failed)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: BasilIcon(
                'cross-outline',
                size: 16,
                color: AppColors.onErrorContainer,
              ),
            ),
          Text(
            amount,
            style: callJourneyHeading(context, 14).copyWith(
              color:
                  item.state == MoneyActivityState.failed
                      ? AppColors.textMuted
                      : item.incoming
                      ? AppColors.onSuccessContainer
                      : AppColors.textPrimary,
              decoration:
                  item.state == MoneyActivityState.failed
                      ? TextDecoration.lineThrough
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}
