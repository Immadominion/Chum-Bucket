/// Application dimensions and spacing constants
library app_dimensions;

import 'package:flutter/material.dart';

class AppDimensions {
  /// Spacing constants
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;
  static const double spacingXXLarge = 48.0;

  /// Padding constants
  static const double paddingXSmall = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  /// Margin constants
  static const double marginXSmall = 4.0;
  static const double marginSmall = 8.0;
  static const double marginMedium = 16.0;
  static const double marginLarge = 24.0;
  static const double marginXLarge = 32.0;

  /// Border radius constants
  static const double borderRadiusSmall = 8.0;
  static const double borderRadius = 12.0;
  static const double borderRadiusLarge = 16.0;
  static const double borderRadiusXLarge = 24.0;
  static const double borderRadiusCircular = 50.0;

  /// Icon sizes
  static const double iconSmall = 16.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
  static const double iconXLarge = 48.0;

  /// Avatar sizes
  static const double avatarSmall = 32.0;
  static const double avatarMedium = 48.0;
  static const double avatarLarge = 64.0;
  static const double avatarXLarge = 96.0;

  /// Button dimensions
  static const double buttonHeightSmall = 32.0;
  static const double buttonHeight = 48.0;
  static const double buttonHeightLarge = 56.0;
  static const double buttonMinWidth = 88.0;

  /// Card dimensions
  static const double cardElevation = 2.0;
  static const double cardElevationHigh = 8.0;
  static const double cardMaxWidth = 400.0;

  /// App bar dimensions
  static const double appBarHeight = 56.0;
  static const double appBarElevation = 0.0;

  /// Bottom navigation dimensions
  static const double bottomNavHeight = 80.0;
  static const double bottomNavElevation = 8.0;

  /// Fab dimensions
  static const double fabSize = 56.0;
  static const double fabSizeSmall = 40.0;
  static const double fabSizeLarge = 64.0;

  /// Input field dimensions
  static const double inputHeight = 56.0;
  static const double inputHeightSmall = 40.0;
  static const double inputHeightLarge = 64.0;

  /// Divider dimensions
  static const double dividerThickness = 1.0;
  static const double dividerIndent = 16.0;

  /// Screen breakpoints for responsive design
  static const double mobileMaxWidth = 480.0;
  static const double tabletMaxWidth = 768.0;
  static const double desktopMaxWidth = 1024.0;

  /// Animation duration constants
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 600);

  /// Common edge insets
  static const EdgeInsets paddingAllSmall = EdgeInsets.all(spacingSmall);
  static const EdgeInsets paddingAllMedium = EdgeInsets.all(spacingMedium);
  static const EdgeInsets paddingAllLarge = EdgeInsets.all(spacingLarge);

  static const EdgeInsets paddingHorizontalSmall = EdgeInsets.symmetric(
    horizontal: spacingSmall,
  );
  static const EdgeInsets paddingHorizontalMedium = EdgeInsets.symmetric(
    horizontal: spacingMedium,
  );
  static const EdgeInsets paddingHorizontalLarge = EdgeInsets.symmetric(
    horizontal: spacingLarge,
  );

  static const EdgeInsets paddingVerticalSmall = EdgeInsets.symmetric(
    vertical: spacingSmall,
  );
  static const EdgeInsets paddingVerticalMedium = EdgeInsets.symmetric(
    vertical: spacingMedium,
  );
  static const EdgeInsets paddingVerticalLarge = EdgeInsets.symmetric(
    vertical: spacingLarge,
  );

  /// Common border radius
  static const BorderRadius borderRadiusSmallAll = BorderRadius.all(
    Radius.circular(borderRadiusSmall),
  );
  static const BorderRadius borderRadiusMediumAll = BorderRadius.all(
    Radius.circular(borderRadius),
  );
  static const BorderRadius borderRadiusLargeAll = BorderRadius.all(
    Radius.circular(borderRadiusLarge),
  );

  /// Shadow configurations
  static const List<BoxShadow> shadowSmall = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> shadowLarge = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 8)),
  ];
}
