/// A1 "Sign in to lock your call" and B1 "Welcome back" (onboarding spec §6,
/// §7). Sign-in comes at the moment it is earned; the draft card proves
/// nothing will be lost; "Not now" keeps signed-out reading fully usable.
library;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/first_call_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/sign_in_panel.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

/// The fist bump: plays once and holds; a still frame under reduced motion
/// (the frame where the fists meet).
class FistBumpHero extends StatelessWidget {
  const FistBumpHero({super.key, this.size = 120});
  final double size;

  static const String asset = 'assets/animations/lottie/lottie.json';

  /// Frame 60 of 121: the fists touch.
  static const double meetProgress = 60 / 121;

  @override
  Widget build(BuildContext context) {
    final reduce = onbReduceMotion(context);
    return ExcludeSemantics(
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: Lottie.asset(
            asset,
            repeat: false,
            animate: !reduce,
            controller: reduce ? AlwaysStoppedAnimation(meetProgress) : null,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, this.welcomeBack = false, this.panel});

  /// B1: the returning variant (brand band, no draft card, no progress).
  final bool welcomeBack;

  /// Test seam for the panel's wallet door.
  final OnboardingSignInPanel? panel;

  String _title(OnboardingFlowController flow) {
    if (welcomeBack) return OnboardingCopy.backTitle;
    return switch (flow.signInReason) {
      SignInReason.call => OnboardingCopy.signInTitleCall,
      SignInReason.follow => OnboardingCopy.signInTitleFollow(
        flow.app.pendingFollowIds.length,
        flow.singlePendingFollowName,
      ),
      SignInReason.none => OnboardingCopy.signInTitleDefault,
    };
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final title = _title(flow);
    final draft = welcomeBack ? null : flow.pendingCall;
    final panelWidget =
        panel ??
        OnboardingSignInPanel(
          compact: true,
          onStarted: (m, lastUsed) => flow.signInStarted(m, lastUsed: lastUsed),
          onFailed: flow.signInFailed,
          onBusyChanged: flow.setBusy,
        );

    return OnboardingScaffold(
      onBack: !welcomeBack && flow.canGoBack ? flow.back : null,
      busy: flow.busy,
      progress: welcomeBack ? null : flow.progress,
      announce: title,
      // Sign-in is the way in: no "Not now" or "Look around first". The ways
      // in sit at the bottom, where a thumb reaches on a tall phone.
      actions: [
        panelWidget,
        const SizedBox(height: 22),
        const OnbConsentLine(),
      ],
      children: [
        const SizedBox(height: 8),
        Center(
          child: OnbReveal(
            scaleFrom: .94,
            child: ChumbucketStateArt(
              welcomeBack
                  ? ChumbucketStateArtwork.success
                  : ChumbucketStateArtwork.record,
              size: 176,
            ),
          ),
        ),
        const SizedBox(height: 20),
        OnbTitle(title),
        if (welcomeBack) ...[
          const SizedBox(height: 8),
          OnbBody(OnboardingCopy.backBody),
        ],
        if (welcomeBack && flow.sessionEnded) ...[
          const SizedBox(height: 16),
          OnbSurface(
            child: OnbIconLine(
              key: const ValueKey('sign-in-session-ended'),
              icon: 'info-circle-outline',
              text: OnboardingCopy.backSessionEnded,
              color: AppColors.textPrimary,
            ),
          ),
        ],
        if (draft != null) ...[
          const SizedBox(height: 16),
          DraftCallCard(draft: draft),
        ],
      ],
    );
  }
}
