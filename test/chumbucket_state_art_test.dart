import 'dart:io';
import 'dart:ui' as ui;

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 844,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, __) => MaterialApp(
            theme: AppTheme.lightTheme,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
            home: Scaffold(body: child),
          ),
    ),
  );
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, tester.element(find.byType(Scaffold)));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      ('Montserrat', ['assets/fonts/Montserrat/Montserrat-Regular.ttf']),
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

  for (final artwork in ChumbucketStateArtwork.values) {
    test(
      '${artwork.name} is bundled, square and genuinely transparent',
      () async {
        final source = await rootBundle.load(artwork.assetPath);
        expect(source.lengthInBytes, lessThan(2 * 1024 * 1024));
        final codec = await ui.instantiateImageCodec(
          source.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        final image = frame.image;
        expect(image.width, image.height);
        expect(image.width, greaterThanOrEqualTo(512));
        final pixels =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int alpha(int x, int y) =>
            pixels.getUint8((y * image.width + x) * 4 + 3);
        for (final (x, y) in [
          (0, 0),
          (image.width - 1, 0),
          (0, image.height - 1),
          (image.width - 1, image.height - 1),
        ]) {
          expect(alpha(x, y), 0, reason: 'No opaque background at the corners');
        }
        var transparent = 0;
        var opaque = 0;
        for (var offset = 3; offset < pixels.lengthInBytes; offset += 4) {
          final a = pixels.getUint8(offset);
          if (a == 0) transparent++;
          // Generated antialiased PNGs can encode solid paint at 254/255.
          if (a >= 250) opaque++;
        }
        final area = image.width * image.height;
        expect(transparent / area, greaterThan(.2));
        expect(opaque / area, greaterThan(.15));
        image.dispose();
        codec.dispose();
      },
    );
  }

  testWidgets('art is decorative and has bounded intrinsic size', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester, const CallsEmptyView());
    expect(
      tester.getSize(find.byType(ChumbucketStateArt)),
      const Size(144, 144),
    );
    expect(find.text('No calls yet'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.excludeFromSemantics, isTrue);
    expect(image.semanticLabel, isNull);
    final root =
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!;
    void checkDecorative(SemanticsNode node) {
      expect(node.flagsCollection.isImage, isFalse);
      node.visitChildren((child) {
        checkDecorative(child);
        return true;
      });
    }

    checkDecorative(root);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  final states =
      <String, (Widget Function(VoidCallback), ChumbucketStateArtwork, String)>{
        'empty': (
          (action) =>
              CallsEmptyView(actionLabel: 'Explore markets', onAction: action),
          ChumbucketStateArtwork.calls,
          'Explore markets',
        ),
        'error': (
          (action) =>
              CallsErrorView(message: 'Please try again.', onRetry: action),
          ChumbucketStateArtwork.error,
          'Try again',
        ),
        'offline': (
          (action) => CallsOfflineView(onRetry: action),
          ChumbucketStateArtwork.offline,
          'Try again',
        ),
        'signed out': (
          (action) => CallsSignedOutView(onSignIn: action),
          ChumbucketStateArtwork.access,
          'Sign in',
        ),
      };
  for (final entry in states.entries) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
      testWidgets('${entry.key} keeps its action at $width / ${scale}x', (
        tester,
      ) async {
        var acted = 0;
        final (build, artwork, label) = entry.value;
        await _mount(
          tester,
          build(() => acted++),
          width: width,
          scale: scale,
          height: 568,
        );
        expect(
          tester
              .widget<ChumbucketStateArt>(find.byType(ChumbucketStateArt))
              .artwork,
          artwork,
        );
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        expect(acted, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'loading and cached notices do not become illustrated empty states',
    (tester) async {
      await _mount(tester, const CallsLoadingView(rows: 2));
      expect(find.byType(ChumbucketStateArt), findsNothing);
      await _mount(tester, CallsNotice.offline());
      expect(find.byType(ChumbucketStateArt), findsNothing);
      expect(
        find.text('Offline — showing what we already had.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty friends retain the existing add action', (tester) async {
    var added = 0;
    await _mount(
      tester,
      SingleChildScrollView(
        child: FriendsGrid(
          friends: const [],
          onFriendSelected: (_) {},
          buildViewMoreItem: (_, __) => const SizedBox(),
          onAddFriend: () => added++,
        ),
      ),
      width: 320,
      scale: 2,
    );
    expect(
      tester
          .widget<ChumbucketStateArt>(find.byType(ChumbucketStateArt))
          .artwork,
      ChumbucketStateArtwork.people,
    );
    await tester.ensureVisible(find.text('Add a friend'));
    await tester.tap(find.text('Add a friend'));
    expect(added, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty challenge list is not a completion celebration', (
    tester,
  ) async {
    await _mount(tester, buildNoChallengesView(withText: true));
    expect(
      tester
          .widget<ChumbucketStateArt>(find.byType(ChumbucketStateArt))
          .artwork,
      ChumbucketStateArtwork.challenges,
    );
    expect(find.text('No escrow challenges'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short empty friends sheet stays content-sized', (tester) async {
    await _mount(
      tester,
      ViewMoreFriendsSheet(friends: const [], onFriendSelected: (_) {}),
    );
    expect(tester.getSize(find.byType(ChumbucketStateArt)), const Size(96, 96));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('chumbucket-sheet-surface')))
          .height,
      lessThan(420),
    );
    expect(find.text('Your friends will appear here.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('state family contact sheet', (tester) async {
    final families = <String, List<ChumbucketStateArtwork>>{};
    for (final art in ChumbucketStateArtwork.values) {
      (families[art.assetPath] ??= []).add(art);
    }
    await _mount(
      tester,
      RepaintBoundary(
        key: const ValueKey('state-art-gallery'),
        child: ColoredBox(
          color: const Color(0xFFF4F4F4),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CHUMBUCKET / STATE ILLUSTRATIONS',
                  style: TextStyle(fontFamily: 'PPNeueMachina', fontSize: 24),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Plankton & Karen · different moments, one family · transparent backgrounds',
                  style: TextStyle(fontFamily: 'Montserrat', fontSize: 13),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.12,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final family in families.values)
                        ColoredBox(
                          color: Colors.white,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ChumbucketStateArt(family.first),
                              const SizedBox(height: 4),
                              Text(
                                family.map((art) => art.name).join(' / '),
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      width: 1040,
      height: 590,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('state-art-gallery')),
      matchesGoldenFile('goldens/state_art_family.png'),
    );
  });

  test('all state art stays local and no secret asset is added', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    expect(manifest, contains('    - assets/images/states/'));
    expect(
      RegExp(r'^\s+-\s+\.?/?\.env\s*$', multiLine: true).hasMatch(manifest),
      isFalse,
    );
    expect(
      ChumbucketStateArtwork.values.map((a) => a.assetPath).toSet().length,
      8,
    );
    expect(ChumbucketStateArtwork.values.length, 11);
    final bundledPngs =
        Directory('assets/images/states')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.png'))
            .map((file) => file.path)
            .toSet();
    expect(
      bundledPngs,
      ChumbucketStateArtwork.values.map((art) => art.assetPath).toSet(),
      reason: 'Do not silently bundle the superseded house illustrations.',
    );
  });
}
