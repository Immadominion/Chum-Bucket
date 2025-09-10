import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_dimensions.dart';

/// Standard loading indicator
class LoadingIndicator extends StatelessWidget {
  final double? size;
  final Color? color;
  final String? message;

  const LoadingIndicator({super.key, this.size, this.color, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size ?? 24.w,
            height: size ?? 24.h,
            child: CircularProgressIndicator(
              color: color ?? AppColors.primary,
              strokeWidth: 2.5,
            ),
          ),
          if (message != null) ...[
            SizedBox(height: AppDimensions.paddingMedium),
            Text(
              message!,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Full screen loading overlay
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String? loadingMessage;
  final Color? overlayColor;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.loadingMessage,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: overlayColor ?? Colors.black.withOpacity(0.3),
            child: LoadingIndicator(
              message: loadingMessage,
              color: Colors.white,
            ),
          ),
      ],
    );
  }
}

/// Shimmer loading placeholder
class ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(
      begin: -1.0,
      end: 2.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius:
                widget.borderRadius ??
                BorderRadius.circular(AppDimensions.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (_animation.value - 1.0).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 1.0).clamp(0.0, 1.0),
              ],
              colors: [
                AppColors.surfaceVariant,
                AppColors.surfaceVariant.withOpacity(0.5),
                AppColors.surfaceVariant,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// List tile shimmer placeholder
class ShimmerListTile extends StatelessWidget {
  final bool showAvatar;
  final bool showTrailing;

  const ShimmerListTile({
    super.key,
    this.showAvatar = true,
    this.showTrailing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: AppDimensions.paddingSmall,
      ),
      child: Row(
        children: [
          if (showAvatar) ...[
            ShimmerPlaceholder(
              width: 40.w,
              height: 40.h,
              borderRadius: BorderRadius.circular(20),
            ),
            SizedBox(width: AppDimensions.paddingMedium),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder(width: double.infinity, height: 16.h),
                SizedBox(height: AppDimensions.paddingXSmall),
                ShimmerPlaceholder(width: 150.w, height: 12.h),
              ],
            ),
          ),
          if (showTrailing) ...[
            SizedBox(width: AppDimensions.paddingMedium),
            ShimmerPlaceholder(width: 60.w, height: 20.h),
          ],
        ],
      ),
    );
  }
}
