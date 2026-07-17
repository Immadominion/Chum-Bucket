import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Bottom section of the resolve challenge sheet containing the challenge text
/// and action buttons for completing or failing the challenge.
/// NOTE: Only the WITNESS can resolve challenges ("Witness is Judge" model)
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
    // Only witness can resolve - initiator sees waiting message
    final canResolve = isPending && isWitness;

    return Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 12.h),
        child: Column(
          children: [
            // Challenge description
            Flexible(
              flex: 3,
              child: Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: 350.w, minHeight: 60.h),
                  child: Text(
                    (challenge['description'] as String?) ??
                        (challenge['title'] as String?) ??
                        'Create challenge first',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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

            // Spacer to push buttons to bottom
            const Spacer(),

            // Action buttons - only shown to witness
            if (canResolve) ...[
              // Challenge completed button
              ChallengeButton(
                createNewChallenge: () => onMarkCompleted(challenge, true),
                label: 'Challenge Completed',
              ),
              SizedBox(height: 8.h),
              // Failed to complete button
              TextButton(
                onPressed: () => onMarkCompleted(challenge, false),
                child: Text(
                  'Failed to complete',
                  style: TextStyle(
                    fontSize: 17.sp,
                    color: const Color(0xFFFF5A76),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ] else if (isPending && !isWitness) ...[
              // Initiator sees waiting message
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
                        'Waiting for witness to resolve',
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
            ] else ...[
              // Completed state
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BasilIcon(
                      'check-outline',
                      color: Colors.green.shade600,
                      size: 20.w,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Challenge completed',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 8.h), // Bottom padding
          ],
        ),
      ),
    );
  }
}
