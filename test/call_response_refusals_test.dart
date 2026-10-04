// "Lock my YES call just loads and nothing happens" (production, 4 Oct):
// five POST /calls.respond 400s, and the sheet showed each refusal at the
// bottom of a long scroll, below the fold. These pin the fix:
//
//  * every refusal or failure stops the spinner and is said beside Lock;
//  * your own call never offers Back/Fade/Dare — it says "That's your call",
//    and a server "your own call" refusal turns the sheet into that state;
//  * "already on record" disables Lock and says so;
//  * a reason the content policy refuses is caught before anything is sent.
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_refusals.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

const _viewer = MockCallsRepository.demoViewerUserId;

/// Answers every respond with [failure] (and counts the attempts).
class _FailingRepository extends MockCallsRepository {
  _FailingRepository(this.failure);
  final Object failure;
  int attempts = 0;

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async {
    attempts++;
    throw failure;
  }

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) async {
    attempts++;
    throw failure;
  }
}

/// Records what the sheet sends, and answers as the mock does.
class _CapturingRepository extends MockCallsRepository {
  final sent = <RespondToCallInput>[];
  ChallengeInvitation? invitation;

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async {
    sent.add(input);
    final result = await super.respondToCall(
      input: input,
      viewerUserId: viewerUserId,
    );
    invitation = result.invitation;
    return result;
  }
}

Widget _host(CallsProvider provider, Widget child) =>
    ChangeNotifierProvider.value(
      value: provider,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(body: child),
            ),
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<(CallsProvider, CallFeedEntry)> _rig(
  MockCallsRepository repo, {
  String callId = 'call_ada_btc',
}) async {
  final provider = CallsProvider(repository: repo)..setViewer(_viewer);
  addTearDown(provider.dispose);
  final entry =
      (await repo.fetchCall(callId: callId, viewerUserId: _viewer)).entry;
  return (provider, entry);
}

