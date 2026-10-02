import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/front_door_options.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/mwa_connect_button.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';

/// The first screen for anyone not signed in.
///
/// With the calls experience on (the people-first product), it is the one
/// account front door: Continue with wallet, Google or X — X only when the
/// project has it switched on — with the method this device last used marked
/// "Last used". A Google or X account needs no wallet to use the app.
///
/// Without it (the legacy challenge build), it stays the original wallet-only
/// door, unchanged.
class MwaLoginScreen extends StatelessWidget {
  const MwaLoginScreen({
    super.key,
    this.peopleFirst = AppConfig.callReceiptExperienceEnabled,
  });

  final bool peopleFirst;

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
                    flex: peopleFirst ? 4 : 5,
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: media.size.height * (peopleFirst ? .3 : .4),
                        minHeight: peopleFirst ? 140 : 200.h,
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
                    flex: peopleFirst ? 6 : 5,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          peopleFirst
                              ? const _PeopleFirstHeadline()
                              : _legacyHeadline(context),
                          Padding(
                            padding: EdgeInsets.all(peopleFirst ? 4 : 16.w),
                            child: Column(
                              children: [
                                if (peopleFirst)
                                  const FrontDoorOptions()
                                else
                                  const MwaConnectButton(),
                                SizedBox(height: peopleFirst ? 8 : 16.h),
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

class _PeopleFirstHeadline extends StatelessWidget {
  const _PeopleFirstHeadline();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/ai_gen/logo/chum_transparent_bg_logo.png',
          height: 72,
          fit: BoxFit.contain,
          semanticLabel: 'Chumbucket',
        ),
        const SizedBox(height: 12),
        Text(
          'See who called it.',
          style: AppTextStyles.pageTitle.copyWith(
            fontSize: 30,
            height: 1.15,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Follow the people making calls on real prediction markets. Back '
          'them, fade them, or make your own — calls are free, and every one '
          'gets a receipt when the market settles.',
          style: AppTextStyles.textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
