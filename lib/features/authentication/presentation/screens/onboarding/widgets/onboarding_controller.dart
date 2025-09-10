import 'package:flutter/material.dart';

// A widget that provides page controller access to descendants
class OnboardingPageController extends InheritedWidget {
  final PageController controller;

  const OnboardingPageController({
    super.key,
    required this.controller,
    required Widget child,
  }) : super(child: child);

  // Use findAncestorWidgetOfExactType for performance boost over dependOnInheritedWidgetOfExactType
  // when we don't need rebuilds when the controller changes
  static OnboardingPageController? of(BuildContext context) {
    return context.findAncestorWidgetOfExactType<OnboardingPageController>();
  }

  @override
  bool updateShouldNotify(OnboardingPageController oldWidget) {
    return controller != oldWidget.controller;
  } // Helper method to navigate to next page - optimized for smooth animation

  void nextPage() {
    if (controller.hasClients) {
      final int currentPage = controller.page?.round() ?? 0;
      final int nextPage = currentPage + 1;

      // Use a more optimized animation curve that matches our custom scroll physics
      controller.animateToPage(
        nextPage,
        duration: const Duration(
          milliseconds: 500,
        ), // Longer duration for a more controlled feel
        curve: Curves.easeOutCubic, // Smooth cubic curve for better animation
      );
    }
  }

  // Helper method to navigate to previous page
  void previousPage() {
    if (controller.hasClients) {
      final int currentPage = controller.page?.round() ?? 0;
      if (currentPage > 0) {
        final int prevPage = currentPage - 1;

        controller.animateToPage(
          prevPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  // Navigate directly to a specific page (for indicators)
  void goToPage(int page) {
    if (controller.hasClients && page >= 0 && page < 3) {
      // Assuming 3 pages total
      controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }
}
