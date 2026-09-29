import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget app(CallsProvider provider, String personRef) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (context, _) => MaterialApp(
    home: ChangeNotifierProvider<CallsProvider>.value(
      value: provider,
      child: CallPersonScreen(personRef: personRef, allowArenaProfileLink: false),
    ),
  ),
);

void main() {
  testWidgets('the existing person page follows and unfollows a canonical person', (tester) async {
    phone(tester);
    final provider = CallsProvider(repository: MockCallsRepository())
      ..setViewer(MockCallsRepository.demoViewerUserId);
    await tester.pumpWidget(app(provider, 'user_tobi'));
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsOneWidget);
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    final followingButton = find.descendant(
      of: find.byType(ChallengeButton), matching: find.text('Following'),
    );
    expect(followingButton, findsOneWidget);
    expect(provider.personDetail('user_tobi')?.viewerIsFollowing, isTrue);
    await tester.tap(followingButton);
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsOneWidget);
    expect(provider.personDetail('user_tobi')?.viewerIsFollowing, isFalse);
  });

  testWidgets('the existing person page never offers self-follow', (tester) async {
    phone(tester);
    final provider = CallsProvider(repository: MockCallsRepository())
      ..setViewer(MockCallsRepository.demoViewerUserId);
    await tester.pumpWidget(app(provider, MockCallsRepository.demoViewerUserId));
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsNothing);
  });
}
