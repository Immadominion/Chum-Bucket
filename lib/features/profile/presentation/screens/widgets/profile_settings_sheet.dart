import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_menu_item.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/core/services/chat_service.dart';

/// Settings modal sheet following the app's design conventions
class ProfileSettingsSheet extends StatelessWidget {
  const ProfileSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 400.h;
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
      child: Stack(
        children: [
          Column(
            children: [
              // Header with gradient background and wave
              Container(
                height: 220.h.clamp(160.h, maxHeight * 0.35),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(43.r),
                    topRight: Radius.circular(43.r),
                  ),
                ),
                child: Stack(
                  children: [
                    // Gradient header
                    Container(
                      width: double.infinity,
                      height: 220.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(43.r),
                          topRight: Radius.circular(43.r),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          SizedBox(height: 24.h),
                          // Settings title
                          Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // Main title
                          Text(
                            'Account & Support',
                            style: TextStyle(
                              fontSize: 24.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // White wavy section
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipPath(
                        clipper: DetailedWaveClipper(),
                        child: Container(height: 130.h, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 130.h,
            bottom: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 0.h),
              child: Column(
                children: [
                  // Menu items - scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Consumer<WalletProvider>(
                            builder: (context, walletProvider, _) {
                              return ProfileMenuItem(
                                icon: PhosphorIcons.wallet(),
                                title: 'My Wallet',
                                subtitle:
                                    walletProvider.walletAddress != null
                                        ? 'Export your private key'
                                        : 'Loading...',
                                iconColor: const Color(0xFFFF5A76),
                                onTap: () => _showExportWarning(context),
                              );
                            },
                          ),

                          ProfileMenuItem(
                            icon: PhosphorIcons.star(),
                            title: 'Rate Chum Bucket',
                            subtitle: 'Share your experience',
                            iconColor: Colors.amber,
                            onTap: () {},
                          ),

                          ProfileMenuItem(
                            icon: PhosphorIcons.question(),
                            title: 'Talk To Support',
                            subtitle: 'Get help when you need it',
                            iconColor: Colors.blue,
                            onTap: () => _openTawkToSupport(context),
                            iconSize: 30,
                          ),

                          ProfileMenuItem(
                            icon: PhosphorIcons.trash(),
                            title: 'Delete Your Account',
                            subtitle: 'Permanently remove your account',
                            isDanger: true,
                            onTap: () {},
                          ),

                          SizedBox(height: 16.h),
                        ],
                      ),
                    ),
                  ),

                  // Fixed bottom buttons
                  ChallengeButton(
                    createNewChallenge: () async {
                      final authProvider = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      );
                      await authProvider.clearUserData();

                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      }
                    },
                    label: 'Sign Out',
                  ),

                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 17.sp,
                        color: const Color(0xFFFF5A76),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Open Tawk.to support chat in external browser
  void _openTawkToSupport(BuildContext context) {
    // Close the current sheet first
    Navigator.pop(context);
    // Open chat in external browser to avoid webview privacy manifest requirements
    ChatService.openChat();
  }

  /// Wallet Management Sheet for wallet export/copy functionality

  void _showExportWarning(BuildContext context) {
    Navigator.pop(context); // Close current sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      elevation: 0,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
          child: const SafeArea(child: WalletExportWarningSheet()),
        );
      },
    );
  }
}

/// Warning sheet for wallet export
class WalletExportWarningSheet extends StatefulWidget {
  const WalletExportWarningSheet({super.key});

