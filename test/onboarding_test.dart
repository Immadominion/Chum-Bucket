import 'package:flutter_test/flutter_test.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Onboarding Provider Tests', () {
    late OnboardingProvider onboardingProvider;

    setUp(() async {
      // Mock SharedPreferences
      SharedPreferences.setMockInitialValues({});
      onboardingProvider = OnboardingProvider();
    });

    test('Initial state should be correct', () {
      expect(onboardingProvider.currentPage, 0);
      expect(onboardingProvider.isLastPage, false);
    });

    test('Setting current page should update state correctly', () {
      onboardingProvider.setCurrentPage(1);
      expect(onboardingProvider.currentPage, 1);
      expect(onboardingProvider.isLastPage, false);

      onboardingProvider.setCurrentPage(2);
      expect(onboardingProvider.currentPage, 2);
      expect(onboardingProvider.isLastPage, true);
    });

    test('Onboarding completion should be tracked', () async {
      // Initially not completed
      expect(await onboardingProvider.isOnboardingCompleted(), false);

      // Mark as completed
      await onboardingProvider.completeOnboarding();
      expect(await onboardingProvider.isOnboardingCompleted(), true);
    });

    test('Clear user data should reset state', () async {
      // Set some state
      onboardingProvider.setCurrentPage(2);
      await onboardingProvider.completeOnboarding();

      // Clear data
      await onboardingProvider.clearUserData();

      // Check state is reset
      expect(onboardingProvider.currentPage, 0);
      expect(onboardingProvider.isLastPage, false);
      expect(await onboardingProvider.isOnboardingCompleted(), false);
    });
  });
}
