/// Rematch: who may be rematched, what a rematch creates, and the things it
/// must never carry.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/rematch/data/rematch_offer.dart';
import 'package:chumbucket/features/rematch/presentation/rematch_sheet.dart';
import 'package:chumbucket/features/rematch/presentation/widgets/rematch_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'packet_g_fixtures.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

RematchOffer offerFrom(
  CallFeedEntry entry, {
  String? viewerUserId = viewer,
}) => RematchOffer.fromEntry(entry, viewerUserId: viewerUserId);

Widget sheetHarness(CallsProvider calls, RematchOffer offer) =>
    ChangeNotifierProvider<CallsProvider>.value(
      value: calls,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (context, _) => MaterialApp(home: Scaffold(body: RematchSheet(offer: offer))),
      ),
    );

void main() {
  group('who can be rematched', () {
    test('a settled call by someone else is available', () {
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.correct),
      );
      expect(offer.availability, RematchAvailability.available);
      expect(offer.isAvailable, isTrue);
    });

    test('a miss is just as rematchable as a hit', () {
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.incorrect),
      );
      expect(offer.availability, RematchAvailability.available);
    });

    test('a pending call has nothing to rematch yet', () {
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.pending),
      );
      expect(offer.availability, RematchAvailability.notSettled);
      expect(offer.isAvailable, isFalse);
    });

    test('you cannot rematch yourself', () {
      final entry = testEntry(
        id: 'c1',
        outcome: CallOutcome.correct,
        author: const Person(id: viewer, handle: 'you', displayName: 'You'),
      );
      expect(
        offerFrom(entry).availability,
        RematchAvailability.ownCall,
      );
      expect(offerFrom(entry).isAvailable, isFalse);
    });

    test('a void result is still rematchable, and is labelled as void', () {
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.voided),
      );
      expect(offer.availability, RematchAvailability.voidResult);
      expect(offer.isAvailable, isTrue);
      expect(offer.resultLine, contains('neither a win nor a loss'));
    });

    test('the receipt path and the entry path agree', () {
      for (final outcome in CallOutcome.values) {
        final entry = testEntry(id: 'c_${outcome.wire}', outcome: outcome);
        final fromEntry = RematchOffer.fromEntry(entry, viewerUserId: viewer);
        final fromReceipt = RematchOffer.fromReceipt(
          CallReceipt.fromEntry(entry, shareUrl: 'https://example.test/c/x'),
          opponentUserId: entry.author.id,
          marketAcceptsNewCalls: entry.market.status.acceptsNewCalls,
          viewerUserId: viewer,
        );
        expect(
          fromReceipt.availability,
          fromEntry.availability,
          reason: outcome.wire,
        );
        expect(fromReceipt.sourceCallId, fromEntry.sourceCallId);
        expect(fromReceipt.opponentUserId, fromEntry.opponentUserId);
      }
    });
  });

  group('what a rematch is, structurally', () {
    test('there is no escrow and no stake, by construction', () {
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.correct),
      );
      expect(offer.hasEscrow, isFalse);
      expect(offer.hasStake, isFalse);
    });

    test('it can only ever become a challenge', () {
      final input = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.correct),
      ).toInput(note: 'Go again.');

      expect(input.kind, CallResponseKind.challenge);
      expect(input.kind.createsOwnCall, isFalse);
      expect(input.targetCallId, 'c1');
      expect(input.thesis, 'Go again.');
      // A challenge creates no call for the challenger, so there is nothing to
      // be confident about.
      expect(input.confidence, isNull);
    });

    test('an empty note stays null rather than becoming an empty thesis', () {
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.correct),
      );
      expect(offer.toInput().thesis, isNull);
      expect(offer.toInput(note: '   ').thesis, isNull);
    });

    test('the wire payload carries no amount-shaped field at all', () {
      final json = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.correct),
      ).toInput(note: 'Go again.').toJson();

      expect(json.keys.toSet(), {
        'targetCallId',
        'kind',
        'confidence',
        'thesis',
        'visibility',
      });
      for (final key in json.keys) {
        expect(
          key.toLowerCase(),
          isNot(anyOf(contains('amount'), contains('stake'), contains('escrow'))),
        );
      }
    });
  });

  group('sending one', () {
    test('creates a challenge, mints no call, and escrows nothing', () async {
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);

      final detail = await repo.fetchCall(
        callId: 'call_zed_fed',
        viewerUserId: viewer,
      );
      final offer = RematchOffer.fromEntry(
        detail.entry,
        viewerUserId: viewer,
      );
      expect(offer.isAvailable, isTrue);

      final callsBefore = repo.debugCalls.length;
      final result = await provider.respondToCall(offer.toInput(note: 'Again.'));

      expect(result.response.kind, CallResponseKind.challenge);
      expect(result.response.resultingCallId, isNull);
      expect(result.resultingCall, isNull);
      expect(result.invitation, isNotNull);
      expect(result.invitation!.hasEscrow, isFalse);
      expect(result.invitation!.toUserId, 'user_zed');
      expect(result.invitation!.fromUserId, viewer);
      // No call was made in anybody's name.
      expect(repo.debugCalls.length, callsBefore);
    });

    test('the invitation lands in the opponent inbox, not the sender one',
        () async {
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      final detail = await repo.fetchCall(
        callId: 'call_zed_fed',
        viewerUserId: viewer,
      );

      await provider.respondToCall(
        RematchOffer.fromEntry(detail.entry, viewerUserId: viewer).toInput(),
      );

      final theirs = await repo.fetchInvitations(viewerUserId: 'user_zed');
      expect(theirs.map((i) => i.fromUserId), contains(viewer));
      expect(theirs.every((i) => i.hasEscrow == false), isTrue);
    });

    test('a signed-out person cannot send one', () async {
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo);
      final detail = await repo.fetchCall(callId: 'call_zed_fed');

      expect(
        () => provider.respondToCall(
          RematchOffer.fromEntry(detail.entry, viewerUserId: null).toInput(),
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
    });
  });

  group('the button', () {
    testWidgets('renders nothing when a rematch is not on offer', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.pending),
      );
      await tester.pumpWidget(
        screenUtilApp(
          Scaffold(
            body: RematchButton(offer: offer, onPressed: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Rematch'), findsNothing);
    });

    testWidgets('names the person it will reach', (tester) async {
      usePhoneSurface(tester);
      final offer = offerFrom(
        testEntry(id: 'c1', outcome: CallOutcome.correct),
      );
      await tester.pumpWidget(
        screenUtilApp(
          Scaffold(body: RematchButton(offer: offer, onPressed: () {})),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rematch @ada'), findsOneWidget);
    });
  });

  group('the sheet', () {
    testWidgets('says in words that nothing is at stake, and offers no amount',
        (tester) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      final detail = await repo.fetchCall(
        callId: 'call_zed_fed',
        viewerUserId: viewer,
      );

      await tester.pumpWidget(
        sheetHarness(
          provider,
          RematchOffer.fromEntry(detail.entry, viewerUserId: viewer),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nothing is escrowed, nothing is staked'),
        findsOneWidget,
      );
      expect(find.textContaining('no amount is set'), findsOneWidget);

      // The content-sized list also builds the note's editable Scrollable.
      // Target the outer form instead of assuming a single scrollable exists.
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField).hitTestable(), findsOneWidget);

      // Exactly one input, and it is the note. No amount field, no slider.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, isNot(TextInputType.number));
      expect(field.maxLength, kThesisMaxLength);
    });

    testWidgets('sends the rematch and hands back the challenge', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      final detail = await repo.fetchCall(
        callId: 'call_zed_fed',
        viewerUserId: viewer,
      );

      CallResponseResult? captured;
      await tester.pumpWidget(
        ChangeNotifierProvider<CallsProvider>.value(
          value: provider,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (context, _) => MaterialApp(
                  home: Builder(
                    builder:
                        (context) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () async {
                                captured = await showRematchSheet(
                                  context: context,
                                  offer: RematchOffer.fromEntry(
                                    detail.entry,
                                    viewerUserId: viewer,
                                  ),
                                );
                              },
                              child: const Text('open'),
                            ),
                          ),
                        ),
                  ),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Send the rematch'), findsOneWidget);

      await tester.tap(find.text('Send the rematch'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.response.kind, CallResponseKind.challenge);
      expect(captured!.invitation!.hasEscrow, isFalse);
      expect(captured!.resultingCall, isNull);
    });

    testWidgets('a signed-out person is asked for an account, not a wallet', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo);
      final detail = await repo.fetchCall(callId: 'call_zed_fed');

      await tester.pumpWidget(
        sheetHarness(
          provider,
          RematchOffer.fromEntry(detail.entry, viewerUserId: null),
        ),
      );
      await tester.pumpAndSettle();

      // One line on screen; the "no wallet, no stake" promise is read out
      // with it.
      expect(find.text('Sign in to send a free rematch'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Sign in to send a free rematch')).hint,
        contains('no wallet, no stake'),
      );
      expect(find.text('Send the rematch'), findsNothing);
    });

    testWidgets('a pending call gets an explanation, not a dead button', (
      tester,
    ) async {
      usePhoneSurface(tester);
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      final detail = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );

      await tester.pumpWidget(
        sheetHarness(
          provider,
          RematchOffer.fromEntry(detail.entry, viewerUserId: viewer),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not settled yet'), findsOneWidget);
      expect(find.text('Send the rematch'), findsNothing);
    });
  });
}
