import 'dart:async';

import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';

/// Runs before every test file in test/. Onboarding's ambient loops (W1's
/// auto-advancing feed, pulse, floating callers, drag-up hint) never settle,
/// so widget tests run without them; one test turns them back on to check
/// they stop on touch and under reduced motion.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  onbAmbientMotion = false;
  await testMain();
}
