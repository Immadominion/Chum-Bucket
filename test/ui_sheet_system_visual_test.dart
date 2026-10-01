// Opt-in captures of real widgets/fonts using fake providers and no writes.
// flutter test --no-pub --update-goldens --dart-define=CAPTURE_SHEET_SYSTEM=true test/ui_sheet_system_visual_test.dart
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_friend_sheet_test.dart' show FakeFriends;
import 'chumbucket_sheet_system_test.dart' show mountSheetSystem, sheetScenes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_SHEET_SYSTEM');
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final (family, paths) in [
      (
        'PPNeueMachina',
        [
          'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
          'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
        ],
      ),
      (
        'Montserrat',
        [
          'assets/fonts/Montserrat/Montserrat-Regular.ttf',
          'assets/fonts/Montserrat/Montserrat-Medium.ttf',
        ],
      ),
      (
        'Montserrat_regular',
        ['assets/fonts/Montserrat/Montserrat-Regular.ttf'],
      ),
      ('Montserrat_medium', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  final scenes = {
    ...sheetScenes(),
    'add-friend':
        () => AddFriendSheet(service: FakeFriends(), onFriendAdded: () {}),
  };
  for (final scene in scenes.entries) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
      testWidgets('capture ${scene.key} $width/$scale', (tester) async {
        await mountSheetSystem(
          tester,
          RepaintBoundary(
            key: const ValueKey('sheet-capture'),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFF4F0EC)),
                ),
                const Positioned(
                  top: 20,
                  left: 24,
                  child: Text('WIDGET TEST · SYNTHETIC DATA'),
                ),
                scene.value(),
              ],
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('sheet-capture')),
          matchesGoldenFile(
            Uri.file(
              '/tmp/chum-sheet-${scene.key}-${width.toInt()}-${scale.toInt()}x.png',
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox());
      }, skip: !enabled);
    }
  }
}
