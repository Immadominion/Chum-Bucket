import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AnimatedOnboardingImage extends StatelessWidget {
  final String illustration;
  final bool isAnimated;
  final String? fallback;

  const AnimatedOnboardingImage({
    super.key,
    required this.illustration,
    required this.isAnimated,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    // Cache screen size to avoid repeated MediaQuery calls
    final screenWidth = MediaQuery.of(context).size.width;

    return isAnimated
        // For animated content, make it fill full screen width with more height
        ? ClipRRect(
          borderRadius: BorderRadius.circular(24.r),
          child: Container(
            width: screenWidth, // Full screen width
            height: 270.h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24.r),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(child: _buildAnimatedImage(context)),
          ),
        )
        // For static images, make it fill screen width while keeping circular shape
        : Container(
          width: screenWidth,
          height: 270.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24.r),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Image.asset(
            illustration,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withOpacity(0.8),
                      Theme.of(context).colorScheme.primary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  Icons.fitness_center,
                  size: 100.w,
                  color: Colors.white,
                ),
              );
            },
          ),
        );
  }

  // Widget to handle animated GIF display with fallback to static image
  Widget _buildAnimatedImage(context) {
    try {
      if (isAnimated) {
        // Use precacheImage for better performance with GIFs
        return Image.asset(
          illustration,
          fit: BoxFit.cover,
          gaplessPlayback: true, // Ensures smooth playback of GIF
          cacheHeight: 600, // Optimize memory usage with explicit dimensions
          cacheWidth: 800,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // Use fade-in animation only when loading asynchronously
            if (wasSynchronouslyLoaded) return child;

            return AnimatedOpacity(
              opacity: frame != null ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // Try to load a static fallback image instead
            return fallback != null
                ? Image.asset(
                  fallback!,
                  fit: BoxFit.cover,
                  cacheHeight: 600,
                  cacheWidth: 800,
                  errorBuilder: (context, __, ___) => _buildErrorPlaceholder(context),
                )
                : _buildErrorPlaceholder(context);
          },
        );
      } else {
        return Image.asset(
          illustration,
          fit: BoxFit.cover,
          cacheHeight: 600,
          cacheWidth: 800,
          errorBuilder: (_, __, ___) => _buildErrorPlaceholder(context),
        );
      }
    } catch (e) {
      print("Exception while loading animated image: $e");
      return _buildErrorPlaceholder(context);
    }
  }

  // Helper method for building the error placeholder
  Widget _buildErrorPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary.withOpacity(0.8), Theme.of(context).colorScheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64.w, color: Colors.white),
            SizedBox(height: 8.h),
            Text(
              "Image not available",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
