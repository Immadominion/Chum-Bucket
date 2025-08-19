import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/providers/wallet_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, _) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24.w,
            right: 24.w,
            top: 24.h,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "My Wallet",
                    style: TextStyle(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(CupertinoIcons.xmark, size: 18.sp),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Text(
                "Your holdings are held in cryptocurrency wallets in your custody. You can directly control your wallets using your secret phrase.",
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 24.h),
              Center(
                child: Container(
                  width: 200.w,
                  height: 200.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.1),
                    ),
                  ),
                  child:
                      walletProvider.loadingState == LoadingState.loading
                          ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: Theme.of(context).colorScheme.primary,
                                  strokeWidth: 3.w,
                                ),
                                SizedBox(height: 12.h),
                                Text(
                                  "Loading wallet...",
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : walletProvider.walletAddress != null
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(16.r),
                            child: QrImageView(
                              data: walletProvider.walletAddress!,
                              version: QrVersions.auto,
                              size: 200.w,
                              backgroundColor: Colors.white,
                              padding: EdgeInsets.all(16.w),
                              errorStateBuilder: (context, error) {
                                return Center(
                                  child: Text(
                                    "Error generating QR code",
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                          : Center(
                            child: Icon(
                              CupertinoIcons.qrcode,
                              size: 120.sp,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                ),
              ),
              SizedBox(height: 16.h),
              Center(
                child: InkWell(
                  onTap: () {
                    if (walletProvider.walletAddress != null) {
                      Clipboard.setData(
                        ClipboardData(text: walletProvider.walletAddress!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Wallet address copied to clipboard"),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          walletProvider.displayAddress ?? 'No Address',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Icon(
                          Icons.copy,
                          size: 16.sp,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              Text(
                "Disclaimer: Wallet secrets are managed by Privy and are not exportable.",
                style: TextStyle(
                  fontSize: 14.sp,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}
