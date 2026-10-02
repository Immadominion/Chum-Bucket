// "More" on a call opens report / mute / block — on other people's calls
// only — and never reaches the network in a test (a fake repository).
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'packet_g_fixtures.dart' show usePhoneSurface;
import 'trust_fakes.dart';

void main() {
  testWidgets('More on someone else\'s call reports, mutes or blocks them', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final calls = CallsProvider(repository: MockCallsRepository())
      ..setViewer(MockCallsRepository.demoViewerUserId);
    addTearDown(calls.dispose);
    final trust = FakeTrust();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CallsProvider>.value(value: calls),
          Provider<TrustRepository?>.value(value: trust),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => const MaterialApp(
                home: CallDetailScreen(callId: 'call_ada_btc'),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('More'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Report this call'), findsOneWidget);
    expect(find.textContaining('Mute @'), findsOneWidget);
    expect(find.textContaining('Block @'), findsOneWidget);
  });
}
