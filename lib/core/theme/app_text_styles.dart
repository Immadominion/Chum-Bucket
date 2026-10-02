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
  /// Product roles use logical pixels, independent of viewport width. System
  /// text scaling remains in charge. Match the current bundled brand fonts.
  static const pageTitle = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: Color(0xFF111827),
  );
  /// The question a call is about, leading its card (prototype: 20 / 800,
  /// tracked in).
  static const questionTitle = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.3,
    letterSpacing: -.5,
    color: Color(0xFF111827),
  );

  /// A market's question in a list row (Codex's layout prototype: 16 / 800).
  /// Long venue questions read as a column beside the row's glyph instead of
  /// a block of display type; market detail keeps [questionTitle]. Never
  /// truncated — the full wording is the market's contract.
  static const marketRowQuestion = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 16,
    fontWeight: FontWeight.w800,
    height: 1.35,
    color: Color(0xFF111827),
  );

  static const sheetTitle = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.25,
    color: Color(0xFF111827),
  );

  // --- Bottom sheets -------------------------------------------------------
  //
  // Set to the reference comp
  // (assets/images/open_sourced_design_inspiration/irfan/img2.jpeg), measured
  // in pixels and converted at 390dp. The comp is set in a neo-grotesque, as
  // the original app was in Inter, so sheets use the bundled Inter
  // (assets/fonts/Inter/) rather than the display face used on screens.
  // Weights are matched by measured ink density against the comp: caption
  // Regular, amount Bold, statement and call to action SemiBold, names Medium.

  /// "Bet Amount": white at 60% over the gradient, Regular.
  static TextStyle get sheetCaption => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.2,
    // The comp's face tracks tighter than Inter at text sizes.
    letterSpacing: -.2,
    color: const Color(0x99FFFFFF),
  );

  /// "$20.0": the one number the sheet is about.
  static TextStyle get sheetValue => GoogleFonts.inter(
    // 46, not the comp's 48pt: Inter's capitals stand taller, so 46 matches
    // the comp's measured 35dp digit height.
    fontSize: 46,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -.5,
    color: const Color(0xFFFFFFFF),
  );

  /// The heading of a sheet that has no hero value ("Add a friend").
  static TextStyle get sheetTitleOnBrand => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -.2,
    color: const Color(0xFFFFFFFF),
  );

  /// Supporting copy under a heading or value.
  static TextStyle get sheetSubtitleOnBrand => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: const Color(0xD9FFFFFF),
  );

  /// Names under the avatars ("You", "Zara").
  static TextStyle get sheetPersonName => GoogleFonts.inter(
    fontSize: 16,
    // Medium: SemiBold measured 16% more ink than the comp's names.
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: const Color(0xFF000000),
  );

  /// The statement the sheet is about ("Hit 80% sleep score inside whoop app").
  static TextStyle get sheetStatement => GoogleFonts.inter(
    fontSize: 22,
    // SemiBold: Bold measured 10% more ink than the comp's statement.
    fontWeight: FontWeight.w600,
    // A 29dp line pitch, as measured between the comp's two lines.
    height: 1.318,
    letterSpacing: -.2,
    color: const Color(0xFF000000),
  );

  /// The label on the pink call to action.
  static TextStyle get sheetAction => GoogleFonts.inter(
    fontSize: 16,
    // SemiBold, tracked in: Bold set the comp's label ~12dp too wide and heavy.
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -.4,
    color: const Color(0xFFFFFFFF),
  );

  /// The text-only secondary action under it ("Failed to complete").
  static TextStyle get sheetTextAction => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: const Color(0xFFFF3355),
  );

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
