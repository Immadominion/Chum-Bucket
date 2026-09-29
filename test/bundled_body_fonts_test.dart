import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'the unchanged body and overline fonts load without any HTTP fetching',
    () async {
      final previous = GoogleFonts.config.allowRuntimeFetching;
      GoogleFonts.config.allowRuntimeFetching = false;
      addTearDown(() => GoogleFonts.config.allowRuntimeFetching = previous);
      final colors = ColorScheme.fromSeed(seedColor: const Color(0xFFFF3355));
      final theme = AppTextStyles.textThemeWithColorScheme(colors);
      final overline = AppTextStyles.overline(colors);
      await GoogleFonts.pendingFonts();
      expect(theme.bodyMedium?.fontFamily, 'Montserrat_regular');
      expect(overline.fontFamily, 'Montserrat_500');
      expect(theme.headlineLarge?.fontFamily, 'PPNeueMachina');
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(
        manifest.listAssets(),
        containsAll([
          'assets/fonts/Montserrat/Montserrat-Regular.ttf',
          'assets/fonts/Montserrat/Montserrat-Medium.ttf',
          'assets/fonts/Montserrat/OFL.txt',
        ]),
      );
    },
  );
}
