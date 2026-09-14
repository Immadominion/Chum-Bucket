import 'dart:io';

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/calls_repository_factory.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/deeplink/call_deep_link.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The free loop, end to end, in one test.
///
/// This is the acceptance criterion the whole pivot is judged on:
///
///   a shared link -> the person and their call -> Back or Fade -> your own
///   immutable free call -> the venue resolves it -> a shareable receipt
///
/// It runs with **no wallet, no money and no session for the read half**, which
/// is the product claim: the social loop has to be useful before anyone
/// connects anything.
///
/// Every other test in the suite covers one seam. This one covers the joins
/// between them, which is where a vertical slice usually breaks: each packet's
/// own tests pass while the product does not work.
void main() {
  late MockCallsRepository repository;
  late CallsProvider provider;

  setUp(() {
    repository = MockCallsRepository(latency: Duration.zero);
    provider = CallsProvider(repository: repository);
  });

  tearDown(() => provider.dispose());

  group('the free loop', () {
    test('a stranger can open a shared link and read it with no account', () async {
      // Arrives from WhatsApp. No session, no wallet, nothing installed but the app.
      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final someoneElse = feed.entries.firstWhere(
        (e) => e.call.userId != MockCallsRepository.demoViewerUserId,
      );

      final link = repository.shareLinkForCall(someoneElse.call.id);
      final target = parseCallDeepLink(Uri.parse(link));
      expect(target, isA<CallLinkTarget>(), reason: 'a shared link must parse');
      expect((target! as CallLinkTarget).callId, someoneElse.call.id);

      // Signed out on purpose.
      expect(provider.isSignedIn, isFalse);
      final detail = await provider.loadCall(someoneElse.call.id);

      expect(detail, isNotNull);
      expect(detail!.entry.call.id, someoneElse.call.id);
      expect(
        detail.entry.author.displayName.isNotEmpty,
        isTrue,
        reason: 'the person is the point — a call must arrive attributed',
      );
    });

    test('Back creates the responder OWN call, linked to the source', () async {
      provider.setViewer(MockCallsRepository.demoViewerUserId);

      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final source = feed.entries.firstWhere(
        (e) =>
            e.call.userId != MockCallsRepository.demoViewerUserId &&
            e.market.status == MarketStatus.open &&
            !e.viewerHasCalled,
      );

      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: source.call.id,
          kind: CallResponseKind.back,
        ),
      );

      expect(result.resultingCall, isNotNull, reason: 'Back must mint a call');
      final mine = result.resultingCall!.call;
      expect(mine.userId, MockCallsRepository.demoViewerUserId);
      expect(mine.parentCallId, source.call.id);
      expect(mine.side, source.call.side, reason: 'Back takes the same side');
      expect(mine.fundingState, FundingState.none, reason: 'a call is free');
      expect(result.response.kind, CallResponseKind.back);
    });

    test('Fade takes the OPPOSITE side and is still a free call', () async {
      provider.setViewer(MockCallsRepository.demoViewerUserId);

      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final source = feed.entries.firstWhere(
        (e) =>
            e.call.userId != MockCallsRepository.demoViewerUserId &&
            e.market.status == MarketStatus.open &&
            !e.viewerHasCalled,
      );

      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: source.call.id,
          kind: CallResponseKind.fade,
        ),
      );

      final mine = result.resultingCall!.call;
      expect(
        mine.side,
        source.call.side == Side.yes ? Side.no : Side.yes,
        reason: 'Fade is disagreement — it must take the other side',
      );
      expect(mine.parentCallId, source.call.id);
      expect(mine.fundingState, FundingState.none);
    });

    test('Challenge mints NO call and carries no money', () async {
      provider.setViewer(MockCallsRepository.demoViewerUserId);

      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final source = feed.entries.firstWhere(
        (e) => e.call.userId != MockCallsRepository.demoViewerUserId,
      );

      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: source.call.id,
          kind: CallResponseKind.challenge,
        ),
      );

      expect(
        result.resultingCall,
        isNull,
        reason: 'a challenge is an invitation, not a call of your own',
      );
      expect(result.invitation, isNotNull);
    });

    test('a challenge has no money-shaped field to put a wager in', () {
      // This used to assert against `invitation.toString()`, which was
      // vacuous: ChallengeInvitation declares no toString, so Dart returns
      // "Instance of 'ChallengeInvitation'" and the check passed no matter
      // what the class contained. It would have passed with a stakeAmount
      // field sitting right there.
      //
      // The claim worth protecting is that no such field can be ADDED without
      // somebody noticing, and only reading the declaration can do that.
      final source =
          File(
            'lib/features/calls/data/calls_repository.dart',
          ).readAsStringSync();
      final start = source.indexOf('class ChallengeInvitation');
      expect(start, isNot(-1), reason: 'ChallengeInvitation must still exist');
      final body = source.substring(start, source.indexOf('\n}', start));

      final fields = RegExp(
        r'^\s*final\s+[\w<>?, ]+\s+(\w+);',
        multiLine: true,
      ).allMatches(body).map((m) => m.group(1)!).toList();

      expect(fields, isNotEmpty, reason: 'the regex must actually match fields');

      const banned = [
        'stake',
        'amount',
        'escrow',
        'wager',
        'lamport',
        'usdc',
        'payout',
        'balance',
        'price',
        'size',
        'fee',
      ];
      for (final field in fields) {
        for (final word in banned) {
          expect(
            field.toLowerCase(),
            isNot(contains(word)),
            reason:
                'ChallengeInvitation.$field is money-shaped. A challenge is a '
                'dare to go on record, not a wager — the absence of the field '
                'is the enforcement.',
          );
        }
      }
    });

    test('a call locks immutable, and a receipt reports the ORIGINAL call', () async {
      provider.setViewer(MockCallsRepository.demoViewerUserId);

      final markets = await repository.fetchOpenMarkets();
      final market = markets.first;

      final created = await provider.createCall(
        CreateCallInput(
          marketId: market.id,
          side: Side.yes,
          confidence: 0.7,
          thesis: 'Funding rates have been negative for three days.',
        ),
      );

      final call = created.call;
      expect(call.fundingState, FundingState.none);
      expect(call.lockedAt, isNotNull);
      expect(call.side, Side.yes);

      // Re-read it. Nothing about the locked facts may have moved.
      final reread = await provider.loadCall(call.id, force: true);
      expect(reread!.entry.call.side, call.side);
      expect(reread.entry.call.entryProbability, call.entryProbability);
      expect(reread.entry.call.lockedAt, call.lockedAt);
      expect(reread.entry.call.marketId, call.marketId);
    });

    test('a resolved call produces a receipt whose result matches the venue', () async {
      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final settled = feed.entries.where((e) => e.result != null).toList();
      expect(
        settled,
        isNotEmpty,
        reason: 'the seed must cover the resolved half of the loop',
      );

      for (final entry in settled) {
        final result = entry.result!;
        final expected = deriveCallOutcome(
          side: entry.call.side,
          resolution: result.resolution,
        );
        expect(
          result.outcome,
          expected,
          reason:
              'the receipt must agree with the frozen derivation rule for '
              'side=${entry.call.side} resolution=${result.resolution}',
        );
      }
    });

    test('a cancelled market is VOID — never a win and never a loss', () async {
      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final voided =
          feed.entries
              .where((e) => e.result?.resolution == Resolution.voided)
              .toList();

      for (final entry in voided) {
        expect(entry.result!.outcome, CallOutcome.voided);
        expect(entry.result!.outcome, isNot(CallOutcome.correct));
        expect(entry.result!.outcome, isNot(CallOutcome.incorrect));
      }
    });

    test('an unresolved market stays PENDING, however late it is', () async {
      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final pending = feed.entries.where(
        (e) =>
            e.market.status == MarketStatus.closedPendingResolution &&
            e.result != null,
      );

      for (final entry in pending) {
        expect(
          entry.result!.outcome,
          CallOutcome.pending,
          reason: 'no venue resolution means pending — never a guess',
        );
      }
    });

    test('a resolved call is shareable, and the link round-trips', () async {
      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      final settled = feed.entries.firstWhere((e) => e.result != null);

      final link = provider.shareLinkForCall(settled.call.id);
      final target = parseCallDeepLink(Uri.parse(link));
      expect((target! as CallLinkTarget).callId, settled.call.id);
    });
  });

  group('the money boundary holds across the whole loop', () {
    test('nothing in the feed is funded by default', () async {
      final feed = await repository.fetchFeed(mode: CallFeedMode.global);
      for (final entry in feed.entries) {
        expect(
          entry.call.fundingState,
          FundingState.none,
          reason: 'the default loop is free — a funded call is opt-in',
        );
      }
    });

    test('a signed-out person can read everything but write nothing', () async {
      expect(provider.isSignedIn, isFalse);

      // Reading works.
      await provider.loadFeed();
      expect(provider.feed, isNotEmpty);
      final markets = await repository.fetchOpenMarkets();
      expect(markets, isNotEmpty);

      // Writing does not.
      await expectLater(
        provider.createCall(
          CreateCallInput(marketId: markets.first.id, side: Side.yes),
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
    });
  });

  group('the configured backend', () {
    test('defaults to the mock, so a misconfigured build still runs', () {
      expect(resolveCallsBackend(overrides: const {}), CallsBackend.mock);
      expect(
        resolveCallsBackend(overrides: const {'CALLS_BACKEND': ''}),
        CallsBackend.mock,
      );
    });

    test('selects the BFF only when asked for by name', () {
      expect(
        resolveCallsBackend(overrides: const {'CALLS_BACKEND': 'bff'}),
        CallsBackend.bff,
      );
      expect(
        resolveCallsBackend(overrides: const {'CALLS_BACKEND': 'BFF'}),
        CallsBackend.bff,
      );
    });

    test('an unrecognised value falls back to the mock, not to a guess', () {
      expect(
        resolveCallsBackend(overrides: const {'CALLS_BACKEND': 'prod'}),
        CallsBackend.mock,
      );
    });

    test('buildCallsRepository honours the requested backend', () {
      expect(
        buildCallsRepository(
          backend: CallsBackend.mock,
          mockLatency: Duration.zero,
        ),
        isA<MockCallsRepository>(),
      );
    });
  });
}
