import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';

/// The single floating sheet treatment used by new Chumbucket flows.
class ChumbucketWavySheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final double? height;
  final double headerHeight;
  final Widget? headerLeading;
  final Widget? headerTrailing;

  const ChumbucketWavySheet({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.height,
    this.headerHeight = 164,
    this.headerLeading,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.padding.top - 28.h;
    final sheetHeight = (height ?? availableHeight * 0.72).clamp(
      320.h,
      availableHeight,
    );

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
            12.w,
            12.h,
            12.w,
            media.viewInsets.bottom + 14.h,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: sheetHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(43.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 44,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SizedBox(
                    height: headerHeight.h,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.lightPrimary,
                                AppColors.primary,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10.h,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 43.w,
                              height: 4.h,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.38),
                                borderRadius: BorderRadius.circular(2.r),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 32.h,
                          left: 24.w,
                          right: 24.w,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (headerLeading != null) ...[
                                headerLeading!,
                                SizedBox(width: 12.w),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22.sp,
                                        height: 1.15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (subtitle != null) ...[
                                      SizedBox(height: 6.h),
                                      Text(
                                        subtitle!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.86,
                                          ),
                                          fontSize: 13.sp,
                                          height: 1.35,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (headerTrailing != null) ...[
                                SizedBox(width: 8.w),
                                headerTrailing!,
                              ],
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -1,
                          child: ClipPath(
                            clipper: DetailedWaveClipper(),
                            child: Container(height: 42.h, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: Material(color: Colors.white, child: body)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showChumbucketWavySheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    elevation: 0,
    builder: builder,
  );
}
