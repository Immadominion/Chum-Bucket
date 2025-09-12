import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/send_sol_sheet.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

/// Redesigned wallet balance card following the app's design system
class ProfileWalletCard extends StatelessWidget {
  const ProfileWalletCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26.r),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.2), offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with wallet icon and title
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  PhosphorIcons.wallet(),
                  size: 20.w,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                'Wallet Balance',
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),

          SizedBox(height: 16.h),

          // Balance display
          Consumer<WalletProvider>(
            builder: (context, walletProvider, _) {
              if (walletProvider.loadingState == LoadingState.loading) {
                return Row(
                  children: [
                    SizedBox(
                      width: 20.w,
                      height: 20.w,
                      child: CircularProgressIndicator(
                        color: const Color(0xFFFF5A76),
                        strokeWidth: 2.w,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main balance with reload icon
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${walletProvider.balance.toStringAsFixed(2)} SOL',
                        style: TextStyle(
                          fontSize: 28.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      GestureDetector(
                        onTap: () {
                          walletProvider.refreshBalance();
                        },
                        child: Icon(
                          PhosphorIcons.arrowsClockwise(),
                          size: 18.w,
                          color: const Color(0xFFFF5A76),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  // Wallet address (shortened) and disclaimer
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (walletProvider.walletAddress != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: ResolvedAddressText(
                                addressOrLabel: walletProvider.walletAddress!,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            GestureDetector(
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: walletProvider.walletAddress!,
                                  ),
                                );
                                if (context.mounted) {
                                  SnackBarUtils.showInfo(
                                    context,
                                    title: 'Wallet Address Copied',
                                    subtitle:
                                        'The wallet address has been copied to your clipboard.',
                                  );
                                }
                              },
                              child: Icon(
                                PhosphorIcons.copySimple(),
                                size: 14.w,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Spacer(),
                          ],
                        ),
                      SizedBox(height: 8.h),
                      Text(
                        "All funds are stored in Solana. Amount may fluctuate.",
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 20.h),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ChallengeButton(
                          createNewChallenge: () => showSendSolSheet(context),
                          label: 'Withdraw',
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: _buildSecondaryButton(
                          'Add SOL',
                          () => showWalletModal(context),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryButton(String text, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 14.h),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
