// Market creation without widgets: the draft rules mirrored from the BFF (and
// through it, Panta), the wire models, the real client over a scripted HTTP
// BFF, and both controllers. Every key, wallet and transaction is synthetic.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/market_creation/market_creation.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';

import 'market_creation_fixtures.dart';

final _now = DateTime.utc(2026, 10, 2, 12);

MarketDraft _draft({
  String question = 'Will synthetic BTC close above 120,000 on 31 Dec 2026?',
  MarketCategory category = MarketCategory.crypto,
  Duration closesIn = const Duration(days: 3),
  Duration resolvesAfterClose = const Duration(hours: 1),
  String rules =
      'Resolves YES if the synthetic source reports a daily close above 120,000.',
  List<String> sources = const ['https://example.com/btc'],
  String? description,
}) {
  final closes = _now.add(closesIn);
  return MarketDraft(
    question: question,
    category: category,
    closesAt: closes,
    resolvesAt: closes.add(resolvesAfterClose),
    rules: rules,
    sources: sources,
    description: description,
  );
}

List<DraftField> _fields(MarketDraft draft) => [
  for (final p in validateDraft(draft.normalized(), now: _now)) p.field,
];

class _Wallet implements PantaWalletPort {
  int signs = 0;
  FutureOr<Uint8List> Function(Uint8List unsigned)? reply;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    signs++;
    return reply == null ? signedCopy(unsigned) : await reply!(unsigned);
  }
}

