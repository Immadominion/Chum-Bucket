/// Application text styles following Material 3 design

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        // Display styles
        displayLarge: GoogleFonts.montserrat(
          fontSize: 57,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.25,
          color: colorScheme.onSurface,
        ),
        displayMedium: GoogleFonts.montserrat(
          fontSize: 45,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        displaySmall: GoogleFonts.montserrat(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),

        // Headline styles
        headlineLarge: GoogleFonts.montserrat(
          fontSize: 32,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        headlineMedium: GoogleFonts.montserrat(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        headlineSmall: GoogleFonts.montserrat(
          fontSize: 24,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),

        // Title styles
        titleLarge: GoogleFonts.montserrat(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: colorScheme.onSurface,
        ),
        titleMedium: GoogleFonts.montserrat(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
          color: colorScheme.onSurface,
        ),
        titleSmall: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: colorScheme.onSurface,
        ),

        // Label styles
        labelLarge: GoogleFonts.montserrat(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: colorScheme.onSurface,
        ),
        labelMedium: GoogleFonts.montserrat(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: colorScheme.onSurface,
        ),
        labelSmall: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w500,
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
  static TextStyle button(ColorScheme colorScheme) => GoogleFonts.montserrat(
    fontSize: 14,
    fontWeight: FontWeight.w500,
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
