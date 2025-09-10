import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';

/// Route names for login-related screens
class LoginRoutes {
  static const String loginScreen = '/login';

  /// Register all login-related routes
  static Map<String, WidgetBuilder> getRoutes() {
    return {loginScreen: (context) => const LoginScreen()};
  }
}
