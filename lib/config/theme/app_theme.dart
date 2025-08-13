import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFFFF5A76);
  static const background = Color(0xFFF5F5F5);
  static const card = Colors.white;
  static const text = Colors.black;
  static const secondaryText = Color(0xFF7C7C7C);
  static const chipBackground = Color(0xFFE0E0FF);

  // Glassmorphism colors
  static const glassmorphismBackground = Color(0xFF1A1A2E);
  static const glassmorphismCard = Color(0x40FFFFFF);
  static const glassmorphismBorder = Color(0x30FFFFFF);
  static const glassmorphismText = Colors.white;
  static const glassmorphismSecondaryText = Color(0xB3FFFFFF);

  // Gradient colors for background
  static const gradientStart = Color(0xFF6366F1);
  static const gradientMiddle = Color(0xFF8B5CF6);
  static const gradientEnd = Color(0xFFEC4899);

  // Button colors
  static const buttonBackground = Color(0x40FFFFFF);
  static const buttonText = Colors.white;
  static const skipButtonText = Color(0x80FFFFFF);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.card,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.primary,
        surface: AppColors.background,
      ),
      textTheme: GoogleFonts.latoTextTheme().apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.secondaryText,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primary, width: 2.0),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
