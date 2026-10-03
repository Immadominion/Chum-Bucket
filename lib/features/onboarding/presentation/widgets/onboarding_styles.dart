/// Onboarding's type roles, on the app's two faces: PP Neue Machina for
/// display (titles, names, leads, questions) and Montserrat for body. Sizes
/// follow the design audit: 24–28 titles, 14–16 body, 12 minimum metadata.
/// Nothing here fixes a height; every role scales with the system text size.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';

abstract final class OnbText {
  /// Step titles: 28 / 800, tracked in like the prototype's page titles.
  static const TextStyle title = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.18,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
  );

  /// Section headings inside a step ("Live calls", "Answer a call").
  static const TextStyle section = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 17,
    fontWeight: FontWeight.w800,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  /// A person's name, a "how it works" lead.
  static const TextStyle name = TextStyle(
    fontFamily: 'PPNeueMachina',
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  /// A market question in a row or card. Never truncated.
  static const TextStyle question = AppTextStyles.marketRowQuestion;

  /// Body under a title: Montserrat 16 / 1.45, muted.
  static TextStyle get body => GoogleFonts.montserrat(
    fontSize: 16,
    height: 1.45,
    color: AppColors.textMuted,
  );

  /// Body in ink (rows, notes).
  static TextStyle get bodyInk => GoogleFonts.montserrat(
    fontSize: 15,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  /// Secondary lines: Montserrat 13, muted.
  static TextStyle get small => GoogleFonts.montserrat(
    fontSize: 13,
    height: 1.45,
    color: AppColors.textMuted,
  );

  /// The floor: Montserrat 12, muted.
  static TextStyle get meta => GoogleFonts.montserrat(
    fontSize: 12,
    height: 1.45,
    color: AppColors.textMuted,
  );

  /// Labels on chips and small buttons: Montserrat Medium 15.
  static TextStyle get chip => GoogleFonts.montserrat(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: AppColors.textPrimary,
  );
}

/// Spacing rhythm: 16 gutters, 8-step increments.
abstract final class OnbSpace {
  static const double gutter = 16;
  static const double maxContentWidth = 480;
  static const double radius = 20;
}
