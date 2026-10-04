/// A call with an amount, from tap to fill (money contract, flow (a)):
/// needs funds and needs gas continue with the same key, a ready quote is
/// checked against the request before any signer sees it, a signature is
/// never a fill, and a failed trade offers retry, keep free or discard.
library;

import 'dart:convert';

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/money/data/money_models.dart';
import 'package:chumbucket/features/money/money_call_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'money_fakes.dart';

const tapKey = 'tap-key-000000000001';
const freshCallId = '88888888-8888-4888-8888-888888888888';

void main() {
  late FakeMoneyServer server;
  late FakeBuyPort port;
  String? selected;

  setUp(() {
    server = FakeMoneyServer();
    port = FakeBuyPort();
    selected = signerWallet;
  });

  MoneyCallController controller({
    MoneyCallRequest? request,
    Future<void> Function(String, BigInt)? topUp,
    FakeBuyPort? signer,
    int now = moneyNow,
  }) {
    final c = MoneyCallController(
      client: server.moneyClient(),
      trading: server.tradingClient(),
      request:
          request ??
          MoneyCallRequest(
            kind: MoneyCallKind.own,
            marketId: pantaMarketId,
            side: Side.yes,
            venueMarketId: venueMarket,
            question: 'Will BTC trade above 150k?',
            amountBaseUnits: BigInt.from(5000000),
          ),
      signer: MoneyBuySigner(
        address: signerWallet,
        port: signer ?? port,
        selectedWallet: () => selected,
      ),
      topUp: topUp,
      newIdempotencyKey: () => tapKey,
      now: () => DateTime.fromMillisecondsSinceEpoch(now),
      pollEvery: const Duration(hours: 1),
    );
    addTearDown(c.dispose);
    return c;
  }

  test('ready → sign → pending; funded only when the server says so', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('pantaTrading.submit', [venueOrderJson()])
      ..on('money.callStatus', [
        callStatusJson(),
        // Filled on Panta but not yet stamped: still pending.
        callStatusJson(trade: 'FILLED'),
        callStatusJson(state: 'FUNDED', trade: 'FILLED'),
      ]);
    final c = controller();
    await c.prepare();
    expect(c.step, MoneyCallStep.review);
    expect(c.prepared!.review.amountUsdc, '5.000000');
    final prepare = server.inputs('money.prepareCall').single;
    expect(prepare, {
      'kind': 'own',
      'marketId': pantaMarketId,
      'side': 'YES',
      'amountBaseUnits': '5000000',
      'idempotencyKey': tapKey,
      'wallet': signerWallet,
      'visibility': 'public',
    });

    await c.sign();
    expect(port.signed, hasLength(1));
    final submit = server.inputs('pantaTrading.submit').single;
    expect(submit['orderId'], orderId);
    expect(
      base64Decode(submit['signedTransaction'] as String),
      moneySigned(moneyUnsigned()),
    );
    expect(c.step, MoneyCallStep.pending);

    await c.refreshStatus();
    expect(c.step, MoneyCallStep.pending);
    await c.refreshStatus();
    expect(c.step, MoneyCallStep.pending, reason: 'FILLED trade, not FUNDED');
    expect(c.moneyCall!.isFunded, isFalse);
    await c.refreshStatus();
    expect(c.step, MoneyCallStep.funded);
    expect(c.moneyCall!.filledBaseUnits, BigInt.from(5000000));
  });

  test('needs funds: nothing is created, then the same tap continues', () async {
    server.on('money.prepareCall', [needsFundsJson(), readyJson()]);
    final c = controller();
    await c.prepare();
    expect(c.step, MoneyCallStep.needsFunds);
    expect(c.needsFunds!.shortfallBaseUnits, BigInt.from(4000000));
    expect(c.moneyCall, isNull);
    expect(port.signed, isEmpty);

    await c.continueAfterFunds();
    expect(c.step, MoneyCallStep.review);
    final calls = server.inputs('money.prepareCall');
    expect(calls, hasLength(2));
    expect(calls[1], calls[0], reason: 'same input, same key');
  });

  test('needs gas: the top-up runs for the server\'s amount, then again', () async {
    server.on('money.prepareCall', [needsGasJson(), readyJson()]);
    final topUps = <(String, BigInt)>[];
    final c = controller(
      topUp: (wallet, amount) async => topUps.add((wallet, amount)),
    );
    await c.prepare();
    expect(topUps, [(signerWallet, BigInt.from(2000000))]);
    expect(c.step, MoneyCallStep.review);
    expect(
      server.inputs('money.prepareCall').map((i) => i['idempotencyKey']).toSet(),
      {tapKey},
    );
  });

  test('needs gas with no top-up here stops; never asks for SOL', () async {
    server.on('money.prepareCall', [needsGasJson(topUp: null)]);
    var asked = false;
    final c = controller(topUp: (_, _) async => asked = true);
    await c.prepare();
    expect(asked, isFalse);
    expect(c.step, MoneyCallStep.stopped);
    expect(c.error, isNotNull);
  });

  group('a ready quote that is not what was asked is refused unsigned', () {
    final bad = <String, Map<String, dynamic> Function()>{
      'another side': () => {
        ...readyJson(),
        'trade': preparedTradeJson(side: 'NO'),
      },
      'another owner': () => readyJson(owner: otherWallet),
      'another market': () => readyJson(market: otherWallet),
      'another amount': () => readyJson(amount: '50000000'),
      'someone else\'s wallet paying': () => {
        ...readyJson(),
        'moneyCall': moneyCallJson(wallet: otherWallet),
      },
    };
    for (final entry in bad.entries) {
      test(entry.key, () async {
        server.on('money.prepareCall', [entry.value()]);
        final c = controller();
        await c.prepare();
        expect(c.step, MoneyCallStep.stopped);
        expect(port.signed, isEmpty);
        expect(server.count('pantaTrading.submit'), 0);
      });
    }
  });

  test('a lost submit reply resends the identical bytes, never re-signs', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('pantaTrading.submit', [
        http.Response('gateway', 502),
        venueOrderJson(),
      ]);
    final c = controller();
    await c.prepare();
    await c.sign();
    expect(c.step, MoneyCallStep.sent);
    await c.resend();
    expect(c.step, MoneyCallStep.pending);
    expect(port.signed, hasLength(1));
    final sent = server.inputs('pantaTrading.submit');
    expect(sent, hasLength(2));
    expect(sent[1]['signedTransaction'], sent[0]['signedTransaction']);
  });

  test('a failed trade: retry, keep free, or discard', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('pantaTrading.submit', [venueOrderJson()])
      ..on('money.callStatus', [
        callStatusJson(
          trade: 'FAILED',
          canRetry: true,
          canKeepFree: true,
          canDiscard: true,
        ),
      ])
      ..on('money.retry', [readyJson()])
      ..on('money.keepFree', [
        {
          'moneyCall': moneyCallJson(state: 'FREE', trade: 'FAILED', canDiscard: false),
          // A NEW free call at today's price; the pending one is withdrawn.
          'call': pantaEntryJson(id: freshCallId),
        },
      ]);
    final c = controller();
    await c.prepare();
    await c.sign();
    await c.refreshStatus();
    expect(c.step, MoneyCallStep.failed);
    expect(c.moneyCall!.canKeepFree, isTrue);

    await c.retry();
    expect(c.step, MoneyCallStep.review);
    expect(server.inputs('money.retry').single, {
      'callId': moneyCallId,
      'wallet': signerWallet,
    });

    await c.keepFree();
    expect(c.step, MoneyCallStep.free);
    expect(c.call!.call.id, freshCallId);
  });

  test('keep free that answers with the old call is refused', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('money.keepFree', [
        {
          'moneyCall': moneyCallJson(state: 'FREE', canDiscard: false),
          'call': pantaEntryJson(),
        },
      ]);
    final c = controller();
    await c.prepare();
    await c.keepFree();
    expect(c.step, isNot(MoneyCallStep.free));
    expect(c.error, isNotNull);
  });

  test('keep free after the buy filled after all: funded', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('money.keepFree', [
        {
          'moneyCall': moneyCallJson(state: 'FUNDED', trade: 'FILLED', canDiscard: false),
          'call': pantaEntryJson(),
        },
      ]);
    final c = controller();
    await c.prepare();
    await c.keepFree();
    expect(c.step, MoneyCallStep.funded);
  });

  test('the price moved: no retry, only a new call', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('pantaTrading.submit', [venueOrderJson()])
      ..on('money.callStatus', [
        callStatusJson(trade: 'FAILED', canRetry: true, canDiscard: true),
      ])
      ..on('money.retry', [
        moneyError(
          'PRECONDITION_FAILED',
          'The price moved since you made this call. Make a new call.',
          reason: 'PRICE_MOVED',
        ),
      ]);
    final c = controller();
    await c.prepare();
    await c.sign();
    await c.refreshStatus();
    await c.retry();
    expect(c.retryRefused, isTrue);
    expect(c.step, MoneyCallStep.failed);
    expect(c.error, 'The price moved since you made this call. Make a new call.');
  });

  test('discard ends a pending call for good', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('money.discard', [
        {'moneyCall': moneyCallJson(state: 'EXPIRED', canDiscard: false)},
      ]);
    final c = controller();
    await c.prepare();
    await c.discard();
    expect(c.step, MoneyCallStep.discarded);
    expect(server.inputs('money.discard').single, {'callId': moneyCallId});
  });

  test('a cancelled approval sends nothing and stays on review', () async {
    server.on('money.prepareCall', [readyJson()]);
    final c = controller(signer: FakeBuyPort(cancel: true));
    await c.prepare();
    await c.sign();
    expect(c.step, MoneyCallStep.review);
    expect(c.error, contains('Nothing was signed'));
    expect(server.count('pantaTrading.submit'), 0);
  });

  test('a wallet change between review and signing is refused', () async {
    server.on('money.prepareCall', [readyJson()]);
    final c = controller();
    await c.prepare();
    selected = otherWallet;
    await c.sign();
    expect(port.signed, isEmpty);
    expect(c.step, MoneyCallStep.review);
    expect(server.count('pantaTrading.submit'), 0);
  });

  test('an expired quote at signing time is re-quoted for review', () async {
    var clock = moneyNow;
    server
      ..on('money.prepareCall', [readyJson(expiresAt: moneyNow + 60000)])
      ..on('money.retry', [readyJson(expiresAt: moneyNow + 900000)]);
    final c = MoneyCallController(
      client: server.moneyClient(),
      trading: server.tradingClient(),
      request: MoneyCallRequest(
        kind: MoneyCallKind.own,
        marketId: pantaMarketId,
        side: Side.yes,
        venueMarketId: venueMarket,
        question: 'Q',
        amountBaseUnits: BigInt.from(5000000),
      ),
      signer: MoneyBuySigner(
        address: signerWallet,
        port: port,
        selectedWallet: () => signerWallet,
      ),
      newIdempotencyKey: () => tapKey,
      now: () => DateTime.fromMillisecondsSinceEpoch(clock),
      pollEvery: const Duration(hours: 1),
    );
    addTearDown(c.dispose);
    await c.prepare();
    clock = moneyNow + 120000;
    await c.sign();
    expect(port.signed, isEmpty);
    expect(c.step, MoneyCallStep.review);
    expect(server.count('money.retry'), 1);
  });

  test('a replayed key after the call settled answers SETTLED', () async {
    server.on('money.prepareCall', [
      {
        'status': 'SETTLED',
        'moneyCall': moneyCallJson(state: 'FUNDED', trade: 'FILLED'),
        'call': pantaEntryJson(),
      },
    ]);
    final c = controller();
    await c.prepare();
    expect(c.step, MoneyCallStep.funded);
  });

  test('Tail and Fade name the call they answer, never a market or side', () async {
    server.on('money.prepareCall', [readyJson(kind: 'fade', side: 'NO')]);
    final c = controller(
      request: MoneyCallRequest(
        kind: MoneyCallKind.fade,
        targetCallId: targetCallId,
        side: Side.no,
        venueMarketId: venueMarket,
        question: 'Q',
        amountBaseUnits: BigInt.from(5000000),
      ),
    );
    await c.prepare();
    expect(c.step, MoneyCallStep.review);
    final input = server.inputs('money.prepareCall').single;
    expect(input['kind'], 'fade');
    expect(input['targetCallId'], targetCallId);
    expect(input.containsKey('marketId'), isFalse);
    expect(input.containsKey('side'), isFalse);
  });

  test('the same wording without its reason is not a price move', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('pantaTrading.submit', [venueOrderJson()])
      ..on('money.callStatus', [
        callStatusJson(trade: 'FAILED', canRetry: true, canDiscard: true),
      ])
      ..on('money.retry', [
        moneyError(
          'PRECONDITION_FAILED',
          'The price moved since you made this call. Make a new call.',
        ),
      ]);
    final c = controller();
    await c.prepare();
    await c.sign();
    await c.refreshStatus();
    await c.retry();
    expect(c.retryRefused, isFalse, reason: 'branch on reason, not words');
  });

  test('a buy already going through: retry watches it instead', () async {
    server
      ..on('money.prepareCall', [readyJson()])
      ..on('pantaTrading.submit', [venueOrderJson()])
      ..on('money.callStatus', [
        callStatusJson(trade: 'FAILED', canRetry: true, canDiscard: true),
        callStatusJson(state: 'FUNDED', trade: 'FILLED'),
      ])
      ..on('money.retry', [
        moneyError('CONFLICT', r'Your $5 is still going through.', reason: 'IN_FLIGHT'),
      ]);
    final c = controller();
    await c.prepare();
    await c.sign();
    await c.refreshStatus();
    await c.retry();
    expect(c.step, MoneyCallStep.pending);
    await c.refreshStatus();
    expect(c.step, MoneyCallStep.funded);
  });

  test('server refusals come back in its own words', () async {
    server.on('money.prepareCall', [
      moneyError('PRECONDITION_FAILED', 'This market takes free calls only.'),
    ]);
    final c = controller();
    await c.prepare();
    expect(c.step, MoneyCallStep.stopped);
    expect(c.error, 'This market takes free calls only.');
  });

  test('a pending call picked up later shows its choices', () async {
    final view = MoneyCallView.fromJson(
      moneyCallJson(trade: 'FAILED', canRetry: true, canKeepFree: true),
    );
    final c = MoneyCallController.resume(
      client: server.moneyClient(),
      trading: server.tradingClient(),
      moneyCall: view,
      call: (MoneyPrepareResult.fromJson(readyJson()) as MoneyReady).call,
      signer: MoneyBuySigner(
        address: signerWallet,
        port: port,
        selectedWallet: () => signerWallet,
      ),
      pollEvery: const Duration(hours: 1),
    );
    addTearDown(c.dispose);
    expect(c.step, MoneyCallStep.failed);
    expect(c.request.amountBaseUnits, BigInt.from(5000000));
  });
}
