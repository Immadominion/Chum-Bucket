/// The host for one onboarding run: builds the per-run controller, shows the
/// current step with a shared-axis transition, owns system Back, and hands
/// back to the app when the run ends (onboarding spec §4.1, §10, §11).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/first_call_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/on_record_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/people_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/topics_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/upgrade_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/username_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';

/// Where a finished run goes when it replaces the splash: Home, by default.
typedef OnboardingExitHandler =
    void Function(BuildContext context, FlowExit exit);

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.run,
    required this.onExit,
    this.resumeAt,
    this.sessionEnded = false,
    this.suggestions,
    this.clock,
    this.stepBuilder,
  });

  final OnboardingRun run;
  final OnboardingStep? resumeAt;
  final bool sessionEnded;
  final OnboardingExitHandler onExit;
  final PeopleSuggestionsRepository? suggestions;
  final DateTime Function()? clock;

  /// Test seam: replace a step's screen.
  final Widget? Function(OnboardingStep step)? stepBuilder;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final OnboardingFlowController _flow;

  @override
  void initState() {
    super.initState();
    _flow = OnboardingFlowController(
      run: widget.run,
      resumeAt: widget.resumeAt,
      sessionEnded: widget.sessionEnded,
      app: context.read<OnboardingController>(),
      calls: context.read<CallsProvider>(),
      session: context.read<ChumbucketSession?>(),
      suggestions: widget.suggestions,
      clock: widget.clock,
      onExit: (exit) {
        if (mounted) widget.onExit(context, exit);
      },
    )..start();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  Widget _screen(OnboardingStep step) {
    final custom = widget.stepBuilder?.call(step);
    if (custom != null) return custom;
    return switch (step) {
      OnboardingStep.welcome => const WelcomeScreen(),
      OnboardingStep.welcomeBack => const SignInScreen(welcomeBack: true),
      OnboardingStep.upgrade => const UpgradeScreen(),
      OnboardingStep.topics => const TopicsScreen(),
      OnboardingStep.people => const PeopleScreen(),
      OnboardingStep.firstCall => const FirstCallScreen(),
      OnboardingStep.signIn => const SignInScreen(),
      OnboardingStep.username => const UsernameScreen(),
      OnboardingStep.friends => const PeopleScreen(friends: true),
      OnboardingStep.resumeCall => const FirstCallScreen(resume: true),
      OnboardingStep.onRecord => const OnRecordScreen(),
    };
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _flow,
    child: Consumer<OnboardingFlowController>(
      builder: (context, flow, _) {
        final step = flow.current;
        final reduce = onbReduceMotion(context);
        return PopScope(
          // At the run's root, Back leaves (the app, or the flow pushed over
          // Home); anywhere else it goes to the previous step.
          canPop: flow.atRoot,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) flow.back();
          },
          child: AnimatedSwitcher(
            duration:
                reduce
                    ? const Duration(milliseconds: 150)
                    : const Duration(milliseconds: 300),
            switchInCurve: Curves.linear,
            switchOutCurve: Curves.linear,
            layoutBuilder:
                (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
            transitionBuilder:
                (child, animation) => sharedAxisTransition(
                  child: child,
                  animation: animation,
                  forward: flow.forward,
                  reduceMotion: reduce,
                ),
            child: KeyedSubtree(
              key: ValueKey('onboarding-step-${step.wire}'),
              child: _screen(step),
            ),
          ),
        );
      },
    ),
  );
}
