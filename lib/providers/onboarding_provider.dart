import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingProvider extends ChangeNotifier {
  int _currentPage = 0;
  bool _isLastPage = false;
  final String _onboardingCompletedKey = 'onboardingCompleted';

  int get currentPage => _currentPage;
  bool get isLastPage => _isLastPage;

  void setCurrentPage(int page) {
    _currentPage = page;
    _isLastPage = page == 2; // We have 3 onboarding screens (0, 1, 2)
    notifyListeners();
  }

  Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, true);
    notifyListeners();
  }
}
