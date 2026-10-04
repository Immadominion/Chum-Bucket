/// The amount on a call action: `Free · $5 · $10 · $25 · +`, and the call to
/// action that follows it — `Call YES` in ink with the Free marker, or
/// `Call YES · $5` in pink. Pink is money; nothing free is ever pink.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallJourneyButton, callJourneyBody, callJourneyHeading;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_models.dart';
import '../money_controller.dart';

/// Money is on for this account (the build flag and the server both): the
/// amount row, the pill and every money action show only then.
MoneyController? moneyOf(BuildContext context, {bool listen = true}) {
  final money =
      listen
          ? context.watch<MoneyController?>()
          : context.read<MoneyController?>();
  return money != null && money.enabled ? money : null;
}

class MoneyAmountRow extends StatefulWidget {
  const MoneyAmountRow({
    super.key,
    required this.value,
    required this.presets,
    required this.minBaseUnits,
    required this.maxBaseUnits,
    required this.onChanged,
    this.enabled = true,
  });

  final MoneyAmount value;
  final List<BigInt> presets;
  final BigInt minBaseUnits;
  final BigInt maxBaseUnits;
  final ValueChanged<MoneyAmount> onChanged;
  final bool enabled;

  /// The row for [money]'s presets and limits.
  factory MoneyAmountRow.of(
    MoneyController money, {
    Key? key,
    required MoneyAmount value,
    required ValueChanged<MoneyAmount> onChanged,
    bool enabled = true,
  }) => MoneyAmountRow(
    key: key,
    value: value,
    presets: money.presets,
    minBaseUnits: money.minBaseUnits,
    maxBaseUnits: money.maxBaseUnits,
    onChanged: onChanged,
    enabled: enabled,
  );

  @override
  State<MoneyAmountRow> createState() => _MoneyAmountRowState();
}

class _MoneyAmountRowState extends State<MoneyAmountRow> {
  late bool _editing = _isCustom(widget.value);
  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _invalid = false;

  bool _isCustom(MoneyAmount value) =>
      !value.isFree && !widget.presets.contains(value.baseUnits);

  @override
  void initState() {
    super.initState();
    if (_isCustom(widget.value)) {
      _field.text = _plain(widget.value.baseUnits!);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// "7.5" for the field, not "$7.50".
  String _plain(BigInt units) =>
      moneyDollars(units).replaceFirst(r'$', '').replaceAll(',', '');

  void _pick(MoneyAmount amount) {
    setState(() {
      _editing = false;
      _invalid = false;
    });
    _focus.unfocus();
    widget.onChanged(amount);
  }

  void _custom() {
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _typed(String text) {
    final units = parseDollarAmount(text);
    final ok =
        units != null &&
        units >= widget.minBaseUnits &&
        units <= widget.maxBaseUnits;
    setState(() => _invalid = text.isNotEmpty && !ok);
    if (ok) widget.onChanged(MoneyAmount(units));
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final custom = _isCustom(value);
    final onTap = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MoneyChip(
                key: const ValueKey('money-amount-free'),
                label: 'Free',
                icon: 'present-outline',
                selected: value.isFree,
                money: false,
                onTap: onTap ? () => _pick(const MoneyAmount.free()) : null,
              ),
              for (final preset in widget.presets) ...[
                const SizedBox(width: 8),
                _MoneyChip(
                  key: ValueKey('money-amount-$preset'),
                  label: moneyDollars(preset),
                  selected: value.baseUnits == preset,
                  money: true,
                  onTap: onTap ? () => _pick(MoneyAmount(preset)) : null,
                ),
              ],
              const SizedBox(width: 8),
              _MoneyChip(
                key: const ValueKey('money-amount-custom'),
                label: custom ? value.label : null,
                icon: custom ? null : 'plus-outline',
                semanticsLabel: custom ? value.label : 'Other amount',
                selected: custom || _editing,
                money: true,
                onTap: onTap ? _custom : null,
              ),
            ],
          ),
        ),
        if (_editing) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('money-amount-custom-field'),
            controller: _field,
            focusNode: _focus,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              LengthLimitingTextInputFormatter(9),
            ],
            onChanged: _typed,
            style: callJourneyHeading(context, 18),
            decoration: InputDecoration(
              prefixText: r'$ ',
              prefixStyle: callJourneyHeading(context, 18),
              isDense: true,
              filled: true,
              fillColor: AppColors.background,
              errorText:
                  _invalid
                      ? '${moneyDollars(widget.minBaseUnits)}–'
                          '${moneyDollars(widget.maxBaseUnits)}'
                      : null,
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
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MoneyChip extends StatelessWidget {
  const _MoneyChip({
    super.key,
    required this.selected,
    required this.money,
    required this.onTap,
    this.label,
    this.icon,
    this.semanticsLabel,
  });

  final String? label;
  final String? icon;
  final String? semanticsLabel;
  final bool selected;

  /// Pink when chosen; Free is ink.
  final bool money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill =
        selected
            ? (money ? AppColors.primary : ChumbucketPrimaryButton.ink)
            : AppColors.surface;
    final ink =
        selected
            ? (money ? AppColors.textPrimary : Colors.white)
            : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: StadiumBorder(
          side: BorderSide(
            color:
                selected
                    ? fill
                    : money
                    ? AppColors.outlineVariant
                    : AppColors.outline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null)
                    BasilIcon(icon!, size: 16, color: ink),
                  if (icon != null && label != null) const SizedBox(width: 5),
                  if (label != null)
                    Text(
                      label!,
                      style: callJourneyHeading(
                        context,
                        14,
                      ).copyWith(color: ink, fontWeight: FontWeight.w800),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Call YES` (ink, Free marker) or `Call YES · $5` (pink).
class MoneyCallButton extends StatelessWidget {
  const MoneyCallButton({
    super.key,
    required this.label,
    required this.amount,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final MoneyAmount amount;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (amount.isFree) {
      return CallJourneyButton(
        label: label,
        primary: true,
        free: true,
        busy: busy,
        onPressed: onPressed,
      );
    }
    final text = '$label · ${amount.label}';
    return ChumbucketPrimaryButton(
      key: const ValueKey('money-call-button'),
      label: text,
      onPressed: onPressed,
      busy: busy,
      busyLabel: 'Please wait…',
      semanticsLabel: text,
    );
  }
}

/// A quiet one-line note under a money action (a refusal, a reason).
class MoneyNote extends StatelessWidget {
  const MoneyNote(this.text, {super.key, this.icon = 'info-circle-outline'});
  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      BasilIcon(icon, size: 16, color: AppColors.textMuted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: callJourneyBody(12))),
    ],
  );
}
