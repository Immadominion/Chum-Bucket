import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

enum SolTransferStatus { success, failed }

class SolTransferResultScreen extends StatefulWidget {
  final SolTransferStatus status;
  final String? errorMessage;
  final VoidCallback onDone;
  final String? destinationAddress;
  final double? amount;
  final String? transactionSignature;

  const SolTransferResultScreen({
    super.key,
    required this.status,
    this.errorMessage,
    required this.onDone,
    this.destinationAddress,
    this.amount,
    this.transactionSignature,
  });

  @override
  State<SolTransferResultScreen> createState() =>
      _SolTransferResultScreenState();
}

class _SolTransferResultScreenState extends State<SolTransferResultScreen> {
  String? _displayAddress;

  @override
  void initState() {
    super.initState();
    _resolveDisplayAddress();
  }

  Future<void> _resolveDisplayAddress() async {
    if (widget.destinationAddress != null) {
      final displayName = await AddressNameResolver.resolveDisplayName(
        widget.destinationAddress!,
      );
      if (mounted) {
        setState(() {
          _displayAddress = displayName;
        });
      }
    }
  }

  SolTransferStatusData _getSolTransferStatusData(SolTransferStatus status) {
    switch (status) {
      case SolTransferStatus.success:
        return SolTransferStatusData(
          title: "Withdraw Successfully!",
          message:
              _displayAddress != null
                  ? "Sol is on its way to $_displayAddress"
                  : "Your SOL transfer has been processed successfully",
          color: Colors.green,
          buttonDescription: "Your SOL transfer is complete",
        );
      case SolTransferStatus.failed:
        return SolTransferStatusData(
          title: "Withdraw Failed",
          message:
              widget.errorMessage ??
              "Something went wrong with your withdrawal. Please try again.",
          color: Colors.red,
          buttonDescription: "SOL withdrawal could not be completed",
        );
    }
  }

  Future<void> _openTransactionOnExplorer() async {
    if (widget.transactionSignature == null) return;

    // Use Solscan for devnet or mainnet
    final explorerUrl =
        'https://solscan.io/tx/${widget.transactionSignature}?cluster=devnet';

    try {
      final uri = Uri.parse(explorerUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to Solana Explorer
        final fallbackUrl =
            'https://explorer.solana.com/tx/${widget.transactionSignature}?cluster=devnet';
        final fallbackUri = Uri.parse(fallbackUrl);
        if (await canLaunchUrl(fallbackUri)) {
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      // Handle error silently or show a snackbar
      debugPrint('Could not open explorer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusData = _getSolTransferStatusData(widget.status);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // SOL Transfer Status Animation and Text
            SolTransferStatusWidget(
              status: widget.status,
              statusData: statusData,
              errorMessage: widget.errorMessage,
              amount: widget.amount,
              destinationAddress: _displayAddress,
            ),

            const SizedBox(height: 30),

            // Action Buttons
            Row(
              children: [
                // Show explorer button for successful transfers with signature
                if (widget.status == SolTransferStatus.success &&
                    widget.transactionSignature != null) ...[
                  Flexible(
                    child: ChallengeButton(
                      createNewChallenge: _openTransactionOnExplorer,
                      label: 'View on Explorer',
                      hasGradient: true,
                      blurRadius: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                Flexible(
                  child: ChallengeButton(
                    createNewChallenge: widget.onDone,
                    label: 'Done',
                    blurRadius: false,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// Custom status data class for SOL transfers
class SolTransferStatusData {
  final String title;
  final String message;
  final Color color;
  final String buttonDescription;

  const SolTransferStatusData({
    required this.title,
    required this.message,
    required this.color,
    required this.buttonDescription,
  });
}

// Custom widget for SOL transfer status display
class SolTransferStatusWidget extends StatelessWidget {
  final SolTransferStatus status;
  final SolTransferStatusData statusData;
  final String? errorMessage;
  final double? amount;
  final String? destinationAddress;

  const SolTransferStatusWidget({
    super.key,
    required this.status,
    required this.statusData,
    this.errorMessage,
    this.amount,
    this.destinationAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Status Icon
        status == SolTransferStatus.success
            ? LottieBuilder.asset(
              'assets/animations/lottie/success.json',
              width: 150.w,
              height: 150.h,
              repeat: false,
            )
            : LottieBuilder.asset(
              'assets/animations/lottie/Failed.json',
              width: 150.w,
              height: 150.h,
              repeat: false,
            ),

        const SizedBox(height: 24),

        // Title
        Text(
          statusData.title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        // Amount display for successful transfers
        if (status == SolTransferStatus.success && amount != null)
          Text(
            '$amount SOL',
            style: TextStyle(
              fontSize: 32.sp,
              fontWeight: FontWeight.w700,
              color: statusData.color,
            ),
            textAlign: TextAlign.center,
          ),

        const SizedBox(height: 12),

        // Message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            statusData.message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
              height: 1.4,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
