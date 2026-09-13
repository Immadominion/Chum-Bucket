/// Shared builders for the Packet G tests (inbox, category record, rematch).
///
/// Kept in one place so a record test and a rematch test are never arguing
/// about two differently-shaped fixtures.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The slice is laid out against a 390x844 design. The default 800x600 test
/// window makes ScreenUtil scale everything ~2x and overflow, which is a
/// harness artefact rather than a layout bug — so every widget test runs on a
/// phone.
void usePhoneSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Mirrors `main.dart`: ScreenUtilInit -> MaterialApp. Without it
/// flutter_screenutil throws a LateInitializationError production never hits.
Widget screenUtilApp(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (context, _) => MaterialApp(home: child),
);

VenueMarket testMarket({
  required String id,
  String category = 'crypto',
  MarketStatus status = MarketStatus.resolved,
  MarketVenue venue = MarketVenue.jupiter,
  String? question,
}) => VenueMarket(
  id: id,
  venue: venue,
  venueEventId: 'evt_$id',
  venueMarketId: 'jup:$id',
  question: question ?? 'Will $id happen?',
  rulesText: 'The venue resolves $id from its own published evidence.',
  category: category,
  outcomes: const [
    MarketOutcome(side: Side.yes, label: 'Yes'),
    MarketOutcome(side: Side.no, label: 'No'),
  ],
  status: status,
  rawStatus: 'raw-$id',
  opensAt: null,
  closesAt: null,
  resolvesAt: null,
  resolutionSource: 'Test venue',
  lastSyncedAt: 0,
  payloadVersion: 1,
);

const Person testPerson = Person(
  id: 'user_ada',
  handle: 'ada',
  displayName: 'Ada Okafor',
  settledCalls: 31,
  correctCalls: 19,
);

/// One feed entry with a chosen outcome.
///
/// The outcome is produced by pointing `deriveCallOutcome` at a resolution —
/// the only permitted derivation (contract §3) — rather than by writing a
/// `CallOutcome` by hand, so a fixture can never encode an outcome the rules
/// would not produce.
CallFeedEntry testEntry({
  required String id,
  required CallOutcome outcome,
  String category = 'crypto',
  String marketId = 'market_1',
  FundingState funding = FundingState.none,
  Person author = testPerson,
  Side side = Side.yes,
  MarketStatus status = MarketStatus.resolved,
}) {
  final resolution = switch (outcome) {
    CallOutcome.correct => side == Side.yes ? Resolution.yes : Resolution.no,
    CallOutcome.incorrect => side == Side.yes ? Resolution.no : Resolution.yes,
    CallOutcome.voided => Resolution.voided,
    CallOutcome.pending => null,
  };

  final call = Call(
    id: id,
    userId: author.id,
    marketId: marketId,
    side: side,
    confidence: null,
    thesis: null,
    entryProbability: 0.4,
    snapshotId: null,
    visibility: CallVisibility.public,
    createdAt: 1700000000000,
    lockedAt: 1700000000000,
    parentCallId: null,
    fundingState: funding,
  );

  return CallFeedEntry(
    call: call,
    author: author,
    market: testMarket(id: marketId, category: category, status: status),
    result:
        resolution == null
            ? null
            : CallResult(
              callId: id,
              outcome: deriveCallOutcome(side: side, resolution: resolution),
              resolution: resolution,
              resolvedAt: 1700000100000,
              marketResolutionId: 'res_$marketId',
              derivedAt: 1700000100000,
            ),
  );
}

/// `count` entries of one outcome, ids suffixed so they stay distinct.
List<CallFeedEntry> testEntries({
  required int count,
  required CallOutcome outcome,
  String category = 'crypto',
  String marketId = 'market_1',
  FundingState funding = FundingState.none,
  String prefix = 'call',
}) => List.generate(
  count,
  (i) => testEntry(
    id: '${prefix}_${outcome.wire.toLowerCase()}_$i',
    outcome: outcome,
    category: category,
    marketId: marketId,
    funding: funding,
  ),
  growable: false,
);