  @override
  State<WalletExportWarningSheet> createState() =>
      _WalletExportWarningSheetState();
}

class _WalletExportWarningSheetState extends State<WalletExportWarningSheet> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 350.h;
    final preferredHeight = 500.h;
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
      child: Stack(
        children: [
          Column(
            children: [
              // Header with gradient background and wave
              Container(
                height: 180.h.clamp(140.h, maxHeight * 0.35),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(43.r),
                    topRight: Radius.circular(43.r),
                  ),
                ),
                child: Stack(
                  children: [
                    // Warning gradient header
                    Container(
                      width: double.infinity,
                      height: 180.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.red],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(43.r),
                          topRight: Radius.circular(43.r),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          SizedBox(height: 24.h),
                          // Warning icon
                          Icon(
                            PhosphorIcons.smileyNervous(),
                            size: 80.w,
                            color: AppColors.challengeFailed,
                          ),

                          SizedBox(height: 12.h),
                          // Title
                          Text(
                            'Export Wallet 💀',
                            style: TextStyle(
                              fontSize: 24.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // White wavy section
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipPath(
                        clipper: DetailedWaveClipper(),
                        child: Container(height: 40.h, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 160.h,
            bottom: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
              child: Column(
                children: [
                  SizedBox(height: 20.h),
                  Text(
                    'Are you sure you want to export your wallet secret phrase?',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'We cannot guarantee the security of your account after you export your secret phrase. Please store it securely and never share it with anyone.',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Action buttons
                  _isLoading
                      ? Container(
                        width: double.infinity,
                        height: 56.h,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                          ),
                          borderRadius: BorderRadius.circular(28.r),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Text(
                                'Exporting...',
                                style: TextStyle(
                                  fontSize: 17.sp,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      : ChallengeButton(
                        createNewChallenge: _attemptWalletExport,
                        label: 'Export Wallet',
                        hasGradient: true,
                      ),

                  SizedBox(height: 8.h),

                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 17.sp,
                        color: const Color(0xFFFF5A76),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _attemptWalletExport() async {
    if (_isLoading) return;

    Navigator.pop(context);
    SnackBarUtils.showInfo(
      context,
      title: 'Coming Soon...',
      subtitle: 'This feature is under development.',
    );

    //TODO: Work on wallet export functionality
    // setState(() {
    //   _isLoading = true;
    // });

    // try {
    //   final walletProvider = Provider.of<WalletProvider>(
    //     context,
    //     listen: false,
    //   );

    //   final walletAddress = walletProvider.walletAddress;
    //   if (walletAddress == null) {
    //     throw Exception('No wallet address available');
    //   }

    //   // Simulate wallet export attempt (since Privy may not allow direct export)
    //   await Future.delayed(const Duration(seconds: 2));

    //   if (!mounted) return;

    //   // For now, show that full export is not available but address can be copied
    //   Navigator.pop(context);
    //   await Future.delayed(const Duration(milliseconds: 100));

    //   if (mounted) {
    //     _showWalletCopyOptions(context);
    //   }
    // } catch (e) {
    //   if (!mounted) return;

    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: Text('Export failed: $e'),
    //       backgroundColor: Colors.red,
    //     ),
    //   );

    //   // Close current sheet and show address copy as fallback
    //   Navigator.pop(context);
    //   await Future.delayed(const Duration(milliseconds: 100));

    //   if (mounted) {
    //     _showWalletCopyOptions(context);
    //   }
    // } finally {
    //   if (mounted) {
    //     setState(() {
    //       _isLoading = false;
    //     });
    //   }
    // }
  }
}

/// Sheet for copying wallet address (alternative to full export)
class WalletCopySheet extends StatelessWidget {
  final String walletAddress;

  const WalletCopySheet({super.key, required this.walletAddress});

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 350.h;
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
      child: Stack(
        children: [
          Column(
            children: [
              // Header with gradient background and wave
              Container(
                height: 180.h.clamp(140.h, maxHeight * 0.35),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(43.r),
                    topRight: Radius.circular(43.r),
                  ),
                ),
                child: Stack(
                  children: [
                    // Success gradient header
                    Container(
                      width: double.infinity,
                      height: 180.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.green, Colors.teal],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(43.r),
                          topRight: Radius.circular(43.r),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          SizedBox(height: 24.h),
                          // Copy icon
                          Icon(
                            PhosphorIcons.copy(),
                            size: 80.w,
                            color: Colors.white,
                          ),
                          SizedBox(height: 12.h),
                          // Title
                          Text(
                            'Wallet Address',
                            style: TextStyle(
                              fontSize: 24.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // White wavy section
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipPath(
                        clipper: DetailedWaveClipper(),
                        child: Container(height: 40.h, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 160.h,
            bottom: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
              child: Column(
                children: [
                  SizedBox(height: 20.h),
                  Text(
                    'Your Wallet Address',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16.h),

                  // Wallet address display
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SelectableText(
                      walletAddress,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontFamily: 'monospace',
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  SizedBox(height: 16.h),

                  Text(
                    'Full wallet export is not available through the mobile app for security reasons. You can copy your address above.',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Copy button
                  ChallengeButton(
                    createNewChallenge: () async {
                      await Clipboard.setData(
                        ClipboardData(text: walletAddress),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Wallet address copied to clipboard'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    label: 'Copy Address',
                    hasGradient: false,
                  ),

                  SizedBox(height: 8.h),

                  // Close button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 17.sp,
                        color: const Color(0xFFFF5A76),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet showing that wallet export is not available
class WalletExportNotAvailableSheet extends StatelessWidget {
  const WalletExportNotAvailableSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 350.h;
    final preferredHeight = 500.h;
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
      child: Stack(
        children: [
          Column(
            children: [
              // Header with gradient background and wave
              Container(
                height: 180.h.clamp(140.h, maxHeight * 0.35),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(43.r),
                    topRight: Radius.circular(43.r),
                  ),
                ),
                child: Stack(
                  children: [
                    // Info gradient header
                    Container(
                      width: double.infinity,
                      height: 180.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.blue, Colors.indigo],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(43.r),
                          topRight: Radius.circular(43.r),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          SizedBox(height: 24.h),
                          // Info icon
                          Icon(
                            PhosphorIcons.info(),
                            size: 80.w,
                            color: Colors.white,
                          ),
                          SizedBox(height: 12.h),
                          // Title
                          Text(
                            'Export Not Available',
                            style: TextStyle(
                              fontSize: 24.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // White wavy section
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipPath(
                        clipper: DetailedWaveClipper(),
                        child: Container(height: 40.h, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 160.h,
            bottom: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
              child: Column(
                children: [
                  SizedBox(height: 20.h),
                  Text(
                    'Your holdings are held in cryptocurrency wallets in your custody.',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'You can directly control your wallets using your secret phrase, but wallet export is currently not available through the mobile app. Your wallet secrets are managed securely by Privy.',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(),

                  // Close button
                  ChallengeButton(
                    createNewChallenge: () => Navigator.pop(context),
                    label: 'Got It',
                    hasGradient: false,
                  ),

                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Function to show the settings sheet with backdrop blur
Future<void> showProfileSettingsSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    elevation: 0,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
        child: const SafeArea(child: ProfileSettingsSheet()),
      );
    },
  );
}
