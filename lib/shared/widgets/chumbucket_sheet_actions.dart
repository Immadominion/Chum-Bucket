import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';

/// The call to action from the reference comp
/// (`assets/images/open_sourced_design_inspiration/irfan/img2.jpeg`).
///
/// Measured off the comp's pixels and converted at 390dp, not eyeballed:
///
///  * 57dp tall, 22dp corner radius (a rounded rectangle, not a pill);
///  * the gradient runs TOP to BOTTOM, `#FF5A76 -> #FF3355` — every row of the
///    comp's button is one colour edge to edge, lighter at the top;
///  * a glossy lower lip: over its last 4.5dp the comp's button brightens again
///    from #FF3355 back toward #FF5A76, over a tight dark edge — that is what
///    gives it its slight depth (there is no soft drop shadow: the comp is
///    near-white 1dp below the edge);
///  * a white Inter Bold label.
///
/// [ChallengeButton] and the primary `CallJourneyButton` both render through
/// this, so the primary action in every sheet is the same button.
class ChumbucketPrimaryButton extends StatelessWidget {
  const ChumbucketPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Shows a spinner and swallows taps, without changing the button's size.
  final bool busy;
  final String? busyLabel;
  final Widget? leading;

  static const double height = 57;
  static const double radius = 22;

  /// Where the lower lip begins, as a fraction of the 57dp height (4.5dp up).
  static const double lipStart = (height - 4.5) / height;
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.lightPrimary, AppColors.primary],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: busy ? (busyLabel ?? label) : label,
      // The label stands in for the subtree, so the tap has to as well, or a
      // screen reader could announce the button but not press it.
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Opacity(
        // A disabled action keeps its shape and colour, at half strength.
        opacity: onPressed == null && !busy ? .5 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: height),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              // The comp's darker edge line, right under the button.
              BoxShadow(
                color: Color(0x40A3203C),
                blurRadius: 1,
                offset: Offset(0, 1),
              ),
            ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // The lip: transparent until the last 4.5dp, then up to the
              // gradient's light colour at the very edge.
              stops: [0, lipStart, 1],
              colors: [
                Color(0x00FF5A76),
                Color(0x00FF5A76),
                AppColors.lightPrimary,
              ],
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(radius),
              splashColor: Colors.white.withValues(alpha: .16),
              highlightColor: Colors.white.withValues(alpha: .08),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ] else if (leading != null) ...[
                      IconTheme.merge(
                        data: const IconThemeData(color: Colors.white),
                        child: leading!,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        busy ? (busyLabel ?? label) : label,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.sheetAction,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The text-only action under the call to action — the comp's
/// "Failed to complete": Inter SemiBold in brand pink, no fill, no border.
class ChumbucketTextAction extends StatelessWidget {
  const ChumbucketTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Defaults to brand pink. Pass a neutral for a non-destructive dismissal.
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      foregroundColor: color ?? AppColors.primary,
      overlayColor: (color ?? AppColors.primary).withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ChumbucketPrimaryButton.radius),
      ),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: AppTextStyles.sheetTextAction.copyWith(
        color: color ?? AppColors.primary,
      ),
    ),
  );
}
