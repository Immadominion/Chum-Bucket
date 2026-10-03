import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Bottom section of an earlier SOL escrow challenge's sheet (Settings →
/// History): the statement, and what the viewer can still do.
///
/// Only the WITNESS can settle an open escrow ("witness is judge"): completed
/// returns the stake to the challenger, not completed sends it to the witness,
/// and the program keeps its fee either way. The challenger can only wait, so
/// the sheet says that rather than offering anything.
class ResolveSheetContent extends StatelessWidget {
  final Map<String, dynamic> challenge;
  final bool isPending;
  final bool isWitness;
  final Function(Map<String, dynamic>, bool) onMarkCompleted;

  const ResolveSheetContent({
    super.key,
    required this.challenge,
    required this.isPending,
    required this.isWitness,
    required this.onMarkCompleted,
  });

  /// Check if we have a transaction signature or escrow address to view on explorer
  bool _hasExplorerLink() {
    final txSig = challenge['transaction_signature'] as String?;
    final escrowAddress = challenge['escrowAddress'] as String?;
    return (txSig != null && txSig.isNotEmpty) ||
        (escrowAddress != null && escrowAddress.isNotEmpty);
  }

  /// Open the transaction or account on Solscan explorer
  Future<void> _openExplorer(BuildContext context) async {
    // Prefer transaction signature over escrow address
    final txSig = challenge['transaction_signature'] as String?;
    final escrowAddress = challenge['escrowAddress'] as String?;

    String url;
    if (txSig != null && txSig.isNotEmpty) {
      // View transaction
      url = NetworkConfig.getExplorerUrl(txSig);
    } else if (escrowAddress != null && escrowAddress.isNotEmpty) {
      // View account (escrow address)
      url = NetworkConfig.getAccountExplorerUrl(escrowAddress);
    } else {
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Silently fail - not critical functionality
      debugPrint('Failed to open explorer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only the witness can settle; the challenger sees whose move it is.
    final canResolve = isPending && isWitness;
    final payout = escrowPayoutText(challenge);
    final status = (challenge['status'] as String?)?.toLowerCase() ?? 'pending';
    final statusColor = ChallengeStatusUtils.getStatusColor(status);
    final explain = AppTextStyles.textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
    );

    // Spacing is back-solved from the comp's measured glyph positions:
    // names -> statement 41.5dp, statement -> button 52dp, button -> secondary
    // 22dp, secondary -> sheet edge 25dp. The button sits 15dp from the sheet's
    // sides; the statement wraps inside a narrower 24dp column.
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 31.5, 15, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Text(
              (challenge['description'] as String?) ??
                  (challenge['title'] as String?) ??
                  'Escrow challenge',
              style: AppTextStyles.sheetStatement,
              textAlign: TextAlign.center,
            ),
          ),

          // View on Explorer button - show if transaction signature or escrow address exists
          if (_hasExplorerLink()) ...[
            SizedBox(height: 12.h),
            TextButton.icon(
              onPressed: () => _openExplorer(context),
              icon: BasilIcon(
                'share-box-outline',
                size: 18.w,
                color: Colors.blue.shade600,
              ),
              label: Text(
                'View on Solscan',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],

          if (canResolve) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Text(
                'You’re the witness, so you settle it. Completed sends '
                '$payout back to the challenger; not completed sends it to '
                'you. Your wallet asks you to approve either one.',
                key: const ValueKey('escrow-settle-explainer'),
                style: explain,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ChumbucketPrimaryButton(
              label: 'Completed',
              onPressed: () => onMarkCompleted(challenge, true),
            ),
            const SizedBox(height: 4),
            ChumbucketTextAction(
              label: 'Not completed',
              onPressed: () => onMarkCompleted(challenge, false),
            ),
          ] else if (isPending && !isWitness) ...[
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(25.r),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BasilIcon(
                    'sand-watch-outline',
                    color: Colors.orange.shade600,
                    size: 20.w,
                  ),
                  SizedBox(width: 8.w),
                  Flexible(
                    child: Text(
                      'Waiting for the witness to settle',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only the witness can settle it. Until they do, the SOL stays in '
              'escrow on Solana, and Chumbucket can’t move it.',
              style: explain,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 32),
            // Settled: say how it ended, not just that it did.
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: statusColor.withValues(alpha: .3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BasilIcon(
                    ChallengeStatusUtils.getStatusIcon(status),
                    color: statusColor,
                    size: 20.w,
                  ),
                  SizedBox(width: 8.w),
                  Flexible(
                    child: Text(
                      ChallengeStatusUtils.getStatusLabel(status),
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_settledNote(status) case final note?) ...[
              const SizedBox(height: 12),
              Text(note, style: explain, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Where the stake went, for the two outcomes the witness decides. Nothing
  /// is claimed for any other state.
  static String? _settledNote(String status) => switch (status) {
    'completed' => 'The stake went back to the challenger, less the fee.',
    'failed' => 'The stake went to the witness, less the fee.',
    _ => null,
  };
}
