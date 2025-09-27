import 'package:flutter/material.dart';

/// Utility class for safe modal operations that prevent widget disposal errors
class SafeModalUtils {
  /// Safely close a modal sheet and execute a callback
  /// This prevents "looking up a deactivated widget's ancestor" errors
  static Future<void> safeCloseAndExecute(
    BuildContext context, {
    required bool mounted,
    required VoidCallback onComplete,
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    if (!mounted) return;

    // Close the modal first
    Navigator.of(context).pop();

    // Wait a bit for the modal to close completely
    await Future.delayed(delay);

    // Execute the callback if still mounted
    if (mounted) {
      onComplete();
    }
  }

  /// Safely show a snackbar after checking mounted state
  static void safeShowSnackBar(
    BuildContext context, {
    required bool mounted,
    required Widget content,
    Duration? duration,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Safely navigate to a new screen after checking mounted state
  static Future<void> safeNavigate(
    BuildContext context, {
    required bool mounted,
    required Widget destination,
  }) async {
    if (!mounted) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => destination));
  }

  /// Safely navigate and replace current route
  static Future<void> safeNavigateReplacement(
    BuildContext context, {
    required bool mounted,
    required Widget destination,
  }) async {
    if (!mounted) return;

    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (context) => destination));
  }

  /// Execute a callback only if the widget is still mounted
  static void ifMounted(bool mounted, VoidCallback callback) {
    if (mounted) {
      callback();
    }
  }

  /// Execute an async callback only if the widget is still mounted
  static Future<void> ifMountedAsync(
    bool mounted,
    Future<void> Function() callback,
  ) async {
    if (mounted) {
      await callback();
    }
  }
}
