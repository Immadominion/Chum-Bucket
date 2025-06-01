import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:recess/screens/login/widgets/gmail_login_button.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  Lottie.asset(
                    'assets/animations/lottie/lottie.json',
                    width: MediaQuery.of(context).size.width * 1.5,
                    repeat: true,
                    frameRate: FrameRate.max,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),

            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(left: 12.w),
                        child: Image.asset(
                          'assets/images/ai_gen/logo/chum_transparent_bg_logo.png',
                          height: 170.h,
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
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ],
                  ),

                  Spacer(),
                  Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      children: [
                        const EmailLoginButton(),

                        Padding(
                          padding: EdgeInsets.all(16.w),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(150),
                                height: 1.5,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'By continuing, you agree to our ',
                                ),
                                TextSpan(
                                  text: 'Terms of Use',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  recognizer:
                                      TapGestureRecognizer()
                                        ..onTap = () {
                                          // Handle terms of use tap
                                        },
                                ),
                                const TextSpan(
                                  text: ' and have read and agreed to our ',
                                ),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
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
          ],
        ),
      ),
    );
  }
}
