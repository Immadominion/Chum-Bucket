import 'package:chumbucket/shared/screens/home/widgets/chumbucket_bottom_navigation.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    builder:
        (context, _) => MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('bottom navigation exposes four stable destinations', (
    tester,
  ) async {
    var selected = 0;

    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder:
              (context, setState) => ChumbucketBottomNavigation(
                selectedIndex: selected,
                onSelected: (index) => setState(() => selected = index),
              ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Calls'), findsOneWidget);
    expect(find.bySemanticsLabel('Friends'), findsOneWidget);
    expect(find.bySemanticsLabel('Profile'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Calls'));
    await tester.pumpAndSettle();
    expect(selected, 1);

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pumpAndSettle();
    expect(selected, 3);
  });

  testWidgets('section tabs report the selected destination', (tester) async {
    var selected = 0;

    await tester.pumpWidget(
      _testApp(
        StatefulBuilder(
          builder:
              (context, setState) => ChumbucketTabs(
                labels: const ['Friends', 'Leaderboard'],
                selectedIndex: selected,
                onSelected: (index) => setState(() => selected = index),
              ),
        ),
      ),
    );

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}
