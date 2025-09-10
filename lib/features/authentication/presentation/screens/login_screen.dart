import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/gmail_login_button.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

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
                                  height: 140.h, // Reduced from 170.h
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
                                    fontSize: 22.sp, // Reduced from 24.sp
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
                                const EmailLoginButton(),

                                Padding(
                                  padding: EdgeInsets.all(
                                    12.w,
                                  ), // Reduced from 16.w
                                  child: RichText(
                                    textAlign: TextAlign.center,
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontSize: 13.sp, // Reduced from 14.sp
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface.withAlpha(150),
                                        height: 1.4, // Reduced from 1.5
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
}
