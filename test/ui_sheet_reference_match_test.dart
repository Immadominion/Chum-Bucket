// Opt-in: renders the resolve sheet with the reference comp's own content so
// it can be measured against
// assets/images/open_sourced_design_inspiration/irfan/img2.jpeg.
//
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_SHEET_REFERENCE=true \
//   test/ui_sheet_reference_match_test.dart
import 'package:chumbucket/shared/screens/home/widgets/resolve_challenge_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chumbucket_sheet_system_test.dart' show mountSheetSystem;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_SHEET_REFERENCE');

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // google_fonts registers each weight as `<Family>_<variant>`.
    for (final (family, path) in [
      ('Inter_regular', 'assets/fonts/Inter/Inter-Regular.ttf'),
      ('Inter_500', 'assets/fonts/Inter/Inter-Medium.ttf'),
      ('Inter_600', 'assets/fonts/Inter/Inter-SemiBold.ttf'),
      ('Inter_700', 'assets/fonts/Inter/Inter-Bold.ttf'),
      ('Inter_800', 'assets/fonts/Inter/Inter-ExtraBold.ttf'),
      ('Montserrat_regular', 'assets/fonts/Montserrat/Montserrat-Regular.ttf'),
      (
        'PPNeueMachina',
        'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
      ),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  testWidgets('resolve sheet with the comp content', (tester) async {
    await mountSheetSystem(
      tester,
      RepaintBoundary(
        key: const ValueKey('reference-capture'),
        child: Stack(
          children: [
            // The comp's dimmed app behind the sheet measures ~188 grey.
            const Positioned.fill(child: ColoredBox(color: Color(0xFFBCBCBC))),
            ResolveChallengeSheet(
              challenge: const {
                'friendName': 'Zara',
                'description': 'Hit 80% sleep score inside whoop app',
                'amount': 20,
                'status': 'pending',
                'isCurrentUserWitness': true,
              },
              onMarkCompleted: (_, _) {},
            ),
          ],
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(
        find.byKey(const ValueKey('reference-capture')),
      );
      for (final i in [1, 2]) {
        await precacheImage(
          AssetImage('assets/images/ai_gen/profile_images/$i.png'),
          context,
        );
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('reference-capture')),
      matchesGoldenFile(Uri.file('/tmp/chum-ref-match.png')),
    );
  }, skip: !enabled);
}
