import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart'
    show CallFeedEntry;
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallInlineError, callJourneyHeading;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/money_models.dart';
import 'money_amount_row.dart' show moneyOf;
import 'money_call_sheet.dart';

/// The owner's own call while its money is pending — shown to them alone,
/// never stamped funded. Opens the call's money sheet: wait for the fill,
/// try again, keep it free, or discard it.
class MoneyPendingCard extends StatefulWidget {
  const MoneyPendingCard({
    super.key,
    required this.entry,
    required this.onChanged,
    this.onReplaced,
  });

  final CallFeedEntry entry;

  /// The call changed (funded, discarded): read it again.
  final VoidCallback onChanged;

  /// Kept free: a NEW free call replaced this one. Go to it.
  final ValueChanged<CallFeedEntry>? onReplaced;

  @override
  State<MoneyPendingCard> createState() => _MoneyPendingCardState();
}

class _MoneyPendingCardState extends State<MoneyPendingCard> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await resumeMoneyCall(context, call: widget.entry);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = outcome?.error;
    });
    final replaced = outcome?.call;
    if (replaced != null &&
        replaced.call.id != widget.entry.call.id &&
        widget.onReplaced != null) {
      widget.onReplaced!(replaced);
      return;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final money = widget.entry.money;
    if (money == null || !money.pending || moneyOf(context) == null) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('money-pending-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BasilIcon(
                'clock-outline',
                size: 22,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  moneyOnSide(money.amountBaseUnits, money.side),
                  style: callJourneyHeading(context, 16),
                ),
              ),
              const CallBadge(
                label: 'Pending',
                color: AppColors.textMuted,
                icon: 'clock-outline',
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            CallInlineError(_error!),
          ],
          const SizedBox(height: 12),
          ChumbucketPrimaryButton(
            key: const ValueKey('money-pending-open'),
            label: 'Open',
            neutral: true,
            busy: _busy,
            onPressed: _busy ? null : _open,
          ),
        ],
      ),
    );
  }
}
