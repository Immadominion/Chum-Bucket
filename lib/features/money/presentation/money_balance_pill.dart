import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show callJourneyHeading;
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_models.dart';
import 'money_amount_row.dart' show moneyOf;
import 'money_wallet_sheet.dart';

/// The one balance in the header: `$12.19`. Tap opens the wallet sheet.
/// Nothing at all while money is off, or before the balance has been read.
class MoneyBalancePill extends StatelessWidget {
  const MoneyBalancePill({super.key});

  @override
  Widget build(BuildContext context) {
    final money = moneyOf(context);
    final info = money?.wallet;
    if (money == null || info == null) return const SizedBox.shrink();
    final label = moneyDollars(info.usdcBaseUnits ?? BigInt.zero);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        label: 'Balance $label',
        excludeSemantics: true,
        child: Material(
          key: const ValueKey('money-balance-pill'),
          color: AppColors.surface,
          shape: const StadiumBorder(
            side: BorderSide(color: AppColors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showMoneyWalletSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BasilIcon(
                      'wallet-outline',
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: callJourneyHeading(context, 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
