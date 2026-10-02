import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';

/// Brand header shared by every app-owned modal sheet.
///
/// Built to the reference comp
/// (`assets/images/open_sourced_design_inspiration/irfan/img2.jpeg`), whose
/// pixels were measured and converted at 390dp. Top to bottom: a short white
/// handle, a muted caption, the one value the sheet is about, then the
/// scalloped edge into white — with avatars, when there are any, straddling
/// that edge.
///
/// There is no close button: the comp has none. A sheet closes by dragging
/// its header down, tapping the handle or the backdrop, or system Back — all
/// of them honour a busy sheet ([canClose] false).
class ChumbucketSheetHeader extends StatelessWidget {
  const ChumbucketSheetHeader({
    super.key,
    required this.title,
    this.value,
    this.subtitle,
    this.leading,
    this.leadingAvatarDiameter = 92,
    this.onClose,
    this.canClose = true,
  });

  /// The sheet's name. Large when [value] is absent; the small muted caption
  /// above [value] when it is present ("Bet Amount").
  final String title;

  /// The hero the sheet is about — an amount, a price, a count.
  final String? value;

  final String? subtitle;

  /// Centred on the scallop — the comp's pair of avatars, or a single one.
  final Widget? leading;

  /// The avatar circle's diameter inside [leading]. The scallop's cusps cross
  /// it 47.5% of the way down, as on the comp.
  final double leadingAvatarDiameter;

  /// Tapping the handle closes the sheet; screen readers announce it as Close.
  final VoidCallback? onClose;
  final bool canClose;

  // ---- Measured rhythm (dp from the sheet's top edge on the comp) ----------
  //   handle 7-9.8 · caption cap-top 51 · value glyph top 78 · avatar top 166
  //   · scallop cusps 209.7 (crests 202.4).
  static const double _handleTop = 7;
  static const double _handleWidth = 38;
  static const double _handleHeight = 2.8;
  static const double _handleToText = 37.3;
  static const double _captionToValue = 8.9;
  static const double _toSubtitle = 8;
  static const double _textToWave = 26;
  static const double _valueToLeading = 39.7;
  static const double _horizontalInset = 28;

  /// The cusp line sits this far down the avatar circle.
  static const double _cuspFraction = .475;

  /// The gradient runs #FF5A76 -> #FF3355 over this span from the top edge,
  /// whatever the header's height. On the comp the pink at the scallop
  /// (206dp down) is (255,63,100): 69% of the way along a ~300dp gradient.
  static const double _gradientSpan = 300;

  double naturalHeight(BuildContext context, double width) {
    final textWidth = (width - _horizontalInset * 2).clamp(
      1.0,
      double.infinity,
    );
    double measure(String text, TextStyle style, {double? maxScale}) {
      var scaler = MediaQuery.textScalerOf(context);
      if (maxScale != null) scaler = scaler.clamp(maxScaleFactor: maxScale);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textAlign: TextAlign.center,
        textScaler: scaler,
      )..layout(maxWidth: textWidth);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    var height = _handleTop + _handleHeight + _handleToText;
    if (value == null) {
      height += measure(title, AppTextStyles.sheetTitleOnBrand);
    } else {
      height +=
          measure(title, AppTextStyles.sheetCaption) +
          _captionToValue +
          measure(value!, AppTextStyles.sheetValue, maxScale: 1.5);
    }
    if (subtitle != null) {
      height +=
          _toSubtitle + measure(subtitle!, AppTextStyles.sheetSubtitleOnBrand);
    }
    if (leading != null) {
      // Avatar circle, gap and one name line, which grows with the scaler.
      return height +
          _valueToLeading +
          leadingAvatarDiameter +
          12 +
          measure('Name', AppTextStyles.sheetPersonName);
    }
    return height + _textToWave + ChumbucketSheetWave.height;
  }

  @override
  Widget build(BuildContext context) {
    void close() =>
        onClose != null ? onClose!() : Navigator.of(context).maybePop();
    return Stack(
      children: [
        // Past the gradient's span the header is solid #FF3355.
        const Positioned.fill(child: ColoredBox(color: AppColors.primary)),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _gradientSpan,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.lightPrimary, AppColors.primary],
              ),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: _handleTop),
            Center(
              child: Container(
                key: const ValueKey('chumbucket-sheet-handle'),
                width: _handleWidth,
                height: _handleHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: _handleToText),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _horizontalInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value == null)
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.sheetTitleOnBrand,
                      ),
                    )
                  else ...[
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.sheetCaption,
                      ),
                    ),
                    const SizedBox(height: _captionToValue),
                    Text(
                      value!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sheetValue,
                      // 48sp at 2x would wrap and push the header past half
                      // the sheet; at 1.5x it is still the largest thing here.
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.5),
                    ),
                  ],
                  if (subtitle != null) ...[
                    const SizedBox(height: _toSubtitle),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sheetSubtitleOnBrand,
                    ),
                  ],
                ],
              ),
            ),
            if (leading == null) ...[
              const SizedBox(height: _textToWave),
              const ChumbucketSheetWave(),
            ] else ...[
              const SizedBox(height: _valueToLeading),
              _straddle(),
            ],
          ],
        ),
        // The handle's touch target: 88x48 over a 38x2.8 mark, so the visible
        // handle stays the comp's while the target meets the 48dp minimum.
        // It is also the sheet's Close action for screen readers.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 48,
          child: Center(
            child: Semantics(
              button: true,
              label: 'Close',
              enabled: canClose,
              onTap: canClose ? close : null,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('chumbucket-sheet-close-target'),
                behavior: HitTestBehavior.opaque,
                onTap: canClose ? close : null,
                child: const SizedBox(width: 88, height: 48),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The comp's signature: the avatars sit ON the scallop — upper part on the
  /// gradient, lower part and the names on white — and the scallop runs
  /// behind them.
  Widget _straddle() {
    final bandTop =
        leadingAvatarDiameter * _cuspFraction - DetailedWaveClipper.cuspY;
    return Stack(
      children: [
        // A hairline of overlap: butting white exactly against the clipped
        // scallop leaves a 1px seam where the clip antialiases.
        Positioned(
          top: bandTop + ChumbucketSheetWave.height - 1,
          left: 0,
          right: 0,
          bottom: 0,
          child: const ColoredBox(color: AppColors.surface),
        ),
        Positioned(
          top: bandTop,
          left: 0,
          right: 0,
          child: const ChumbucketSheetWave(),
        ),
        // `leading` is the only non-positioned child, so it sizes the Stack.
        Center(child: leading!),
      ],
    );
  }
}

/// The scallop band itself: white below the edge, transparent above it so the
/// header gradient shows through between the arches.
class ChumbucketSheetWave extends StatelessWidget {
  const ChumbucketSheetWave({super.key});

  static const double height = DetailedWaveClipper.minBoxHeight + 1;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipPath(
      clipper: DetailedWaveClipper(),
      child: const SizedBox(
        height: height,
        width: double.infinity,
        child: ColoredBox(color: AppColors.surface),
      ),
    ),
  );
}