ChumbucketPrimaryButton _lock(WidgetTester tester) =>
    tester.widget<ChumbucketPrimaryButton>(
      find.descendant(
        of: find.byKey(const ValueKey('response-lock')),
        matching: find.byType(ChumbucketPrimaryButton),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the answer sheet never spins without an answer', () {
    for (final (name, failure, shown) in [
      (
        'a lapsed-price refusal, in plain words',
        const CallsRejectedException(
          'Panta prices are missing or stale. Refresh before locking your call.',
        ),
        'Panta’s price is updating. Try again in a moment.',
      ),
      (
        'a refusal it does not know, verbatim',
        const CallsRejectedException('Panta calls are not enabled yet.'),
        'Panta calls are not enabled yet.',
      ),
      (
        'being offline',
        const CallsOfflineException(),
        'No connection. Try again when you’re back.',
      ),
      (
        'a failure that is not a CallsException at all',
        StateError('synthetic'),
        kCallUnexpectedFailure,
      ),
    ]) {
      testWidgets(name, (tester) async {
        _phone(tester);
        final repo = _FailingRepository(failure);
        final (provider, entry) = await _rig(repo);
        await tester.pumpWidget(
          _host(
            provider,
            CallResponseSheet(entry: entry, initialKind: CallResponseKind.fade),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Call NO'));
        await tester.pumpAndSettle();

        expect(repo.attempts, 1);
        expect(provider.isSubmitting, isFalse);
        expect(find.text('Please wait…'), findsNothing);
        expect(find.text(shown), findsOneWidget);
        // Beside the button, on screen — not below the fold.
        final error = tester.getRect(
          find.byKey(const ValueKey('call-inline-error')),
        );
        final lock = tester.getRect(
          find.byKey(const ValueKey('response-lock')),
        );
        expect(error.bottom, lessThanOrEqualTo(lock.top));
        expect(error.bottom, lessThanOrEqualTo(844));
        expect(find.text(shown).hitTestable(), findsOneWidget);
        // And Lock can be tapped again.
        expect(_lock(tester).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"your own call" from the server becomes "That’s your call"', (
      tester,
    ) async {
      _phone(tester);
      final repo = _FailingRepository(
        const CallsRejectedException("You can't respond to your own call."),
      );
      final (provider, entry) = await _rig(repo);
      await tester.pumpWidget(
        _host(
          provider,
          CallResponseSheet(entry: entry, initialKind: CallResponseKind.back),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call YES'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('response-own-call')), findsOneWidget);
      expect(find.text('That’s your call'), findsOneWidget);
      expect(find.byKey(const ValueKey('response-lock')), findsNothing);
      expect(find.text('Back'), findsNothing);
      expect(provider.isSubmitting, isFalse);
    });

    testWidgets('"already have a live call" disables Lock and says so', (
      tester,
    ) async {
      _phone(tester);
      final repo = _FailingRepository(
        const CallsRejectedException(
          'you already have a live call on this market',
        ),
      );
      final (provider, entry) = await _rig(repo);
      await tester.pumpWidget(_host(provider, CallResponseSheet(entry: entry)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call YES'));
      await tester.pumpAndSettle();

      expect(find.text('You’re already on record here'), findsOneWidget);
      expect(_lock(tester).onPressed, isNull);
      // A dare is still possible.
      await tester.tap(find.byKey(const ValueKey('response-challenge')));
      await tester.pumpAndSettle();
      expect(_lock(tester).onPressed, isNotNull);
    });

    testWidgets('a reason with a link is caught before anything is sent', (
      tester,
    ) async {
      _phone(tester);
      final repo = _FailingRepository(StateError('must not be called'));
      final (provider, entry) = await _rig(repo);
      await tester.pumpWidget(_host(provider, CallResponseSheet(entry: entry)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('response-add-reason')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'proof at scam.com');
      await tester.tap(find.text('Call YES'));
      await tester.pumpAndSettle();

      expect(repo.attempts, 0);
      expect(find.textContaining('Links aren\'t allowed'), findsOneWidget);
    });
  });

  group('your own call is never answered', () {
    testWidgets('the sheet shows "That’s your call", with no answers', (
      tester,
    ) async {
      _phone(tester);
      final repo = MockCallsRepository();
      final (provider, own) = await _rig(repo, callId: 'call_you_fed');
      expect(own.author.id, _viewer);
      await tester.pumpWidget(
        _host(
          provider,
          CallResponseSheet(entry: own, initialKind: CallResponseKind.fade),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('That’s your call'), findsOneWidget);
      for (final label in ['Back', 'Fade', 'Dare', 'Call NO']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      // One way out, and it closes the sheet.
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('the call detail offers no Back, Fade or Dare', (tester) async {
      _phone(tester);
      final repo = MockCallsRepository();
      final (provider, _) = await _rig(repo, callId: 'call_you_fed');
      await tester.pumpWidget(
        _host(provider, const CallDetailScreen(callId: 'call_you_fed')),
      );
      await tester.pumpAndSettle();

      expect(find.text('You’re on record'), findsOneWidget);
      expect(find.textContaining('Back ·'), findsNothing);
      expect(find.textContaining('Fade ·'), findsNothing);
      expect(find.byTooltip('Dare @you'), findsNothing);
    });

    testWidgets('a card for your own call has no Back or Fade', (tester) async {
      _phone(tester);
      final repo = MockCallsRepository();
      final (provider, own) = await _rig(repo, callId: 'call_you_fed');
      await tester.pumpWidget(
        _host(
          provider,
          SingleChildScrollView(
            child: CallCard(
              entry: own,
              onOpenCall: () {},
              onShareReceipt: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsNothing);
      expect(find.text('Fade'), findsNothing);
      expect(find.byTooltip('Share receipt'), findsOneWidget);
    });
  });

  group('the composer never spins without an answer', () {
    testWidgets('a failure that is not a CallsException stops and says so', (
      tester,
    ) async {
      _phone(tester);
      final repo = _FailingRepository(StateError('synthetic'));
      final (provider, entry) = await _rig(repo);
      await tester.pumpWidget(
        _host(
          provider,
          CallComposerSheet(market: entry.market, initialSide: Side.no),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call NO'));
      await tester.pumpAndSettle();

      expect(repo.attempts, 1);
      expect(provider.isSubmitting, isFalse);
      expect(find.text(kCallUnexpectedFailure).hitTestable(), findsOneWidget);
      expect(find.text('Please wait…'), findsNothing);
    });
  });

  group('refusal wording', () {
    test('internal states are never shown', () {
      for (final message in [
        'Panta prices are missing or stale. Refresh before locking your call.',
        "Panta's price for this market isn't available right now. Try again in a minute.",
      ]) {
        final shown = callRefusalMessage(CallsRejectedException(message));
        expect(shown, isNot(contains('stale')));
        expect(shown, isNot(contains('Refresh')));
      }
    });

    test('the server sentences the sheet acts on are recognised', () {
      expect(
        classifyCallRefusal(
          const CallsRejectedException("You can't respond to your own call."),
        ),
        CallRefusal.ownCall,
      );
      expect(
        classifyCallRefusal(
          const CallsRejectedException('you cannot back your own call'),
        ),
        CallRefusal.ownCall,
      );
      expect(
        classifyCallRefusal(
          const CallsRejectedException(
            'you already have a live call on this market',
          ),
        ),
        CallRefusal.alreadyOnRecord,
      );
      expect(
        classifyCallRefusal(
          const CallsRejectedException(
            'This market is not accepting new calls, so you can\'t fade this call any more.',
          ),
        ),
        CallRefusal.closed,
      );
      expect(
        classifyCallRefusal(
          const CallsRejectedException(
            'you have already challengeed this call',
          ),
        ),
        CallRefusal.alreadyAnswered,
      );
      expect(
        classifyCallRefusal(
          const CallsRejectedException(
            'New calls and responses use Panta only. This historical call '
            'remains available to read and share.',
          ),
        ),
        CallRefusal.closed,
      );
    });

    test('a machine\'s words are never shown, a sentence is', () {
      for (final error in <CallsException>[
        // A strict input check's issue list, as tRPC words a BAD_REQUEST.
        const CallsRejectedException(
          '[{"code":"unrecognized_keys","keys":["extra"],"path":[],'
          '"message":"Unrecognized key(s) in object: \'extra\'"}]',
        ),
        const CallsFailure('calls.respond: column "x" does not exist'),
        const CallsFailure(
          'The server sent something we could not read (calls.respond, '
          'status 502).',
        ),
        const CallsRejectedException('   '),
      ]) {
        expect(callRefusalMessage(error), kCallUnexpectedFailure);
      }
      expect(
        callRefusalMessage(
          const CallsRejectedException('Slow down a little and try again.'),
        ),
        'Slow down a little and try again.',
      );
    });
  });

  group('a dare', () {
    testWidgets('its words travel as the note the person dared reads', (
      tester,
    ) async {
      _phone(tester);
      final repo = _CapturingRepository();
      final (provider, entry) = await _rig(repo);
      await tester.pumpWidget(
        _host(
          provider,
          CallResponseSheet(
            entry: entry,
            initialKind: CallResponseKind.challenge,
            askForNotifications: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('response-add-reason')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Say it on Friday.');
      await tester.tap(find.text('Send the dare'));
      await tester.pumpAndSettle();

      final sent = repo.sent.single;
      expect(sent.kind, CallResponseKind.challenge);
      expect(sent.toJson()['note'], 'Say it on Friday.');
      expect(sent.toJson()['thesis'], isNull);
      expect(repo.invitation?.note, 'Say it on Friday.');
    });

    test('a Back/Fade sends its reason as the thesis, and no note', () {
      const fade = RespondToCallInput(
        targetCallId: 'c1',
        kind: CallResponseKind.fade,
        thesis: 'Funding is too hot.',
      );
      expect(fade.toJson()['thesis'], 'Funding is too hot.');
      expect(fade.toJson()['note'], isNull);
      // A caller that put a dare's words in `thesis` still reaches them.
      const dare = RespondToCallInput(
        targetCallId: 'c1',
        kind: CallResponseKind.challenge,
        thesis: 'Go again.',
        confidence: .7,
      );
      expect(dare.toJson()['note'], 'Go again.');
      expect(dare.toJson()['thesis'], isNull);
      expect(dare.toJson()['confidence'], isNull);
    });

    testWidgets('a second dare is refused once, and Send stops', (
      tester,
    ) async {
      _phone(tester);
      final repo = _FailingRepository(
        const CallsRejectedException('you have already challengeed this call'),
      );
      final (provider, entry) = await _rig(repo);
      await tester.pumpWidget(
        _host(
          provider,
          CallResponseSheet(
            entry: entry,
            initialKind: CallResponseKind.challenge,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send the dare'));
      await tester.pumpAndSettle();

      expect(find.text('You already answered this call.'), findsOneWidget);
      expect(find.textContaining('challengeed'), findsNothing);
      expect(_lock(tester).onPressed, isNull);
      expect(provider.isSubmitting, isFalse);
    });

    testWidgets('on a closed market the sheet opens on Dare', (tester) async {
      _phone(tester);
      final repo = MockCallsRepository();
      final (provider, entry) = await _rig(repo);
      final closed = CallFeedEntry(
        call: entry.call,
        author: entry.author,
        market: entry.market.copyWith(
          status: MarketStatus.closedPendingResolution,
        ),
      );
      await tester.pumpWidget(
        _host(
          provider,
          CallResponseSheet(entry: closed, initialKind: CallResponseKind.back),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Send the dare'), findsOneWidget);
      expect(_lock(tester).onPressed, isNotNull);
    });
  });
}
