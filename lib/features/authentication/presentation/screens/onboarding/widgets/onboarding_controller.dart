import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';

// A widget that provides onboarding navigation methods to descendants
class OnboardingPageController extends InheritedWidget {
  final PageController controller; // Keep for compatibility, though not used
  final BuildContext context;

  const OnboardingPageController({
    super.key,
    required this.controller,
    required this.context,
    required Widget child,
  }) : super(child: child);

  // Use findAncestorWidgetOfExactType for performance boost
  static OnboardingPageController? of(BuildContext context) {
    return context.findAncestorWidgetOfExactType<OnboardingPageController>();
  }

  @override
  bool updateShouldNotify(OnboardingPageController oldWidget) {
    return controller != oldWidget.controller || context != oldWidget.context;
  }

  // Helper method to navigate to next page using provider
  void nextPage() {
    final provider = Provider.of<OnboardingProvider>(context, listen: false);
    final currentPage = provider.currentPage;
    if (currentPage < 2) {
      // Assuming 3 pages total (0, 1, 2)
      provider.setCurrentPage(currentPage + 1);
    }
  }

  // Helper method to navigate to previous page using provider
  void previousPage() {
    final provider = Provider.of<OnboardingProvider>(context, listen: false);
    final currentPage = provider.currentPage;
    if (currentPage > 0) {
      provider.setCurrentPage(currentPage - 1);
    }
  }

  // Navigate directly to a specific page using provider
  void goToPage(int page) {
    if (page >= 0 && page < 3) {
      // Assuming 3 pages total
      final provider = Provider.of<OnboardingProvider>(context, listen: false);
      provider.setCurrentPage(page);
    }
  }
}
