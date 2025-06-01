import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/config/theme/app_theme.dart';
import 'package:recess/screens/splash/widgets/splash_animations.dart';

class BucketWidget extends StatelessWidget {
  final SplashAnimations animations;

  const BucketWidget({super.key, required this.animations});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animations.bucketController,
      builder: (context, child) {
        return SlideTransition(
          position: animations.bucketSlideAnimation,
          child: Transform.rotate(
            angle: animations.bucketRotationAnimation.value,
            child: Transform.scale(
              scale:
                  animations.bucketScaleAnimation.value *
                  (1.0 + (animations.bucketBounceAnimation.value * 0.1)),
              child: SizedBox(
                width: 200.w,
                height: 300.w,
                child: Image.asset(
                  'assets/images/ai_gen/logo/bucket_logo.png',
                  fit: BoxFit.fitHeight,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.home,
                      size: 200.w,
                      color: AppColors.primary,
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

