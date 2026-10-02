// Market creation screens over the real controller, client and transport, a
// scripted HTTP BFF and a synthetic wallet. Nothing reaches Panta or a chain.

import 'dart:typed_data';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/market_creation/market_creation.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'market_creation_fixtures.dart';

class _Wallet implements PantaWalletPort {
  int signs = 0;
  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    signs++;
    return signedCopy(unsigned);
  }
}

Finder get _vertical =>
    find
        .byWidgetPredicate(
          // A multi-line TextField scrolls too; it is not the page.
          (w) =>
              w is Scrollable &&
              w.axisDirection == AxisDirection.down &&
              w.restorationId != 'editable',
        )
        .last;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  // Moves the page itself rather than dragging: a drag that starts on a
  // multi-line field at 2x text scrolls the field, not the form.
  for (var i = 0; i < 80 && target.evaluate().isEmpty; i++) {
    final position = tester.state<ScrollableState>(_vertical).position;
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 300).clamp(0, position.maxScrollExtent).toDouble(),
    );
    await tester.pump();
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await _reveal(tester, find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  late FakeMarketBff bff;
  late MarketCreationController controller;

  setUp(() {
    bff = FakeMarketBff()..status();
    controller = MarketCreationController(
      client: bff.marketClient(),
      newKey: () => 'synthetic-key-1',
    );
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => MaterialApp(
              theme: AppTheme.lightTheme,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
              home: home,
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A launcher so the screen under test can pop a result.
  Widget launcher(Widget Function() screen, void Function(Object?) onResult) =>
      Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute<Object?>(builder: (_) => screen()),
                    );
                    onResult(result);
                  },
                  child: const Text('open'),
                ),
              ),
        ),
      );

  group('CreateMarketScreen', () {
    final now = DateTime.now().toUtc();
    MarketDraft prefill() => MarketDraft(
      question: 'Will synthetic BTC close above 120,000 on 31 Dec 2026?',
      category: MarketCategory.crypto,
      closesAt: now.add(const Duration(days: 3)),
      resolvesAt: now.add(const Duration(days: 3, hours: 1)),
      rules:
          'Resolves YES if the synthetic source reports a daily close above 120,000.',
      sources: const ['https://example.com/btc'],
    );

    testWidgets('says proposing is free, binary, and powered by Panta', (
      tester,
    ) async {
      await mount(tester, CreateMarketScreen(controller: controller));
      expect(find.text('Create a market'), findsOneWidget);
      expect(find.text('YES'), findsOneWidget);
      expect(find.text('NO'), findsOneWidget);
      for (final category in MarketCategory.values) {
        expect(find.text(category.label), findsOneWidget);
      }
      await _reveal(tester, find.text('Proposing is free'));
      expect(find.text('Powered by Panta'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('an empty form shows each problem and sends nothing', (
      tester,
    ) async {
      await mount(tester, CreateMarketScreen(controller: controller));
      await _tapText(tester, 'Send for review');
      // The errors push the end of the form further down.
      await _reveal(
        tester,
        find.text('Fix the highlighted fields to send this for review.'),
      );
      tester.state<ScrollableState>(_vertical).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.textContaining('Ask a full question'), findsOneWidget);
      expect(find.text('Pick a category.'), findsOneWidget);
      expect(find.text('Pick when trading closes.'), findsOneWidget);
      expect(bff.paths(), ['marketCreation.status']);
    });

    testWidgets('closed proposals disable sending and say why', (tester) async {
      bff.status(
        proposals: false,
        publishing: false,
        reason: 'Market proposals are not switched on yet.',
      );
      await mount(tester, CreateMarketScreen(controller: controller));
      expect(
        find.textContaining('Market proposals aren’t open yet.'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Send for review'));
      final button = tester.widget<ChumbucketPrimaryButton>(
        find.widgetWithText(ChumbucketPrimaryButton, 'Send for review'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a valid draft is proposed and the screen returns it', (
      tester,
    ) async {
      bff.handlers['marketCreation.propose'] = (_) => proposalJson();
      Object? result;
      await mount(
        tester,
        launcher(
          () => CreateMarketScreen(controller: controller, initial: prefill()),
          (r) => result = r,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Send for review');
      expect(result, isA<MarketProposal>());
      final sent = bff.requests.last;
      expect(sent.path, 'marketCreation.propose');
      expect(sent.input['category'], 'crypto');
      expect(sent.input['sources'], ['https://example.com/btc']);
    });

    testWidgets('a server refusal is shown on the form', (tester) async {
      bff.errors['marketCreation.propose'] = (
        code: 'TOO_MANY_REQUESTS',
        message:
            'You already have 5 markets waiting for review. Wait for a decision first.',
        status: 429,
      );
      await mount(
        tester,
        CreateMarketScreen(controller: controller, initial: prefill()),
      );
      await _tapText(tester, 'Send for review');
      expect(
        find.textContaining('5 markets waiting for review'),
        findsOneWidget,
      );
    });

    testWidgets('picking a close fills both times', (tester) async {
      await mount(tester, CreateMarketScreen(controller: controller));
      await _tapText(tester, 'Pick a date and time');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a date and time'), findsNothing);
      expect(find.text('Same as close'), findsNothing);
      expect(find.textContaining('(your time)'), findsNWidgets(2));
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      await mount(
        tester,
        CreateMarketScreen(controller: controller, initial: prefill()),
        width: 320,
        scale: 2,
      );
      await _reveal(tester, find.text('Send for review'));
      expect(tester.takeException(), isNull);
    });
  });

  group('ProposalDetailScreen', () {
    const id = '30000000-0000-4000-8000-000000000001';

    Future<void> open(
      WidgetTester tester,
      Map<String, Object?> json, {
      bool reviewer = false,
      PublishWallet? Function(BuildContext)? wallet,
      void Function(BuildContext, String)? openMarket,
      double width = 390,
      double scale = 1,
    }) async {
      bff.status(reviewer: reviewer);
      bff.handlers['marketCreation.get'] = (_) => json;
      bff.handlers['marketCreation.refreshPublish'] = (_) => json;
      await controller.loadStatus();
      await mount(
        tester,
        ProposalDetailScreen(
          controller: controller,
          proposalId: id,
          wallet: wallet ?? (_) => null,
          openMarket: openMarket,
        ),
        width: width,
        scale: scale,
      );
    }

    testWidgets('pending: the proposer waits and can withdraw', (tester) async {
      await open(tester, proposalJson());
      expect(find.text('Your market'), findsOneWidget);
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Withdraw proposal'), findsOneWidget);
    });

    testWidgets('pending: a reviewer approves it', (tester) async {
      bff.handlers['marketCreation.review'] =
          (_) => proposalJson(
            status: 'approved',
            viewerIsProposer: false,
            canWithdraw: false,
            canPublish: true,
          );
      await open(
        tester,
        proposalJson(viewerIsProposer: false, canWithdraw: false),
        reviewer: true,
      );
      expect(find.text('Market proposal'), findsOneWidget);
      await _tapText(tester, 'Approve');
      expect(bff.requests.last.input['decision'], 'approve');
      expect(find.text('Sponsor and publish'), findsOneWidget);
    });

    testWidgets('approved without a wallet says what publishing needs', (
      tester,
    ) async {
      await open(tester, proposalJson(status: 'approved', canPublish: true));
      expect(find.textContaining('Publish before'), findsOneWidget);
      await _tapText(tester, 'Publish on Panta');
      expect(
        find.textContaining('Publishing needs a Solana wallet with USDC'),
        findsOneWidget,
      );
      expect(bff.paths(), isNot(contains('marketCreation.preparePublish')));
    });

    testWidgets('approved while publishing is off: saved, not publishable', (
      tester,
    ) async {
      await open(tester, proposalJson(status: 'approved'));
      expect(
        find.textContaining('Publishing to Panta isn’t switched on yet'),
        findsOneWidget,
      );
      expect(find.text('Publish on Panta'), findsNothing);
    });

    testWidgets('publish: fee review, wallet approval, then publishing', (
      tester,
    ) async {
      final wallet = _Wallet();
      bff.handlers['marketCreation.preparePublish'] = (_) => reviewJson();
      bff.handlers['marketCreation.submitPublish'] =
          (_) => proposalJson(status: 'publishing', canWithdraw: false);
      await open(
        tester,
        proposalJson(status: 'approved', canPublish: true),
        wallet: (_) => (address: syntheticWallet, port: wallet),
      );
      // After the submit, a status check finds it still confirming.
      bff.handlers['marketCreation.refreshPublish'] =
          (_) => proposalJson(status: 'publishing', canWithdraw: false);
      await _tapText(tester, 'Publish on Panta');
      expect(find.text('Creation fee'), findsOneWidget);
      expect(find.text('50.00 USDC'), findsOneWidget);
      expect(find.text('10.00 USDC'), findsOneWidget);
      expect(find.text('40.00 USDC'), findsOneWidget);
      expect(find.textContaining('not refundable'), findsOneWidget);
      expect(find.text('Powered by Panta'), findsWidgets);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(wallet.signs, 0);

      await _tapText(tester, 'Approve in wallet');
      expect(wallet.signs, 1);
      expect(find.text('Market submitted'), findsOneWidget);
      expect(find.textContaining('Confirming with Solana'), findsOneWidget);
      await _tapText(tester, 'Done');
      expect(find.text('Publishing on Panta'), findsOneWidget);
      expect(find.text('Check status'), findsOneWidget);
    });

    testWidgets('publish: the open sheet follows the create until it is live', (
      tester,
    ) async {
      final wallet = _Wallet();
      bff.handlers['marketCreation.preparePublish'] = (_) => reviewJson();
      bff.handlers['marketCreation.submitPublish'] =
          (_) => proposalJson(status: 'publishing', canWithdraw: false);
      await open(
        tester,
        proposalJson(status: 'approved', canPublish: true),
        wallet: (_) => (address: syntheticWallet, port: wallet),
      );
      final live = proposalJson(
        status: 'live',
        canWithdraw: false,
        live: {
          'venueMarketId': syntheticEvent,
          'marketId': 'market-1',
          'creatorWallet': syntheticWallet,
          'liveAt': 1,
        },
      );
      bff.handlers['marketCreation.refreshPublish'] = (_) => live;
      bff.handlers['marketCreation.get'] = (_) => live;
      await _tapText(tester, 'Publish on Panta');
      await _tapText(tester, 'Approve in wallet');
      expect(find.text('Market submitted'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Market is live'), findsOneWidget);
      expect(find.textContaining('Anyone can now make a call'), findsOneWidget);
      await _tapText(tester, 'Done');
      expect(find.text('Live on Panta'), findsOneWidget);
      expect(find.text('Open market'), findsOneWidget);
    });

    testWidgets(
      'publish: a create released by the chain says no fee was taken',
      (tester) async {
        final wallet = _Wallet();
        bff.handlers['marketCreation.preparePublish'] = (_) => reviewJson();
        bff.handlers['marketCreation.submitPublish'] =
            (_) => proposalJson(status: 'publishing', canWithdraw: false);
        await open(
          tester,
          proposalJson(status: 'approved', canPublish: true),
          wallet: (_) => (address: syntheticWallet, port: wallet),
        );
        final released = proposalJson(status: 'approved', canPublish: true);
        bff.handlers['marketCreation.refreshPublish'] = (_) => released;
        await _tapText(tester, 'Publish on Panta');
        await _tapText(tester, 'Approve in wallet');
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('no creation fee was taken'),
          findsOneWidget,
        );
        await _tapText(tester, 'Done');
        expect(find.text('Publish on Panta'), findsOneWidget);
      },
    );

    testWidgets('the fee review sheet fits 320dp at 2x text', (tester) async {
      bff.handlers['marketCreation.preparePublish'] = (_) => reviewJson();
      await open(
        tester,
        proposalJson(status: 'approved', canPublish: true),
        wallet: (_) => (address: syntheticWallet, port: _Wallet()),
        width: 320,
        scale: 2,
      );
      await _tapText(tester, 'Publish on Panta');
      expect(find.text('Creation fee'), findsOneWidget);
      await _reveal(tester, find.text('Paid from'));
      expect(tester.takeException(), isNull);
      await _tapText(tester, 'Not now');
      expect(find.text('Creation fee'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('live: opens the callable market', (tester) async {
      String? opened;
      await open(
        tester,
        proposalJson(
          status: 'live',
          canWithdraw: false,
          live: {
            'venueMarketId': syntheticEvent,
            'marketId': '50000000-0000-4000-8000-000000000001',
            'creatorWallet': syntheticWallet,
            'liveAt': 1,
          },
        ),
        openMarket: (_, marketId) => opened = marketId,
      );
      expect(find.text('Live on Panta'), findsOneWidget);
      await _tapText(tester, 'Open market');
      expect(opened, '50000000-0000-4000-8000-000000000001');
    });

    testWidgets('rejected: the reason and note, and propose again', (
      tester,
    ) async {
      await open(
        tester,
        proposalJson(
          status: 'rejected',
          canWithdraw: false,
          review: {
            'decidedAt': 1,
            'reason': 'unverifiable',
            'note': 'Link the exchange page.',
          },
        ),
      );
      expect(find.text('Not approved'), findsWidgets);
      expect(
        find.textContaining('The result can’t be checked from the sources'),
        findsOneWidget,
      );
      expect(find.textContaining('Link the exchange page.'), findsOneWidget);
      await _tapText(tester, 'Propose it again');
      expect(find.text('Create a market'), findsOneWidget);
      expect(
        find.text('Will synthetic BTC close above 120,000 on 31 Dec 2026?'),
        findsOneWidget,
      );
    });

    testWidgets('expired: too late to publish', (tester) async {
      await open(tester, proposalJson(status: 'expired', canWithdraw: false));
      expect(find.text('Too late to publish'), findsOneWidget);
    });

    testWidgets('a reviewer rejects with a reason', (tester) async {
      bff.handlers['marketCreation.review'] =
          (_) => proposalJson(
            status: 'rejected',
            viewerIsProposer: false,
            canWithdraw: false,
            review: {'decidedAt': 1, 'reason': 'duplicate', 'note': null},
          );
      await open(
        tester,
        proposalJson(viewerIsProposer: false, canWithdraw: false),
        reviewer: true,
      );
      await _tapText(tester, 'Reject');
      expect(find.text('Reject proposal'), findsOneWidget);
      await tester.tap(find.text(ReviewReason.duplicate.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject proposal'));
      await tester.pumpAndSettle();
      expect(bff.requests.last.input, {
        'proposalId': id,
        'decision': 'reject',
        'reason': 'duplicate',
      });
      expect(find.textContaining('This market already exists'), findsOneWidget);
      // Proposing again is the proposer's move, not the reviewer's.
      expect(find.textContaining('propose a clearer version'), findsNothing);
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      await open(
        tester,
        proposalJson(status: 'approved', canPublish: true),
        width: 320,
        scale: 2,
      );
      await _reveal(tester, find.text('Powered by Panta'));
      expect(tester.takeException(), isNull);
    });
  });

  group('MyMarketsScreen', () {
    testWidgets('an honest empty state with a way to create', (tester) async {
      bff.handlers['marketCreation.mine'] = (_) => [];
      await mount(tester, MyMarketsScreen(controller: controller));
      expect(find.text('No markets yet'), findsOneWidget);
      expect(find.text('To review (0)'), findsNothing);
      await _tapText(tester, 'Create a market');
      expect(find.text('Question'), findsOneWidget);
      expect(find.text('Outcomes'), findsOneWidget);
    });

    testWidgets('lists your proposals with their state', (tester) async {
      bff.handlers['marketCreation.mine'] =
          (_) => [
            proposalJson(),
            proposalJson(
              id: '30000000-0000-4000-8000-000000000003',
              status: 'live',
              question: 'Will the synthetic final finish level?',
            ),
          ];
      await mount(tester, MyMarketsScreen(controller: controller));
      expect(find.text('In review'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(
        find.text('Will the synthetic final finish level?'),
        findsOneWidget,
      );
    });

    testWidgets('reviewers get the review queue', (tester) async {
      bff.status(reviewer: true);
      bff.handlers['marketCreation.mine'] = (_) => [];
      bff.handlers['marketCreation.reviewQueue'] =
          (_) => {
            'pending': [proposalJson(viewerIsProposer: false)],
            'approved': [],
          };
      await mount(tester, MyMarketsScreen(controller: controller));
      expect(find.text('To review (1)'), findsOneWidget);
      await tester.tap(find.text('To review (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(find.text('by @ada'), findsNothing);
      expect(find.textContaining('by @ada'), findsOneWidget);
    });
  });

  group('entry points', () {
    tearDown(() {
      MarketProposerCache.instance
        ..lookupOverride = null
        ..clear();
      MarketCreationAvailability.instance
        ..lookupOverride = null
        ..clear();
    });

    testWidgets('the Markets entry shows only while proposals are open', (
      tester,
    ) async {
      var open = false, asks = 0;
      MarketCreationAvailability.instance.lookupOverride = () async {
        asks++;
        return open;
      };
      Widget entry() =>
          Scaffold(body: CreateMarketEntry(onCreate: () {}, onOpenMine: () {}));
      await mount(tester, entry());
      expect(find.text('Create a market'), findsNothing);

      // Switched on: a fresh read (the closed answer has aged out) shows it.
      open = true;
      MarketCreationAvailability.instance.clear();
      await mount(tester, Scaffold(body: Container()));
      await mount(tester, entry());
      expect(find.text('Create a market'), findsOneWidget);
      expect(asks, 2);

      // Unreachable reads as closed for a first read.
      MarketCreationAvailability.instance
        ..clear()
        ..lookupOverride = () async => throw Exception('offline');
      await mount(tester, Scaffold(body: Container()));
      await mount(tester, entry());
      expect(find.text('Create a market'), findsNothing);
    });

    testWidgets('the Markets card opens create or yours', (tester) async {
      var created = 0, mine = 0;
      await mount(
        tester,
        Scaffold(
          body: CreateMarketEntryCard(
            onCreate: () => created++,
            onOpenMine: () => mine++,
          ),
        ),
        width: 320,
        scale: 2,
      );
      await tester.tap(find.text('Create a market'));
      await tester.tap(find.text('Yours'));
      expect((created, mine), (1, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a proposed live market names its proposer', (tester) async {
      final asked = <String>[];
      MarketProposerCache.instance.lookupOverride = (venueMarketId) async {
        asked.add(venueMarketId);
        return const MarketProposer(
          id: 'person-1',
          handle: 'ada',
          displayName: 'Ada',
        );
      };
      MarketProposer? opened;
      await mount(
        tester,
        Scaffold(
          body: MarketProposerLine(
            venueMarketId: syntheticEvent,
            onOpenPerson: (p) => opened = p,
          ),
        ),
      );
      expect(find.text('Proposed by @ada on Chumbucket'), findsOneWidget);
      await tester.tap(find.text('Proposed by @ada on Chumbucket'));
      expect(opened?.id, 'person-1');
      expect(asked, [syntheticEvent]);
    });

    testWidgets('a venue-created market shows no attribution', (tester) async {
      MarketProposerCache.instance.lookupOverride = (_) async => null;
      await mount(
        tester,
        Scaffold(body: MarketProposerLine(venueMarketId: syntheticEvent)),
      );
      expect(find.textContaining('Proposed by'), findsNothing);
    });
  });
}
