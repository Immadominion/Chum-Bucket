/// A USDC transfer is sent once: a lost reply resends the same bytes and
/// keeps the sheet; a second transfer while one is in flight watches that
/// one; a key replayed after signing answers its state, never a new review.
/// The silent gas top-up is capped and refuses a bad rate before signing.
///
/// These run the REAL transfer check (`checkUsdcTransfer`) on real v0
/// transactions laid out as contract (c) builds them.
library;

import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/money/data/money_models.dart';
import 'package:chumbucket/features/money/domain/money_gas.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/money/domain/money_transfer_signer.dart';
import 'package:chumbucket/features/money/domain/usdc_transfer_check.dart';
import 'package:chumbucket/features/money/presentation/money_dependencies.dart'
    show moneyTransferSignerFor;
import 'package:chumbucket/features/money/money_transfer_controller.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart';
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fixtures/jupiter_gasless_fixtures.dart';
import 'money_fakes.dart';
import 'sol_topup_fakes.dart';

Map<String, dynamic> _view({String state = 'BUILT', String? id}) => {
  'transferId': id ?? transferId,
  'kind': 'cash_out',
  'from': signerWallet,
  'to': otherWallet,
  'amountBaseUnits': '5000000',
  'state': state,
  'signature': state == 'SUBMITTED' || state == 'CONFIRMED' ? fillSignature : null,
  'createdAt': moneyNow,
  'updatedAt': moneyNow,
  'expiresAt': farFuture,
};

/// A real cash out of $5 from [signerWallet] to [otherWallet].
late String realPayload;

Map<String, dynamic> _ready({String? payload}) => {
  'status': 'READY',
  'transfer': _view(),
  'transaction': {
    'encoding': 'solana-tx-base64',
    'payload': payload ?? realPayload,
    'expiresAt': farFuture,
  },
  'review': {
    'from': signerWallet,
    'to': otherWallet,
    'amountBaseUnits': '5000000',
    'createsAccount': false,
    'networkFeeLamports': '5000',
    'rentLamports': '0',
  },
};

http.Response _inFlight(String id) => http.Response(
  jsonEncode({
    'error': {
      'json': {
        'message':
            'Another transfer from this wallet is still going through. Try again when it\'s done.',
        'code': -32600,
        'data': {
          'code': 'CONFLICT',
          'httpStatus': 409,
          'details': {'reason': 'TRANSFER_IN_FLIGHT', 'transferId': id},
        },
      },
    },
  }),
  409,
);

