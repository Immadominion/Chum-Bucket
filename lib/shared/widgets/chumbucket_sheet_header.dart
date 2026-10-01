import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Brand header shared by every app-owned modal sheet. Content determines its
/// height; callers never position text underneath an absolutely placed wave.
class ChumbucketSheetHeader extends StatelessWidget {
  const ChumbucketSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onClose,
    this.canClose = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onClose;
  final bool canClose;

  double naturalHeight(BuildContext context, double width) {
    final textWidth = (width - 88 - (leading == null ? 0 : 60)).clamp(
      1.0,
      double.infinity,
    );
    double measure(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: textWidth);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final content =
        9 +
        measure(title, AppTextStyles.sheetTitle) +
        (subtitle == null
            ? 0
            : 6 +
                measure(
                  subtitle!,
                  AppTextStyles.textTheme.bodyMedium!.copyWith(height: 1.4),
                ));
    return 60 + (content < 48 ? 48 : content);
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.lightPrimary, AppColors.primary],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                SizedBox(width: 48, height: 48, child: leading!),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: AppTextStyles.sheetTitle),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Close',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed:
                    canClose
                        ? onClose ?? () => Navigator.of(context).maybePop()
                        : null,
                icon: const BasilIcon(
                  'cross-outline',
                  size: 22,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const ChumbucketSheetWave(),
      ],
    ),
  );
}

/// Fixed-depth scallop: never derive amplitude from a caller's header height.
class ChumbucketSheetWave extends StatelessWidget {
  const ChumbucketSheetWave({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipPath(
      clipper: DetailedWaveClipper(),
      child: const SizedBox(
        height: 24,
        width: double.infinity,
        child: ColoredBox(color: AppColors.surface),
      ),
    ),
  );
}