void main() {
  group('draft rules (mirror rules.ts)', () {
    test('a complete draft is proposable', () {
      expect(_fields(_draft()), isEmpty);
    });

    test('question bounds and hidden characters', () {
      expect(_fields(_draft(question: 'Too short')), [DraftField.question]);
      expect(_fields(_draft(question: 'Q' * 513)), [DraftField.question]);
      expect(_fields(_draft(question: 'Will this\u0007 resolve YES?')), [
        DraftField.question,
      ]);
      // Exactly Panta's 512 limit is fine.
      expect(_fields(_draft(question: 'Q' * 512)), isEmpty);
    });

    test('trading must stay open long enough for review, within two years', () {
      expect(_fields(_draft(closesIn: const Duration(hours: 2))), [
        DraftField.closesAt,
      ]);
      expect(_fields(_draft(closesIn: const Duration(hours: 3))), isEmpty);
      expect(_fields(_draft(closesIn: const Duration(days: 731))), [
        DraftField.closesAt,
      ]);
    });

    test('the result is known after the close and within 90 days', () {
      expect(_fields(_draft(resolvesAfterClose: const Duration(minutes: -1))), [
        DraftField.resolvesAt,
      ]);
      expect(_fields(_draft(resolvesAfterClose: Duration.zero)), isEmpty);
      expect(_fields(_draft(resolvesAfterClose: const Duration(days: 91))), [
        DraftField.resolvesAt,
      ]);
    });

    test('rules need enough detail and stay under Panta\'s 2048', () {
      expect(_fields(_draft(rules: 'YES if up')), [DraftField.rules]);
      expect(_fields(_draft(rules: 'R' * 2049)), [DraftField.rules]);
      expect(_fields(_draft(rules: 'R' * 2048)), isEmpty);
    });

    test('sources: 1 to 20 public http(s) links', () {
      expect(_fields(_draft(sources: const [])), [DraftField.sources]);
      expect(_fields(_draft(sources: const ['   '])), [DraftField.sources]);
      expect(
        _fields(
          _draft(sources: [for (var i = 0; i < 21; i++) 'https://e$i.com/x']),
        ),
        [DraftField.sources],
      );
      for (final bad in [
        'ftp://example.com/x',
        'https://localhost/x',
        'http://127.0.0.1/x',
        'https://printer.local/x',
        'https://user:pw@example.com/x',
        'https://intranet/x',
        'https://[::1]/x',
        'https://example.com/a b',
      ]) {
        expect(isPublicSourceUrl(bad), isFalse, reason: bad);
      }
      expect(isPublicSourceUrl('https://www.coingecko.com/en'), isTrue);
      expect(isPublicSourceUrl('http://example.org/score'), isTrue);
    });

    test('description is optional and bounded', () {
      expect(_fields(_draft(description: '   ')), isEmpty);
      expect(_fields(_draft(description: 'D' * 1001)), [
        DraftField.description,
      ]);
    });

    test('normalising trims, collapses spaces and de-duplicates sources', () {
      final normal =
          _draft(
            question: '  Will   synthetic BTC\nclose above 120,000?  ',
            sources: const [
              ' https://example.com/a ',
              'https://example.com/a',
              '',
              'https://example.com/b',
            ],
            description: '  ',
          ).normalized();
      expect(normal.question, 'Will synthetic BTC close above 120,000?');
      expect(normal.sources, [
        'https://example.com/a',
        'https://example.com/b',
      ]);
      expect(normal.description, isNull);
    });

    test('server rules override the defaults', () {
      final strict = MarketCreationRules.fromJson({
        ...rulesJson(),
        'questionMin': 60,
      });
      final problems = validateDraft(
        _draft(question: 'Will this short question pass a stricter rule?'),
        now: _now,
        rules: strict,
      );
      expect(problems.single.field, DraftField.question);
      expect(problems.single.message, contains('60'));
    });
  });

  group('wire models', () {
    test('every server status parses and unknown ones fail loudly', () {
      for (final status in ProposalStatus.values) {
        final p = MarketProposal.fromJson(proposalJson(status: status.wire));
        expect(p.status, status);
      }
      expect(
        () => MarketProposal.fromJson(proposalJson(status: 'mystery')),
        throwsA(isA<MarketCreationFormatException>()),
      );
    });

    test('review, publishing and live details are read', () {
      final rejected = MarketProposal.fromJson(
        proposalJson(
          status: 'rejected',
          review: {
            'decidedAt': 1,
            'reason': 'unverifiable',
            'note': 'Add a source.',
          },
        ),
      );
      expect(rejected.review!.reason, ReviewReason.unverifiable);
      expect(rejected.review!.note, 'Add a source.');

      final publishing = MarketProposal.fromJson(
        proposalJson(status: 'publishing'),
      );
      expect(publishing.publishingWallet, syntheticWallet);

      final live = MarketProposal.fromJson(
        proposalJson(
          status: 'live',
          live: {
            'venueMarketId': syntheticEvent,
            'marketId': '50000000-0000-4000-8000-000000000001',
            'creatorWallet': syntheticWallet,
            'liveAt': 2,
          },
        ),
      );
      expect(live.live!.marketId, '50000000-0000-4000-8000-000000000001');
      expect(live.categoryLabel, 'Crypto');
    });

    test(
      'a publish review must be USDC on mainnet with a fee that adds up',
      () {
        final ok = PublishReview.fromJson(reviewJson());
        expect(formatUsdcBaseUnits(ok.feeBaseUnits), '50.00');
        expect(formatUsdcBaseUnits(ok.liquidityBaseUnits), '10.00');
        expect(
          () => PublishReview.fromJson({...reviewJson(), 'currency': 'SOL'}),
          throwsA(isA<MarketCreationFormatException>()),
        );
        expect(
          () => PublishReview.fromJson({
            ...reviewJson(),
            'network': 'solana-devnet',
          }),
          throwsA(isA<MarketCreationFormatException>()),
        );
        expect(
          () => PublishReview.fromJson({
            ...reviewJson(),
            'platformBaseUnits': '45000000',
          }),
          throwsA(isA<MarketCreationFormatException>()),
        );
        expect(
          () => PublishReview.fromJson({...reviewJson(), 'feeBaseUnits': '-1'}),
          throwsA(isA<MarketCreationFormatException>()),
        );
      },
    );

    test('USDC formatting never uses floating point', () {
      expect(formatUsdcBaseUnits('0'), '0.00');
      expect(formatUsdcBaseUnits('1'), '0.00');
      expect(formatUsdcBaseUnits('12345678'), '12.34');
      expect(formatUsdcBaseUnits('100000000000000000'), '100000000000.00');
    });
  });

  group('create transaction checks', () {
    test('accepts the reviewed wallet\'s unsigned create only', () {
      final tx = syntheticCreateTx();
      expect(() => checkUnsignedCreate(tx, syntheticWallet), returnsNormally);
      expect(
        () => checkUnsignedCreate(tx, otherWallet),
        throwsA(isA<CreateTransactionRejected>()),
      );
      expect(
        () => checkUnsignedCreate(signedCopy(tx), syntheticWallet),
        throwsA(isA<CreateTransactionRejected>()),
      );
      expect(
        () => checkUnsignedCreate(Uint8List(0), syntheticWallet),
        throwsA(isA<CreateTransactionRejected>()),
      );
      expect(
        () => checkUnsignedCreate(
          Uint8List.fromList([...tx, 0]),
          syntheticWallet,
        ),
        throwsA(isA<CreateTransactionRejected>()),
      );
    });

    test('the wallet must return the same message, signed', () {
      final tx = syntheticCreateTx();
      expect(
        () => checkSignedCreate(tx, signedCopy(tx), syntheticWallet),
        returnsNormally,
      );
      expect(
        () => checkSignedCreate(tx, tx, syntheticWallet),
        throwsA(isA<CreateTransactionRejected>()),
      );
      expect(
        () => checkSignedCreate(
          tx,
          signedCopy(syntheticCreateTx(dataByte: 8)),
          syntheticWallet,
        ),
        throwsA(isA<CreateTransactionRejected>()),
      );
    });
  });

  group('client and MarketCreationController', () {
    late FakeMarketBff bff;
    late MarketCreationController controller;
    var keys = 0;

    setUp(() {
      bff = FakeMarketBff()..status(reviewer: false);
      keys = 0;
      controller = MarketCreationController(
        client: bff.marketClient(),
        newKey: () => 'synthetic-key-${++keys}',
      );
    });
    tearDown(() => controller.dispose());

    test('status carries the server rules and the session token', () async {
      await controller.loadStatus();
      expect(controller.status!.proposalsEnabled, isTrue);
      expect(controller.rules.proposeMinLead, const Duration(hours: 3));
      expect(
        bff.requests.single.headers['authorization'],
        'Bearer synthetic-session',
      );
    });

    test('propose sends the draft, never an identity field', () async {
      bff.handlers['marketCreation.propose'] = (_) => proposalJson();
      final draft = _draft(description: 'Context').normalized();
      final proposal = await controller.propose(draft);
      expect(proposal.status, ProposalStatus.pendingReview);
      final input = bff.requests.single.input;
      expect(input.keys.toSet(), {
        'question',
        'category',
        'closesAt',
        'resolvesAt',
        'rules',
        'sources',
        'description',
        'idempotencyKey',
      });
      expect(input['category'], 'crypto');
      expect(input['closesAt'], draft.closesAt.millisecondsSinceEpoch);
      expect(controller.mine.single.id, proposal.id);
    });

    test(
      'a dropped reply is retried with the same key; new text gets a new key',
      () async {
        bff.offline = true;
        final draft = _draft().normalized();
        await expectLater(
          controller.propose(draft),
          throwsA(isA<CallsOfflineException>()),
        );
        bff.offline = false;
        bff.handlers['marketCreation.propose'] = (_) => proposalJson();
        await controller.propose(draft);
        expect(bff.requests.single.input['idempotencyKey'], 'synthetic-key-1');

        await controller.propose(
          _draft(
            question: 'Will a different synthetic question resolve?',
          ).normalized(),
        );
        expect(bff.requests.last.input['idempotencyKey'], 'synthetic-key-2');
      },
    );

    test('a server refusal reaches the form as readable copy', () async {
      bff.errors['marketCreation.propose'] = (
        code: 'TOO_MANY_REQUESTS',
        message: 'You already have 5 markets waiting for review.',
        status: 429,
      );
      await expectLater(
        controller.propose(_draft().normalized()),
        throwsA(
          isA<CallsRejectedException>().having(
            (e) => e.message,
            'message',
            contains('5 markets waiting'),
          ),
        ),
      );
    });

    test('the review queue is only asked for by reviewers', () async {
      bff.handlers['marketCreation.reviewQueue'] =
          (_) => {'pending': [], 'approved': []};
      await controller.loadStatus();
      await controller.loadQueue();
      expect(bff.paths(), ['marketCreation.status']);

      bff.status(reviewer: true);
      await controller.loadStatus();
      await controller.loadQueue();
      expect(bff.paths().last, 'marketCreation.reviewQueue');
    });

    test(
      'approving moves a proposal from pending to approved in the queue',
      () async {
        bff.status(reviewer: true);
        const id = '30000000-0000-4000-8000-000000000002';
        bff.handlers['marketCreation.reviewQueue'] =
            (_) => {
              'pending': [proposalJson(id: id, viewerIsProposer: false)],
              'approved': [],
            };
        bff.handlers['marketCreation.review'] =
            (input) => proposalJson(
              id: id,
              status: input['decision'] == 'approve' ? 'approved' : 'rejected',
              viewerIsProposer: false,
              canPublish: true,
            );
        await controller.loadStatus();
        await controller.loadQueue();
        expect(controller.queue!.pending, hasLength(1));

        final errors = <String>[];
        await controller.approve(id, onError: errors.add);
        expect(errors, isEmpty);
        expect(controller.queue!.pending, isEmpty);
        expect(controller.queue!.approved.single.id, id);
        expect(controller.find(id)!.canPublish, isTrue);
        expect(bff.requests.last.input, {
          'proposalId': id,
          'decision': 'approve',
        });
      },
    );

    test('rejecting sends the reason and a trimmed note', () async {
      bff.handlers['marketCreation.review'] =
          (_) => proposalJson(status: 'rejected');
      await controller.reject(
        '30000000-0000-4000-8000-000000000001',
        reason: ReviewReason.unclear,
        note: '  Say which exchange.  ',
        onError: (_) {},
      );
      expect(bff.requests.single.input, {
        'proposalId': '30000000-0000-4000-8000-000000000001',
        'decision': 'reject',
        'reason': 'unclear',
        'note': 'Say which exchange.',
      });
    });

    test('refresh re-checks a publishing proposal against the chain', () async {
      bff.handlers['marketCreation.get'] =
          (_) => proposalJson(status: 'publishing');
      bff.handlers['marketCreation.refreshPublish'] =
          (_) => proposalJson(status: 'publishing');
      const id = '30000000-0000-4000-8000-000000000001';
      await controller.refresh(id, onError: (_) {});
      expect(bff.paths().last, 'marketCreation.get');
      await controller.refresh(id, onError: (_) {});
      expect(bff.paths().last, 'marketCreation.refreshPublish');
    });

    test(
      'loading your markets re-checks sent creates, so they reach Panta',
      () async {
        const sent = '30000000-0000-4000-8000-000000000001';
        bff.handlers['marketCreation.mine'] =
            (_) => [
              proposalJson(status: 'publishing'),
              proposalJson(
                id: '30000000-0000-4000-8000-000000000003',
                status: 'approved',
              ),
            ];
        bff.handlers['marketCreation.refreshPublish'] =
            (_) => proposalJson(
              status: 'live',
              canWithdraw: false,
              live: {
                'venueMarketId': syntheticEvent,
                'marketId': 'market-1',
                'creatorWallet': syntheticWallet,
                'liveAt': 1,
              },
            );
        await controller.loadMine();
        await pumpEventQueue();
        final checks = [
          for (final r in bff.requests)
            if (r.path == 'marketCreation.refreshPublish') r.input,
        ];
        expect(checks, [
          {'proposalId': sent},
        ]);
        expect(controller.find(sent)!.status, ProposalStatus.live);
        expect(controller.mine.first.status, ProposalStatus.live);
        expect(controller.isBusy(sent), isFalse);
      },
    );

    test(
      'an action error is reported and the proposal is not busy after',
      () async {
        bff.errors['marketCreation.withdraw'] = (
          code: 'PRECONDITION_FAILED',
          message: 'This market is already live.',
          status: 412,
        );
        final errors = <String>[];
        await controller.withdraw(
          '30000000-0000-4000-8000-000000000001',
          onError: errors.add,
        );
        expect(errors, ['This market is already live.']);
        expect(
          controller.isBusy('30000000-0000-4000-8000-000000000001'),
          isFalse,
        );
      },
    );

    test('a signed-out reply says what to do for markets', () async {
      bff.errors['marketCreation.mine'] = (
        code: 'UNAUTHORIZED',
        message: 'Sign in to create markets.',
        status: 401,
      );
      await controller.loadMine();
      expect(controller.mineError, 'Sign in again to manage your markets.');
    });

    test('proposerOf reads the public attribution', () async {
      bff.handlers['marketCreation.byMarket'] =
          (_) => {
            'proposalId': '30000000-0000-4000-8000-000000000001',
            'proposer': {
              'id': 'person-1',
              'handle': 'ada',
              'displayName': 'Ada',
            },
            'liveAt': 1,
          };
      final proposer = await bff
          .marketClient(token: null)
          .proposerOf(syntheticEvent);
      expect(proposer!.atHandle, '@ada');
      expect(bff.requests.single.headers.containsKey('authorization'), isFalse);

      bff.handlers['marketCreation.byMarket'] = (_) => null;
      expect(await bff.marketClient().proposerOf(syntheticEvent), isNull);
    });
  });

  group('PublishMarketController', () {
    late FakeMarketBff bff;
    late _Wallet wallet;
    late PublishMarketController publish;
    var clock = DateTime.now().toUtc();

    setUp(() {
      bff = FakeMarketBff();
      wallet = _Wallet();
      clock = DateTime.now().toUtc();
      bff.handlers['marketCreation.preparePublish'] = (_) => reviewJson();
      bff.handlers['marketCreation.submitPublish'] =
          (_) => proposalJson(status: 'publishing', canWithdraw: false);
      publish = PublishMarketController(
        client: bff.marketClient(),
        proposal: MarketProposal.fromJson(
          proposalJson(status: 'approved', canPublish: true),
        ),
        wallet: syntheticWallet,
        walletPort: wallet,
        now: () => clock,
      );
    });
    tearDown(() => publish.dispose());

    test(
      'quote -> wallet signs -> the signed bytes are submitted once',
      () async {
        await publish.prepare();
        expect(publish.phase, PublishPhase.review);
        expect(publish.review!.feeBaseUnits, '50000000');
        expect(wallet.signs, 0, reason: 'nothing is signed by a quote');
        expect(bff.requests.single.input, {
          'proposalId': '30000000-0000-4000-8000-000000000001',
          'wallet': syntheticWallet,
        });

        await publish.approveAndSubmit();
        expect(wallet.signs, 1);
        expect(publish.phase, PublishPhase.done);
        expect(publish.proposal.status, ProposalStatus.publishing);
        final submit = bff.requests.last;
        expect(submit.path, 'marketCreation.submitPublish');
        expect(
          submit.input['signedTransaction'],
          base64Encode(signedCopy(syntheticCreateTx())),
        );
        expect(
          submit.input['sessionId'],
          '40000000-0000-4000-8000-000000000001',
        );
      },
    );

    test('a create paid by another wallet never reaches the wallet', () async {
      bff.handlers['marketCreation.preparePublish'] =
          (_) => reviewJson(tx: syntheticCreateTx(payerByte: 9));
      await publish.prepare();
      expect(publish.phase, PublishPhase.failed);
      expect(publish.review, isNull);
      expect(publish.error, contains('Nothing was sent'));
      await publish.approveAndSubmit();
      expect(wallet.signs, 0);
    });

    test('a review for a different wallet is refused', () async {
      bff.handlers['marketCreation.preparePublish'] =
          (_) => reviewJson(wallet: otherWallet);
      await publish.prepare();
      expect(publish.phase, PublishPhase.failed);
      expect(publish.review, isNull);
    });

    test('a wallet that changes the message is caught before submit', () async {
      await publish.prepare();
      wallet.reply = (_) => signedCopy(syntheticCreateTx(dataByte: 99));
      await publish.approveAndSubmit();
      expect(publish.phase, PublishPhase.review);
      expect(publish.submitted, isFalse);
      expect(publish.error, contains('different transaction'));
      expect(bff.paths(), isNot(contains('marketCreation.submitPublish')));
    });

    test('cancelling in the wallet sends nothing', () async {
      await publish.prepare();
      wallet.reply = (_) => throw const PantaWalletCancelled();
      await publish.approveAndSubmit();
      expect(publish.phase, PublishPhase.review);
      expect(publish.error, contains('Nothing was signed'));
      expect(bff.paths(), isNot(contains('marketCreation.submitPublish')));
    });

    test('an expired quote is never signed', () async {
      await publish.prepare();
      clock = clock.add(const Duration(minutes: 5));
      expect(publish.reviewExpired, isTrue);
      await publish.approveAndSubmit();
      expect(wallet.signs, 0);
      expect(publish.phase, PublishPhase.failed);
      expect(publish.error, contains('expired'));
    });

    test(
      'an uncertain submit is retried with the identical bytes, unsigned again never',
      () async {
        await publish.prepare();
        bff.offline = true;
        await publish.approveAndSubmit();
        expect(publish.phase, PublishPhase.failed);
        expect(publish.submitted, isTrue);

        bff.offline = false;
        await publish.prepare(); // ignored: signed bytes already exist
        expect(
          bff.paths().where((p) => p == 'marketCreation.preparePublish'),
          hasLength(1),
        );
        await publish.approveAndSubmit();
        expect(wallet.signs, 1);
        expect(publish.phase, PublishPhase.done);
        expect(
          bff.requests.last.input['signedTransaction'],
          base64Encode(signedCopy(syntheticCreateTx())),
        );
      },
    );

    test('a server error after signing keeps the bytes for a retry', () async {
      await publish.prepare();
      bff.errors['marketCreation.submitPublish'] = (
        code: 'BAD_GATEWAY',
        message: 'Panta did not answer.',
        status: 502,
      );
      await publish.approveAndSubmit();
      expect(publish.phase, PublishPhase.failed);
      expect(publish.submitted, isTrue);
      expect(publish.error, 'Panta did not answer.');
    });

    test(
      'a sent create is followed up until it is live, then checks stop',
      () async {
        final fast = PublishMarketController(
          client: bff.marketClient(),
          proposal: MarketProposal.fromJson(
            proposalJson(status: 'approved', canPublish: true),
          ),
          wallet: syntheticWallet,
          walletPort: wallet,
          confirmEvery: const Duration(milliseconds: 1),
        );
        addTearDown(fast.dispose);
        var checks = 0;
        bff.handlers['marketCreation.refreshPublish'] =
            (_) =>
                ++checks < 2
                    ? proposalJson(status: 'publishing', canWithdraw: false)
                    : proposalJson(
                      status: 'live',
                      canWithdraw: false,
                      live: {
                        'venueMarketId': syntheticEvent,
                        'marketId': 'market-1',
                        'creatorWallet': syntheticWallet,
                        'liveAt': 1,
                      },
                    );
        await fast.prepare();
        await fast.approveAndSubmit();
        expect(fast.phase, PublishPhase.done);
        expect(fast.confirming, isTrue);
        for (var i = 0; i < 50 && fast.confirming; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(fast.proposal.status, ProposalStatus.live);
        expect(fast.confirming, isFalse);
        expect(checks, 2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(checks, 2, reason: 'no checks after it is live');
      },
    );

    test('follow-up checks are bounded and stop when the sheet goes', () async {
      final bounded = PublishMarketController(
        client: bff.marketClient(),
        proposal: MarketProposal.fromJson(
          proposalJson(status: 'approved', canPublish: true),
        ),
        wallet: syntheticWallet,
        walletPort: wallet,
        confirmAttempts: 3,
        confirmEvery: const Duration(milliseconds: 1),
      );
      var checks = 0;
      bff.handlers['marketCreation.refreshPublish'] = (_) {
        checks++;
        return proposalJson(status: 'publishing', canWithdraw: false);
      };
      await bounded.prepare();
      await bounded.approveAndSubmit();
      for (var i = 0; i < 50 && bounded.confirming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(checks, 3);
      expect(bounded.confirming, isFalse);
      expect(bounded.proposal.status, ProposalStatus.publishing);

      final closed = PublishMarketController(
        client: bff.marketClient(),
        proposal: MarketProposal.fromJson(
          proposalJson(status: 'approved', canPublish: true),
        ),
        wallet: syntheticWallet,
        walletPort: wallet,
        confirmEvery: const Duration(milliseconds: 1),
      );
      await closed.prepare();
      await closed.approveAndSubmit();
      expect(closed.confirming, isTrue);
      closed.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(checks, 3, reason: 'a closed sheet makes no more checks');
    });

    test('a definite refusal drops the bytes and offers a fresh quote', () async {
      await publish.prepare();
      bff.errors['marketCreation.submitPublish'] = (
        code: 'PRECONDITION_FAILED',
        message:
            'The wallet approval arrived after the quote expired. Review a fresh quote; nothing was sent.',
        status: 412,
      );
      await publish.approveAndSubmit();
      expect(publish.phase, PublishPhase.failed);
      expect(publish.submitted, isFalse);
      expect(publish.review, isNull);

      bff.errors.remove('marketCreation.submitPublish');
      await publish.prepare();
      expect(publish.phase, PublishPhase.review);
      expect(
        bff.paths().where((p) => p == 'marketCreation.preparePublish'),
        hasLength(2),
      );
    });
  });
}
