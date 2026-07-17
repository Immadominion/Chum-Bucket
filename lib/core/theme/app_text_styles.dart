/// Application text styles following Material 3 design.
///
/// Mixed typeface: PP Neue Machina — a bold, geometric display face with only
/// three weights (Light/Regular/Ultrabold, no mid-range) — carries the app's
/// "voice" (display/headline/title/label/button: short, punchy text).
/// Montserrat stays for body copy, where long-form reading needs a face with
/// a fuller weight range and softer letterforms.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A PP Neue Machina text style at the given weight (bundled OTF, registered
/// as the `PPNeueMachina` family in pubspec.yaml — not a Google Font).
TextStyle _ppNeueMachina({
  required double fontSize,
  required FontWeight fontWeight,
  double letterSpacing = 0,
  Color? color,
}) => TextStyle(
  fontFamily: 'PPNeueMachina',
  fontSize: fontSize,
  fontWeight: fontWeight,
  letterSpacing: letterSpacing,
  color: color,
);

class AppTextStyles {
  // Backwards compatible static getter using a default dark theme
  static TextTheme get textTheme => textThemeWithColorScheme(
    const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFFFF3355),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFFFE5E9),
      onPrimaryContainer: Color(0xFF3E1114),
      secondary: Color(0xFF10B981),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD1FAE5),
      onSecondaryContainer: Color(0xFF064E3B),
      tertiary: Color(0xFFF59E0B),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFEF3C7),
      onTertiaryContainer: Color(0xFF78350F),
      error: Color(0xFFEF4444),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF111827),
      surfaceContainerHighest: Color(0xFFF9FAFB),
      onSurfaceVariant: Color(0xFF6B7280),
      outline: Color(0xFFD1D5DB),
      outlineVariant: Color(0xFFE5E7EB),
      shadow: Color(0x1A000000),
      scrim: Color(0x80000000),
      inverseSurface: Color(0xFF111827),
      onInverseSurface: Color(0xFFF9FAFB),
      inversePrimary: Color(0xFFFF3355),
      surfaceTint: Color(0xFFFF3355),
    ),
  );

  // New function-based approach
  static TextTheme textThemeWithColorScheme(ColorScheme colorScheme) =>
      TextTheme(
        // Display styles — PP Neue Machina Ultrabold: the app's hero voice.
        displayLarge: _ppNeueMachina(
          fontSize: 57,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.25,
          color: colorScheme.onSurface,
        ),
        displayMedium: _ppNeueMachina(
          fontSize: 45,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        displaySmall: _ppNeueMachina(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),

        // Headline styles — PP Neue Machina Ultrabold.
        headlineLarge: _ppNeueMachina(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        headlineMedium: _ppNeueMachina(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        headlineSmall: _ppNeueMachina(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),

        // Title styles — PP Neue Machina Regular (structural, not shouting).
        titleLarge: _ppNeueMachina(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        titleMedium: _ppNeueMachina(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: colorScheme.onSurface,
        ),
        titleSmall: _ppNeueMachina(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.1,
          color: colorScheme.onSurface,
        ),

        // Label styles — PP Neue Machina (nav labels, chips, tags).
        labelLarge: _ppNeueMachina(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.1,
          color: colorScheme.onSurface,
        ),
        labelMedium: _ppNeueMachina(
          fontSize: 12,
          fontWeight: FontWeight.w300,
          letterSpacing: 0.5,
          color: colorScheme.onSurface,
        ),
        labelSmall: _ppNeueMachina(
          fontSize: 11,
          fontWeight: FontWeight.w300,
          letterSpacing: 0.5,
          color: colorScheme.onSurface,
        ),

        // Body styles
        bodyLarge: GoogleFonts.montserrat(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: colorScheme.onSurface,
        ),
        bodyMedium: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: colorScheme.onSurface,
        ),
        bodySmall: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
          color: colorScheme.onSurface,
        ),
      );

  // Additional custom styles that accept colorScheme
  static TextStyle button(ColorScheme colorScheme) => _ppNeueMachina(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
    color: colorScheme.onPrimary,
  );

  static TextStyle caption(ColorScheme colorScheme) => GoogleFonts.montserrat(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    color: colorScheme.onSurfaceVariant,
  );

  static TextStyle overline(ColorScheme colorScheme) => GoogleFonts.montserrat(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
    color: colorScheme.onSurfaceVariant,
  );
}
