import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/screens/splash/widgets/splash_animations.dart';

class ChumTextLogo extends StatelessWidget {
  final SplashAnimations animations;

  const ChumTextLogo({super.key, required this.animations});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animations.textController,
      builder: (context, child) {
        return SlideTransition(
          position: animations.textSlideAnimation,
          child: Transform.scale(
            scale: animations.textScaleAnimation.value,
            child: Opacity(
              opacity: animations.textFadeAnimation.value,
              child: SizedBox(
                height: 100.h,
                child: Image.asset(
                  'assets/images/ai_gen/logo/chum_text.png',
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        'THE CHUM BUCKET',
                        style: TextStyle(
                          fontSize: 50.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