void main() {
  late FakeMoneyServer server;
  late int signs;
  var keys = 0;

  setUpAll(() async {
    realPayload = await transferPayload(from: signerWallet, to: otherWallet);
  });

  setUp(() {
    server = FakeMoneyServer();
    signs = 0;
  });

  var clock = moneyNow;
  MoneyTransferController controller({
    Future<Uint8List> Function()? answer,
    MoneyGasTopUp? topUp,
    Duration approvalTimeout = const Duration(minutes: 2),
  }) {
    final c = MoneyTransferController(
      client: server.moneyClient(),
      kind: MoneyTransferKind.cashOut,
      // The real check (the signer's default), before any signature.
      signerFor:
          (wallet) => MoneyTransferSigner(
            address: wallet,
            sign: (_, _) async {
              signs++;
              return answer == null
                  ? Uint8List.fromList(List.filled(64, 4))
                  : answer();
            },
          ),
      topUp: topUp,
      newIdempotencyKey: () => 'transfer-key-${(++keys).toString().padLeft(8, '0')}',
      now: () => DateTime.fromMillisecondsSinceEpoch(clock),
      pollEvery: const Duration(hours: 1),
      approvalTimeout: approvalTimeout,
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> prepare(MoneyTransferController c) => c.prepare(
    from: signerWallet,
    to: otherWallet,
    amountBaseUnits: BigInt.from(5000000),
  );

  test('a lost reply: the same bytes again, the sheet stays, no new transfer', () async {
    server
      ..on('money.cashOutPrepare', [_ready()])
      ..on('money.transferSubmit', [
        http.Response('gateway', 502),
        _view(state: 'SUBMITTED'),
      ])
      ..on('money.transferStatus', [_view(state: 'CONFIRMED')]);
    final c = controller();
    await prepare(c);
    await c.sign();
    expect(c.step, MoneyTransferStep.sent);
    expect(c.canDismiss, isFalse, reason: 'closing would drop the only copy');

    // Asking for a new one while this one's outcome is unknown: nothing new.
    await prepare(c);
    expect(server.count('money.cashOutPrepare'), 1);

    await c.resend();
    expect(c.step, MoneyTransferStep.confirming);
    expect(signs, 1);
    final sent = server.inputs('money.transferSubmit');
    expect(sent[1]['signedTransaction'], sent[0]['signedTransaction']);

    await c.refreshStatus();
    expect(c.step, MoneyTransferStep.confirmed);
  });

  test('another transfer in flight: watch the one the server names', () async {
    const flying = '99999999-9999-4999-8999-999999999999';
    server
      ..on('money.cashOutPrepare', [_inFlight(flying)])
      ..on('money.transferStatus', [_view(state: 'SUBMITTED', id: flying)]);
    final c = controller();
    await prepare(c);
    expect(server.inputs('money.transferStatus').single, {'transferId': flying});
    expect(c.step, MoneyTransferStep.confirming);
    expect(c.transfer!.transferId, flying);
    expect(signs, 0);
  });

  test('a key replayed after signing answers its state, never a review', () async {
    server.on('money.cashOutPrepare', [
      {'status': 'SENT', 'transfer': _view(state: 'SUBMITTED')},
    ]);
    final c = controller();
    await prepare(c);
    expect(c.step, MoneyTransferStep.confirming);
    expect(c.ready, isNull);
    expect(signs, 0);
  });

  test('a refused or expired review starts again with a new key', () async {
    server.on('money.cashOutPrepare', [
      {'status': 'INVALID', 'reason': 'ADDRESS', 'message': 'Check the address.'},
      _ready(),
    ]);
    final c = controller();
    await prepare(c);
    expect(c.error, 'Check the address.');
    await prepare(c);
    final keysSent = server
        .inputs('money.cashOutPrepare')
        .map((i) => i['idempotencyKey'])
        .toSet();
    expect(keysSent, hasLength(2));
  });

  test('a lost prepare reply asks again under the same key', () async {
    server.on('money.cashOutPrepare', [http.Response('gateway', 502), _ready()]);
    final c = controller();
    await prepare(c);
    expect(c.step, MoneyTransferStep.idle);
    await prepare(c);
    final keysSent = server
        .inputs('money.cashOutPrepare')
        .map((i) => i['idempotencyKey'])
        .toSet();
    expect(keysSent, hasLength(1));
    expect(c.step, MoneyTransferStep.review);
  });

  test('a review that expired before the submit: drop the bytes, start again', () async {
    server
      ..on('money.cashOutPrepare', [_ready()])
      ..on('money.transferSubmit', [
        moneyError(
          'PRECONDITION_FAILED',
          'This review expired. Nothing was sent. Start again.',
          reason: 'REVIEW_EXPIRED',
        ),
      ]);
    final c = controller();
    await prepare(c);
    await c.sign();
    expect(c.step, MoneyTransferStep.idle);
    expect(c.canDismiss, isTrue);
    expect(c.error, 'This review expired. Nothing was sent. Start again.');
    server.on('money.cashOutPrepare', [_ready()]);
    await prepare(c);
    expect(c.step, MoneyTransferStep.review);
    final keysSent = server
        .inputs('money.cashOutPrepare')
        .map((i) => i['idempotencyKey'])
        .toSet();
    expect(keysSent, hasLength(2));
  });

  test('the real check signs the reviewed transfer, slot only', () async {
    server
      ..on('money.cashOutPrepare', [_ready()])
      ..on('money.transferSubmit', [_view(state: 'SUBMITTED')]);
    final c = controller();
    await prepare(c);
    await c.sign();
    expect(signs, 1);
    final sent = base64Decode(
      server.inputs('money.transferSubmit').single['signedTransaction'] as String,
    );
    expect(sent.sublist(65), base64Decode(realPayload).sublist(65));
    expect(c.step, MoneyTransferStep.confirming);
  });

  test('the real check refuses bytes paying someone else, unsigned', () async {
    final elsewhere = await transferPayload(
      from: signerWallet,
      to: otherWallet,
      destinationOverride: venueMarket,
    );
    server.on('money.cashOutPrepare', [_ready(payload: elsewhere)]);
    final c = controller();
    await prepare(c);
    await c.sign();
    expect(signs, 0);
    expect(server.count('money.transferSubmit'), 0);
    expect(c.error, contains('didn’t match'));
  });

  test('the real check refuses a different amount than asked', () async {
    final more = await transferPayload(
      from: signerWallet,
      to: otherWallet,
      amount: 50000000,
    );
    server.on('money.cashOutPrepare', [_ready(payload: more)]);
    final c = controller();
    await prepare(c);
    await c.sign();
    expect(signs, 0);
    expect(server.count('money.transferSubmit'), 0);
  });

  test('gas is only topped up on the wallet that pays', () async {
    server.on('money.cashOutPrepare', [
      {
        'status': 'NEEDS_GAS',
        'wallet': {'address': otherWallet, 'walletType': 'mwa'},
        'topUp': {'amountBaseUnits': '2000000'},
      },
    ]);
    var topUps = 0;
    final c = controller(topUp: (_, _) async => topUps++);
    await prepare(c);
    expect(topUps, 0);
    expect(c.step, MoneyTransferStep.idle);
    expect(c.error, isNotNull);
  });

  test('an unsigned review in the way: nothing was sent, a new one after it', () async {
    const flying = '99999999-9999-4999-8999-999999999999';
    server
      ..on('money.cashOutPrepare', [_inFlight(flying)])
      ..on('money.transferStatus', [
        {..._view(id: flying), 'expiresAt': moneyNow + 60000},
      ]);
    final c = controller();
    await prepare(c);
    expect(c.step, MoneyTransferStep.idle);
    expect(c.error, 'Nothing was sent.');
    expect(c.canDismiss, isTrue);

    // Before its time is up: not yet.
    await prepare(c);
    expect(server.count('money.cashOutPrepare'), 1);
    expect(c.error, contains('Nothing was sent'));

    // After: a new review.
    clock = moneyNow + 61000;
    server.on('money.cashOutPrepare', [_ready()]);
    await prepare(c);
    expect(c.step, MoneyTransferStep.review);
    clock = moneyNow;
  });

  test('a wallet that never answers: back to review, the sheet free', () async {
    server.on('money.cashOutPrepare', [_ready()]);
    final never = Completer<Uint8List>();
    final c = controller(
      answer: () => never.future,
      approvalTimeout: const Duration(milliseconds: 50),
    );
    await prepare(c);
    await c.sign();
    expect(c.step, MoneyTransferStep.review);
    expect(c.canDismiss, isTrue);
    expect(server.count('money.transferSubmit'), 0);
  });

  test('production wiring signs transfers behind the real check', () {
    final app = moneyTransferSignerFor(
      wallet: signerWallet,
      walletApp: _WalletApp(signerWallet),
    );
    expect(app, isNotNull);
    expect(identical(app!.check, checkUsdcTransfer), isTrue);
    expect(
      identical(
        MoneyTransferSigner(address: signerWallet, sign: (_, _) async => Uint8List(64)).check,
        checkUsdcTransfer,
      ),
      isTrue,
    );
  });

  group('the silent gas top-up', () {
    late FakeTopUpBff bff;
    setUp(() => bff = FakeTopUpBff());

    SolTopUpSigner signer() => _CountingSigner(kSwapOwner);

    test('above \$25 it is refused before anything is asked', () async {
      await expectLater(
        runGasTopUp(
          client: bff.newClient(),
          signer: signer(),
          wallet: kSwapOwner,
          amountBaseUnits: BigInt.from(25000001),
        ),
        throwsA(isA<MoneyException>()),
      );
      expect(bff.calls, isEmpty);
    });

    test('a rate below the floor is refused unsigned', () async {
      final s = _CountingSigner(kSwapOwner);
      await expectLater(
        runGasTopUp(
          client: bff.newClient(),
          signer: s,
          wallet: kSwapOwner,
          amountBaseUnits: BigInt.from(kMetisInAmount),
          // What the transaction guarantees: far too little SOL per dollar.
          check: (bytes, expected) async => CheckedSwap(
            router: SwapRouter.metis,
            feePayer: jupiterGasWallet,
            ownerSignatureIndex: 1,
            inAmount: expected.inAmount,
            minOutLamports: BigInt.from(1000),
            expectedOutLamports: BigInt.from(1000),
            feeBps: kMetisFeeBps,
            slippageBps: 50,
            messageBytes: Uint8List(1),
          ),
        ),
        throwsA(isA<MoneyException>()),
      );
      expect(s.count, 0);
      expect(bff.inputs('execute'), isEmpty);
    });
  });
}

class _CountingSigner implements SolTopUpSigner {
  _CountingSigner(this.address);
  @override
  final String address;
  int count = 0;
  @override
  TopUpSignerKind get kind => TopUpSignerKind.thisPhone;
  @override
  Future<Uint8List> sign(Uint8List unsigned, CheckedSwap checked) async {
    count++;
    return unsigned;
  }
}

class _WalletApp extends MwaAuthProvider {
  _WalletApp(this.wallet);
  final String? wallet;
  @override
  bool get isAuthenticated => wallet != null;
  @override
  String? get walletAddress => wallet;
}
