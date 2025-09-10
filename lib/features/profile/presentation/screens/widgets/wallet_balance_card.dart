import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_buttons.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';

class WalletBalanceCard extends StatelessWidget {
  const WalletBalanceCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showWalletModal(context),
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.05),
              Theme.of(context).colorScheme.primary.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    CupertinoIcons.money_dollar,
                    size: 20.sp,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(width: 12.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Current Balance",
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    Consumer<WalletProvider>(
                      builder: (context, walletProvider, _) {
                        return walletProvider.loadingState ==
                                LoadingState.loading
                            ? Row(
                              children: [
                                SizedBox(
                                  width: 24.w,
                                  height: 24.w,
                                  child: CircularProgressIndicator(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    strokeWidth: 2.w,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  "Loading...",
                                  style: TextStyle(
                                    fontSize: 24.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            )
                            : Text(
                              "${walletProvider.balance.toStringAsFixed(2)} SOL",
                              style: TextStyle(
                                fontSize: 30.sp,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            );
                      },
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GradientButton(
                        text: "Cash Out",
                        onPressed: () {},
                        icon: CupertinoIcons.arrow_up_circle,
                        gradientColors: [
                          AppColors.gradientMiddle,
                          AppColors.gradientEnd,
                        ],
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: SecondaryButton(
                        text: "Add Cash",
                        onPressed: () {
                          _showWalletModal(context);
                        },
                        icon: CupertinoIcons.add_circled,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                // Airdrop button specifically for testnet usage
                Consumer<WalletProvider>(
                  builder: (context, walletProvider, _) {
                    return OutlinedButton(
                      onPressed:
                          walletProvider.loadingState == LoadingState.loading
                              ? null
                              : () async {
                                // Open a dialog to show the result
                                try {
                                  // Display a loading indicator
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder:
                                        (context) => const AlertDialog(
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(height: 16),
                                              Text("Requesting SOL airdrop..."),
                                            ],
                                          ),
                                        ),
                                  );

                                  // Call airdrop function (you'll need to implement this)
                                  final result =
                                      await walletProvider.requestAirdrop();

                                  // Close loading dialog
                                  Navigator.of(context).pop();

                                  // Show result
                                  if (result) {
                                    showDialog(
                                      context: context,
                                      builder:
                                          (context) => AlertDialog(
                                            title: const Text(
                                              "Airdrop Success",
                                            ),
                                            content: const Text(
                                              "SOL has been added to your wallet!",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () =>
                                                        Navigator.pop(context),
                                                child: const Text("OK"),
                                              ),
                                            ],
                                          ),
                                    );
                                  } else {
                                    showDialog(
                                      context: context,
                                      builder:
                                          (context) => AlertDialog(
                                            title: const Text("Airdrop Failed"),
                                            content: const Text(
                                              "Could not add SOL to your wallet. Please try again later.",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () =>
                                                        Navigator.pop(context),
                                                child: const Text("OK"),
                                              ),
                                            ],
                                          ),
                                    );
                                  }
                                } catch (e) {
                                  // Close loading dialog if open
                                  Navigator.of(context).pop();

                                  // Show error
                                  showDialog(
                                    context: context,
                                    builder:
                                        (context) => AlertDialog(
                                          title: const Text("Error"),
                                          content: Text(
                                            "An error occurred: $e",
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(context),
                                              child: const Text("OK"),
                                            ),
                                          ],
                                        ),
                                  );
                                }
                              },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6.h),
                        child: Text(
                          "Request Testnet SOL Airdrop",
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Text(
              "All funds are stored in Solana. Amount may fluctuate.",
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWalletModal(BuildContext context) {
    // Get the wallet provider first to ensure it's available to the modal
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    // Ensure we have the wallet address
    if (walletProvider.walletAddress == null) {
      walletProvider.refreshBalance();
    }

    // Show the modal with the explicit provider
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (BuildContext modalContext) {
        // Return the modal with an explicit provider to avoid context issues
        return ChangeNotifierProvider<WalletProvider>.value(
          value: walletProvider,
          child: const WalletModal(),
        );
      },
    );
  }
}
