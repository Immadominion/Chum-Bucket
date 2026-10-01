import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
// MWA Wallet Provider for Pinocchio program integration
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Wallet modal following the new bottom sheet design pattern
class WalletModal extends StatefulWidget {
  const WalletModal({super.key});

  @override
  State<WalletModal> createState() => _WalletModalState();
}

class _WalletModalState extends State<WalletModal> {
  @override
  void initState() {
    super.initState();
    // Ensure wallet data is refreshed when modal is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final walletProvider = Provider.of<MwaWalletProvider>(
        context,
        listen: false,
      );
      if (walletProvider.walletAddress != null) {
        walletProvider.refreshWalletBalance();
      }
    });
  }

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'My Wallet Details',
    body: SingleChildScrollView(child: _buildScrollableContent()),
  );

  Widget _buildScrollableContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Consumer<MwaWalletProvider>(
        builder: (context, walletProvider, _) {
          return Column(
            children: [
              // QR Code section
              Column(
                children: [
                  // QR Code
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _buildQRCode(walletProvider),
                  ),

                  SizedBox(height: 16.h),

                  // Wallet address with copy button
                  _buildWalletAddress(walletProvider),
                ],
              ),

              const SizedBox(height: 24),

              // Disclaimer
              Text(
                "Wallet managed by your external wallet app (Phantom, Solflare, etc.)",
                style: TextStyle(
                  fontSize: 12.sp,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQRCode(MwaWalletProvider walletProvider) {
    if (walletProvider.loadingState == LoadingState.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: const Color(0xFFFF5A76),
              strokeWidth: 3.w,
            ),
            SizedBox(height: 12.h),
            Text(
              "Loading wallet...",
              style: TextStyle(
                color: const Color(0xFFFF5A76),
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (walletProvider.walletAddress != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: QrImageView(
          data: walletProvider.walletAddress!,
          version: QrVersions.auto,
          size: 200.w,
          backgroundColor: Colors.white,
          padding: EdgeInsets.all(16.w),
          errorStateBuilder: (context, error) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 40.w),
                  SizedBox(height: 8.h),
                  Text(
                    "Error generating QR code",
                    style: TextStyle(color: Colors.red, fontSize: 14.sp),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Center(
      child: Icon(
        CupertinoIcons.qrcode,
        size: 80.w,
        color: Colors.grey.shade400,
      ),
    );
  }

  Widget _buildWalletAddress(MwaWalletProvider walletProvider) {
    return GestureDetector(
      onTap: () {
        if (walletProvider.walletAddress != null) {
          Clipboard.setData(ClipboardData(text: walletProvider.walletAddress!));
          SnackBarUtils.showInfo(
            context,
            title: "Copied",
            subtitle: "Wallet address copied to clipboard",
          );
          Navigator.pop(context);
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child:
                walletProvider.walletAddress != null
                    ? ResolvedAddressText(
                      addressOrLabel: walletProvider.walletAddress!,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                    )
                    : Text(
                      'No Address',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
          ),
          SizedBox(width: 4.w),
          BasilIcon('copy-outline', size: 18.w, color: const Color(0xFFFF5A76)),
        ],
      ),
    );
  }
}

/// Function to show the wallet modal with backdrop blur
Future<void> showWalletModal(BuildContext context) {
  // Preserve the originating wallet even when it is scoped below Navigator.
  final walletProvider = context.read<MwaWalletProvider>();
  if (walletProvider.walletAddress == null) {
    walletProvider.refreshWalletBalance();
  }
  return showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => ChangeNotifierProvider<MwaWalletProvider>.value(
          value: walletProvider,
          child: const WalletModal(),
        ),
  );
}
