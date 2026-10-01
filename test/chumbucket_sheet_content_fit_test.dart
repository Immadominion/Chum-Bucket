import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/widgets/profile_picture_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_friend_sheet_test.dart' show FakeFriends, enter, submit;
import 'chumbucket_sheet_system_test.dart' show mountSheetSystem;

final surface = find.byKey(const ValueKey('chumbucket-sheet-surface'));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final phoneHeight in [667.0, 844.0, 1000.0]) {
    testWidgets('short body and footer hug content on $phoneHeight', (
      tester,
    ) async {
      await mountSheetSystem(
        tester,
        const ChumbucketWavySheet(
          title: 'A short sheet',
          body: SizedBox(key: Key('body'), height: 64),
          footer: SizedBox(key: Key('footer'), height: 72),
        ),
        height: phoneHeight,
      );
      final frame = tester.getRect(surface);
      final header = tester.getRect(find.byType(ChumbucketSheetHeader));
      final body = tester.getRect(find.byKey(const Key('body')));
      final footer = tester.getRect(find.byKey(const Key('footer')));
      expect(frame.height, closeTo(header.height + 64 + 72, .01));
      expect(body.top, closeTo(header.bottom, .01));
      expect(footer.top, closeTo(body.bottom, .01));
      expect(footer.bottom, closeTo(frame.bottom, .01));
      expect(frame.bottom, closeTo(phoneHeight - 14, .01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an explicit ceiling is not a minimum height', (tester) async {
    await mountSheetSystem(
      tester,
      const ChumbucketWavySheet(
        title: 'Small confirmation',
        maxHeight: 600,
        body: SizedBox(height: 48),
      ),
    );
    expect(
      tester.getSize(surface).height,
      tester.getSize(find.byType(ChumbucketSheetHeader)).height + 48,
    );
  });

  testWidgets('dynamic content grows and shrinks without a leftover viewport', (
    tester,
  ) async {
    var rows = 1;
    late StateSetter change;
    await mountSheetSystem(
      tester,
      ChumbucketWavySheet(
        title: 'Changing content',
        body: StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: List.generate(rows, (_) => const SizedBox(height: 48)),
            );
          },
        ),
      ),
    );
    final first = tester.getSize(surface).height;
    change(() => rows = 4);
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, closeTo(first + 144, .01));
    change(() => rows = 1);
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, closeTo(first, .01));
  });

  for (final keyboard in [0.0, 300.0]) {
    testWidgets(
      'long list scrolls to last row; actions stay visible (keyboard $keyboard)',
      (tester) async {
        await mountSheetSystem(
          tester,
          ChumbucketWavySheet(
            title: 'Long sheet',
            body: ListView.builder(
              shrinkWrap: true,
              itemCount: 40,
              itemBuilder:
                  (_, i) => SizedBox(height: 48, child: Text('Item $i')),
            ),
            footer: SizedBox(
              height: 72,
              child: TextButton(onPressed: () {}, child: const Text('Done')),
            ),
          ),
          keyboard: keyboard,
          topInset: 24,
          width: 320,
          scale: 2,
        );
        final frame = tester.getRect(surface);
        expect(frame.top, greaterThanOrEqualTo(36));
        expect(frame.bottom, lessThanOrEqualTo(844 - keyboard - 14));
        expect(find.text('Done').hitTestable(), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Item 39'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Item 39').hitTestable(), findsOneWidget);
        expect(find.text('Done').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'account menu ends 24dp below sign out, without an empty spacer',
    (tester) async {
      await mountSheetSystem(tester, const ProfileSettingsSheet());
      final button = tester.getRect(find.byType(ChallengeButton));
      expect(button.bottom, closeTo(tester.getRect(surface).bottom - 24, .01));
      expect(find.text('Sign Out').hitTestable(), findsOneWidget);
      expect(tester.getSize(surface).height, lessThan(650));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('avatar actions immediately follow its two content-sized rows', (
    tester,
  ) async {
    await mountSheetSystem(tester, const ProfilePictureSelectionModal());
    final sheet = tester.widget<ChumbucketWavySheet>(
      find.byType(ChumbucketWavySheet),
    );
    final body = tester.getRect(find.byWidget(sheet.body));
    final footer = tester.getRect(find.byWidget(sheet.footer!));
    final grid = tester.getRect(find.byType(GridView));
    expect(body.height, closeTo(grid.height + 24, .01));
    expect(footer.top, closeTo(body.bottom, .01));
    expect(footer.bottom, closeTo(tester.getRect(surface).bottom, .01));
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'friend confirmation contracts after successful fake submission',
    (tester) async {
      final service = FakeFriends();
      await mountSheetSystem(
        tester,
        AddFriendSheet(service: service, onFriendAdded: () {}),
      );
      final initialHeight = tester.getSize(surface).height;
      await enter(tester, '@ada');
      await submit(tester, 'Continue with @ada');
      expect(service.handles, ['ada']);
      expect(find.text('Done').hitTestable(), findsOneWidget);
      expect(tester.getSize(surface).height, lessThan(initialHeight));
      final action = tester.getRect(find.widgetWithText(TextButton, 'Done'));
      expect(action.bottom, closeTo(tester.getRect(surface).bottom - 24, .01));
      expect(tester.takeException(), isNull);
    },
  );
}
