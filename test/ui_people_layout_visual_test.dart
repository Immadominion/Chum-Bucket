import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_stats_card.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'ui_people_layout_profile_test.dart'
    show mountPeople, PeopleRepository, peopleEntry;
import 'ui_people_layout_continuity_test.dart'
    show ExistingProfile, ConnectedAuth, ConnectedWallet;

void main() {
  testWidgets('joined identity and neutral record visual review at 390dp', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Optional local screenshot uses bundled typefaces and synthetic test data.
    // flutter test --no-pub --dart-define=CHUM_PEOPLE_CAPTURE=true test/ui_people_layout_visual_test.dart
    const capture = bool.fromEnvironment('CHUM_PEOPLE_CAPTURE');
    if (capture) {
      await (FontLoader('PPNeueMachina')
            ..addFont(
              rootBundle.load(
                'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
              ),
            )
            ..addFont(
              rootBundle.load(
                'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
              ),
            ))
          .load();
      await (FontLoader('Montserrat_regular')..addFont(
        rootBundle.load('assets/fonts/Montserrat/Montserrat-Regular.ttf'),
      )).load();
    }
    final profile = ExistingProfile();
    final auth = ConnectedAuth();
    final wallet = ConnectedWallet();
    final calls = CallsProvider(
      repository: PeopleRepository([
        peopleEntry('correct', CallOutcome.correct, demo: true),
        peopleEntry('incorrect', CallOutcome.incorrect, demo: true),
        peopleEntry('void', CallOutcome.voided, demo: true),
        peopleEntry('pending', CallOutcome.pending, demo: true),
      ]),
    )..setViewer('user_ada');
    addTearDown(profile.dispose);
    addTearDown(auth.dispose);
    addTearDown(wallet.dispose);
    addTearDown(calls.dispose);
    final boundaryKey = GlobalKey();
    await mountPeople(
      tester,
      RepaintBoundary(
        key: boundaryKey,
        child: Theme(
          data: ThemeData(textTheme: AppTextStyles.textTheme),
          child: const ProfileScreen(embedded: true),
        ),
      ),
      width: 390,
      scale: 1,
      wrap:
          (child) => MultiProvider(
            providers: [
              ChangeNotifierProvider<ProfileProvider>.value(value: profile),
              ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
              ChangeNotifierProvider<MwaWalletProvider>.value(value: wallet),
              ChangeNotifierProvider<CallsProvider>.value(value: calls),
            ],
            child: child,
          ),
    );
    final identity = tester.getRect(find.byType(ProfileHeader));
    final record = tester.getRect(find.byType(ProfileStatsCard));
    expect(record.top, identity.bottom); // Joined, without a second card gap.
    expect(record.left, identity.left);
    expect(record.width, identity.width);
    expect(find.text('My wallet'), findsOneWidget);
    expect(find.text('2.50 SOL'), findsNothing);
    expect(tester.takeException(), isNull);
    if (capture) {
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/ai_gen/profile_images/1.png'),
          tester.element(find.byType(ProfileHeader)),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/private/tmp/chum-profile-layout.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
