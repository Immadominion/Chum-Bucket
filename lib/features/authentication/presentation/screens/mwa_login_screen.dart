import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/mwa_connect_button.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';

/// The legacy challenge build's wallet-only door (`CALL_RECEIPT_EXPERIENCE`
/// off), unchanged. The calls product signs in from onboarding instead —
/// "Welcome back" and the sign-in step (`features/onboarding/`), where the
/// wallet / Google / X doors appear at the moment they are needed.
class MwaLoginScreen extends StatelessWidget {
  const MwaLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  media.size.height - media.padding.top - media.padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // Animation section - flexible height
                  Flexible(
                    flex: 5,
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: media.size.height * .4,
                        minHeight: 200.h,
                      ),
                      child: Lottie.asset(
                        'assets/animations/lottie/lottie.json',
                        width: media.size.width * 1.2,
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
                          _legacyHeadline(context),
                          Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Column(
                              children: [
                                const MwaConnectButton(),
                                SizedBox(height: 16.h),
                                _terms(context),
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

  Widget _legacyHeadline(BuildContext context) => Column(
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
            color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
            fontSize: 22.sp,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
          textAlign: TextAlign.left,
        ),
      ),
    ],
  );

  Widget _terms(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: RichText(
      textAlign: TextAlign.center,
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
          height: 1.4,
        ),
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms of Use',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            recognizer:
                TapGestureRecognizer()
                  ..onTap = () => openExternalLink(context, LegalLinks.terms),
          ),
          const TextSpan(text: ' and have read and agreed to our '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            recognizer:
                TapGestureRecognizer()
                  ..onTap = () => openExternalLink(context, LegalLinks.privacy),
          ),
        ],
      ),
    ),
  );

  Widget _buildSolanaMobileBadge(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BasilIcon(
            'shield-outline',
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
