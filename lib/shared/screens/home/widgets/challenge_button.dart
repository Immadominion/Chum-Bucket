import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';

/// The app's primary call to action. Renders the reference comp's button
/// ([ChumbucketPrimaryButton]); the API is unchanged for existing callers.
class ChallengeButton extends StatelessWidget {
  /// The tap handler. (The name is historical: this button no longer starts
  /// anything to do with challenges; it is the shared primary action.)
  final VoidCallback createNewChallenge;

  /// Required: the old default label named the retired SOL escrow flow
  /// (Challenge a new friend) and must not come back by omission.
  final String label;
  final bool enabled; // allow disabling
  final bool isLoading; // optional loading state

  /// False renders the soft variant: same geometry on the pale brand
  /// container, for a secondary action that should not compete with a primary.
  final bool hasGradient;

  /// Kept for source compatibility. The comp's button has no shadow at all,
  /// so there is nothing left for this to switch off.
  final bool blurRadius;

  const ChallengeButton({
    super.key,
    required this.createNewChallenge,
    required this.label,
    this.enabled = true,
    this.isLoading = false,
    this.hasGradient = true,
    this.blurRadius = true,
  });

  // #FF3355 on the pale container is ~3:1; this deeper brand red is 4.8:1.
  static const _softLabel = Color(0xFFC81E3C);

  @override
  Widget build(BuildContext context) {
    final text = label;
    final onPressed = enabled && !isLoading ? createNewChallenge : null;
    if (hasGradient) {
      return ChumbucketPrimaryButton(
        label: text,
        busy: isLoading,
        onPressed: enabled ? createNewChallenge : null,
      );
    }
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: SizedBox(
        width: double.infinity,
        height: ChumbucketPrimaryButton.height,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: AppColors.primaryContainer,
            foregroundColor: _softLabel,
            overlayColor: _softLabel.withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                ChumbucketPrimaryButton.radius,
              ),
            ),
          ),
          child:
              isLoading
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _softLabel,
                    ),
                  )
                  : Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.sheetAction.copyWith(
                      color: _softLabel,
                    ),
                  ),
        ),
      ),
    );
  }
}
