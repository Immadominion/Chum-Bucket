/// A reviewer's "not approved", with a reason the proposer will see.
library;

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';

import '../data/market_creation_models.dart';

class RejectDecision {
  const RejectDecision(this.reason, this.note);
  final ReviewReason reason;
  final String? note;
}

Future<RejectDecision?> showRejectProposalSheet(BuildContext context) =>
    showChumbucketWavySheet<RejectDecision>(
      context: context,
      builder: (_) => const _RejectProposalSheet(),
    );

class _RejectProposalSheet extends StatefulWidget {
  const _RejectProposalSheet();

  @override
  State<_RejectProposalSheet> createState() => _RejectProposalSheetState();
}

class _RejectProposalSheetState extends State<_RejectProposalSheet> {
  ReviewReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Not approved',
    subtitle: 'The proposer sees this reason and your note.',
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<ReviewReason>(
            groupValue: _reason,
            onChanged: (value) => setState(() => _reason = value),
            child: Column(
              children: [
                for (final reason in ReviewReason.values)
                  RadioListTile<ReviewReason>(
                    value: reason,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    activeColor: AppColors.primary,
                    title: Text(
                      reason.label,
                      style: AppTextStyles.sheetStatement,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _note,
              maxLength: 280,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note for the proposer (optional)',
              ),
            ),
          ),
        ],
      ),
    ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChumbucketPrimaryButton(
            label: 'Reject proposal',
            onPressed:
                _reason == null
                    ? null
                    : () => Navigator.of(context).pop(
                      RejectDecision(
                        _reason!,
                        _note.text.trim().isEmpty ? null : _note.text.trim(),
                      ),
                    ),
          ),
          ChumbucketTextAction(
            label: 'Cancel',
            color: AppColors.textSecondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}
