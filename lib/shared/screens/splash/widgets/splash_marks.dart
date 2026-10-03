/// The brand marks the splash and onboarding's brand band draw, cropped
/// out of their PNGs' transparent margins so they sit exactly where (and
/// as big as) the layout says.
library;

import 'package:flutter/material.dart';

/// The bucket from `bucket_logo.png`, cropped to its drawing (the PNG has
/// wide transparent margins). At its default [width] it is the size the
/// native launch window shows the launcher foreground: 121dp wide.
/// Onboarding's brand band uses the same crop, smaller.
class SplashBucket extends StatelessWidget {
  const SplashBucket({super.key, this.size = width});

  static const double width = 121;
  static const double height = 114;

  /// The width to draw at; the height follows the drawing's proportions.
  final double size;

  // The drawing's box inside the 1024x1536 source, measured from its alpha:
  // 706 wide at (200, 320).
  double get _scale => size / 706;

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    return SizedBox(
      width: size,
      height: size * height / width,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: 1024 * scale,
          maxHeight: 1536 * scale,
          child: Transform.translate(
            offset: Offset(-200 * scale, -320 * scale),
            child: Image.asset(
              'assets/images/ai_gen/logo/bucket_logo.png',
              width: 1024 * scale,
              height: 1536 * scale,
              fit: BoxFit.fill,
              // Decoded at the size it is drawn, not 1024x1536.
              cacheWidth: (1024 * scale * dpr).ceil().clamp(64, 1024),
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// "The Chum Bucket" lettering, cropped to its drawing, 180dp wide.
class SplashWordmark extends StatelessWidget {
  const SplashWordmark({super.key});

  static const double width = 180;
  static const double _scale = width / 862;
  static const double height = 526 * _scale;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: 1024 * _scale,
        maxHeight: 1024 * _scale,
        child: Transform.translate(
          offset: const Offset(-88 * _scale, -240 * _scale),
          child: Image.asset(
            'assets/images/ai_gen/logo/chum_text.png',
            width: 1024 * _scale,
            height: 1024 * _scale,
            fit: BoxFit.fill,
            cacheWidth: 640,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}
