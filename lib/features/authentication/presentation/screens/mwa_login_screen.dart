import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/mwa_connect_button.dart';
import 'package:chumbucket/core/theme/app_colors.dart';

/// MWA-based login screen for Solana Mobile compatibility
/// Replaces the email-based Privy login with wallet connection
class MwaLoginScreen extends StatelessWidget {
  const MwaLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // Animation section - flexible height
                  Flexible(
                    flex: 5,
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                        minHeight: 200.h,
                      ),
                      child: Lottie.asset(
                        'assets/animations/lottie/lottie.json',
                        width: MediaQuery.of(context).size.width * 1.2,
                        repeat: true,
                        frameRate: FrameRate.max,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  // Content section - takes remaining space
                  Flexible(
                    flex: 5,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Logo and text section
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(left: 12.w),
                                child: Image.asset(
                                  'assets/images/ai_gen/logo/chum_transparent_bg_logo.png',
                                  height: 140.h,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 32.w),
                                child: Text(
                                  "Challenge Your Friends, \nMake It Count",
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withAlpha(100),
                                    fontSize: 22.sp,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ],
                          ),

                          // Button and terms section
                          Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Column(
                              children: [
                                // MWA Connect Button (replaces email login)
                                const MwaConnectButton(),

                                SizedBox(height: 16.h),

                                Padding(
                                  padding: EdgeInsets.all(12.w),
                                  child: RichText(
                                    textAlign: TextAlign.center,
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontSize: 13.sp,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface.withAlpha(150),
                                        height: 1.4,
                                      ),
                                      children: [
                                        const TextSpan(
                                          text:
                                              'By continuing, you agree to our ',
                                        ),
                                        TextSpan(
                                          text: 'Terms of Use',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                          ),
                                          recognizer:
                                              TapGestureRecognizer()
                                                ..onTap = () {
                                                  // Handle terms of use tap
                                                },
                                        ),
                                        const TextSpan(
                                          text:
                                              ' and have read and agreed to our ',
                                        ),
                                        TextSpan(
                                          text: 'Privacy Policy',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                          ),
                                          recognizer:
                                              TapGestureRecognizer()
                                                ..onTap = () {
                                                  // Handle privacy policy tap
                                                },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Solana Mobile badge
                                _buildSolanaMobileBadge(context),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSolanaMobileBadge(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 16.sp,
            color: AppColors.solanaGreen,
          ),
          SizedBox(width: 6.w),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Powered by Solana Mobile',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.solanaGreen,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 4.w),
              Image.asset(
                'assets/images/solana-mobile.png',
                width: 12.w,
                height: 12.h,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
