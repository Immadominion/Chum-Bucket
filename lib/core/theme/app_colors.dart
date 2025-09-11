/// Application color palette following Material 3 design system
library app_colors;

import 'package:flutter/material.dart';

class AppColors {
  /// Primary brand colors - Chum Bucket Red
  static const Color primary = Color(0xFFFF3355); // Your brand red #FF3355
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFFFE5E9);
  static const Color onPrimaryContainer = Color(0xFF3E1114);

  /// Secondary colors
  static const Color secondary = Color(0xFF10B981); // Emerald
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFD1FAE5);
  static const Color onSecondaryContainer = Color(0xFF064E3B);

  /// Tertiary colors (for accents)
  static const Color tertiary = Color(0xFFF59E0B); // Amber
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFFEF3C7);
  static const Color onTertiaryContainer = Color(0xFF78350F);

  /// Error colors
  static const Color error = Color(0xFFEF4444); // Red
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color onErrorContainer = Color(0xFF7F1D1D);

  /// Success colors
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFD1FAE5);
  static const Color onSuccessContainer = Color(0xFF064E3B);

  /// Warning colors
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color onWarning = Color(0xFFFFFFFF);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarningContainer = Color(0xFF78350F);

  /// Surface colors (Light theme)
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF111827);
  static const Color surfaceVariant = Color(0xFFF9FAFB);
  static const Color onSurfaceVariant = Color(0xFF6B7280);

  /// Surface colors (Dark theme)
  static const Color surfaceDark = Color(0xFF111827);
  static const Color onSurfaceDark = Color(0xFFF9FAFB);
  static const Color surfaceVariantDark = Color(0xFF1F2937);
  static const Color onSurfaceVariantDark = Color(0xFF9CA3AF);

  /// Background colors
  static const Color background = Color(0xFFFAFBFC);
  static const Color onBackground = Color(0xFF111827);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color onBackgroundDark = Color(0xFFF1F5F9);

  /// Outline colors
  static const Color outline = Color(0xFFD1D5DB);
  static const Color outlineVariant = Color(0xFFE5E7EB);
  static const Color outlineDark = Color(0xFF374151);
  static const Color outlineVariantDark = Color(0xFF4B5563);

  /// Text colors
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);

  /// Text colors (Dark theme)
  static const Color textPrimaryDark = Color(0xFFF9FAFB);
  static const Color textSecondaryDark = Color(0xFFD1D5DB);
  static const Color textTertiaryDark = Color(0xFF9CA3AF);
  static const Color textDisabledDark = Color(0xFF6B7280);

  /// Glassmorphism colors
  static const Color glass = Color(0x1AFFFFFF);
  static const Color glassDark = Color(0x1A000000);

  /// Card colors
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color cardBackgroundDark = Color(0xFF1F2937);

  /// Divider colors
  static const Color divider = Color(0xFFE5E7EB);
  static const Color dividerDark = Color(0xFF374151);

  /// Shadow colors
  static const Color shadow = Color(0x1A000000);
  static const Color shadowDark = Color(0x40000000);

  /// Status colors for challenges
  static const Color challengePending = Color(0xFFF59E0B); // Amber
  static const Color challengeActive = Color(0xFF3B82F6); // Blue
  static const Color challengeCompleted = Color(0xFF10B981); // Emerald
  static const Color challengeFailed = Color(0xFFEF4444); // Red
  static const Color challengeExpired = Color(0xFF6B7280); // Gray

  /// Special colors with transparency
  static const Color scrim = Color(0x80000000);
  static const Color barrier = Color(0x80000000);

  /// Gradient colors based on primary
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      Color(0xFFFF3355), // Your brand red
      Color(0xFFFF4466), // Slightly lighter variant
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Accessibility colors
  static const Color focusOutline = Color(
    0xFFFF3355,
  ); // Same as primary for consistency
  static const Color selectedBackground = Color(
    0x1AFF3355,
  ); // 10% opacity of primary

  /// Private constructor to prevent instantiation
  AppColors._();
}
