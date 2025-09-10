import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui';

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
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      if (walletProvider.walletAddress == null) {
        walletProvider.refreshBalance();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 450.h;
    final preferredHeight = 550.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(43.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(43.r),
        child: Stack(
          children: [
            // Header with gradient background and wave
            _buildHeader(),

            // Scrollable content
            Positioned(
              top: 120.h,
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildScrollableContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 200.h,
      child: Stack(
        children: [
          // Gradient Background
          Container(
            height: 200.h,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(height: 8.h),
                  // Drag handle
                  Container(
                    width: 43.w,
                    height: 3.2.h,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  SizedBox(height: 32.h),
                  // Title
                  Text(
                    'Wallet',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'My Wallet Details',
                    style: TextStyle(
                      fontSize: 22.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Wave at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: DetailedWaveClipper(),
              child: Container(height: 80.h, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableContent() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 18.h),
      child: Consumer<WalletProvider>(
        builder: (context, walletProvider, _) {
          return Column(
            children: [
              // QR Code section
              Column(
                children: [
                  // QR Code
                  Container(
                    width: 300.w,
                    height: 300.w,
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

              Spacer(),

              // Disclaimer
              Text(
                "Disclaimer: Wallet secrets are managed by Privy and are not exportable.",
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

  Widget _buildQRCode(WalletProvider walletProvider) {
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

  Widget _buildWalletAddress(WalletProvider walletProvider) {
    return GestureDetector(
      onTap: () {
        if (walletProvider.walletAddress != null) {
          Clipboard.setData(ClipboardData(text: walletProvider.walletAddress!));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Wallet address copied to clipboard"),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
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
          Icon(
            PhosphorIcons.copySimple(),
            size: 18.w,
            color: const Color(0xFFFF5A76),
          ),
        ],
      ),
    );
  }
}

/// Function to show the wallet modal with backdrop blur
Future<void> showWalletModal(BuildContext context) async {
  // Get the wallet provider first to ensure it's available to the modal
  final walletProvider = Provider.of<WalletProvider>(context, listen: false);

  // Ensure we have the wallet address
  if (walletProvider.walletAddress == null) {
    walletProvider.refreshBalance();
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    elevation: 0,
    builder: (BuildContext modalContext) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
        child: SafeArea(
          child: ChangeNotifierProvider<WalletProvider>.value(
            value: walletProvider,
            child: const WalletModal(),
          ),
        ),
      );
    },
  );
}
