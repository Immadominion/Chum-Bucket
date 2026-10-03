// Opt-in captures of the real Add a friend sheet, driven through each stage
// with an in-memory service: synthetic people, no writes, no network.
// flutter test --no-pub --update-goldens --dart-define=CAPTURE_SHEET_SYSTEM=true \
//   --dart-define=CAPTURE_DIR=/tmp test/ui_add_friend_visual_test.dart
import 'package:chumbucket/features/people/data/person_finder.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_friend_sheet_test.dart'
    show FakeFriends, enter, found, matchOf, submit;
import 'chumbucket_sheet_system_test.dart' show mountSheetSystem;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_SHEET_SYSTEM');
  const dir = String.fromEnvironment('CAPTURE_DIR', defaultValue: '/tmp');
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
      ('Inter_400', ['assets/fonts/Inter/Inter-Regular.ttf']),
      ('Inter_500', ['assets/fonts/Inter/Inter-Medium.ttf']),
      ('Inter_600', ['assets/fonts/Inter/Inter-SemiBold.ttf']),
      ('Inter_700', ['assets/fonts/Inter/Inter-Bold.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  const art = 'assets/images/ai_gen/profile_images/3.png';
  final scenes = <String, (FakeFriends, String?, String?)>{
    'input': (FakeFriends(), null, null),
    'card': (
      FakeFriends()..answer = (_) async => found([matchOf(avatarArt: art)]),
      '@irfan',
      null,
    ),
    'following': (
      FakeFriends()
        ..answer =
            (_) async => found([matchOf(avatarArt: art, following: true)]),
      '@irfan',
      null,
    ),
    'two': (
      FakeFriends()
        ..answer =
            (_) async => found([
              matchOf(avatarArt: art),
              matchOf(
                id: 'u-2',
                name: 'Another Irfan',
                handle: 'irfan',
                xHandle: null,
                matchedBy: PersonMatchedBy.username,
              ),
            ]),
      '@irfan',
      null,
    ),
    'not-on-chumbucket': (
      FakeFriends()
        ..answer =
            (_) async => const PersonLookup(
              kind: PersonLookupKind.handle,
              matches: [],
              notOnChumbucket: NotOnChumbucket(xHandle: 'vitalik'),
            ),
      '@vitalik',
      null,
    ),
    'added': (
      FakeFriends()..answer = (_) async => found([matchOf(avatarArt: art)]),
      '@irfan',
      'Add friend',
    ),
  };

  for (final scene in scenes.entries) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
      testWidgets('capture add-friend ${scene.key} $width/$scale', (
        tester,
      ) async {
        final (service, query, action) = scene.value;
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
                AddFriendSheet(service: service, onFriendAdded: () {}),
              ],
            ),
          ),
          width: width,
          scale: scale,
        );
        if (query != null) {
          await enter(tester, query);
          await submit(tester);
          if (action != null) await submit(tester, action);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 2000),
          );
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final context = tester.element(
            find.byKey(const ValueKey('sheet-capture')),
          );
          // The exact provider FriendPicture draws: decoded at its size.
          await precacheImage(
            ResizeImage(
              const AssetImage(art),
              width: 64,
              policy: ResizeImagePolicy.fit,
            ),
            context,
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('sheet-capture')),
          matchesGoldenFile(
            Uri.file(
              '$dir/chum-add-friend-${scene.key}-${width.toInt()}-${scale.toInt()}x.png',
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox());
      }, skip: !enabled);
    }
  }
}
