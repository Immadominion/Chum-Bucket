/// A USDC transfer is sent once: a lost reply resends the same bytes and
/// keeps the sheet; a second transfer while one is in flight watches that
/// one; a key replayed after signing answers its state, never a new review.
/// The silent gas top-up is capped and refuses a bad rate before signing.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/money/data/money_models.dart';
import 'package:chumbucket/features/money/domain/money_gas.dart';
import 'package:chumbucket/features/money/domain/money_transfer_signer.dart';
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

Map<String, dynamic> _ready() => {
  'status': 'READY',
  'transfer': _view(),
  'transaction': {
    'encoding': 'solana-tx-base64',
    'payload': base64Encode(moneyUnsigned()),
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

  setUp(() {
    server = FakeMoneyServer();
    signs = 0;
  });

  MoneyTransferController controller() {
    final c = MoneyTransferController(
      client: server.moneyClient(),
      kind: MoneyTransferKind.cashOut,
      signerFor:
          (wallet) => MoneyTransferSigner(
            address: wallet,
            check: (bytes, _) async => Uint8List.fromList(bytes.sublist(65)),
            sign: (_, _) async {
              signs++;
              return Uint8List.fromList(List.filled(64, 4));
            },
          ),
      newIdempotencyKey: () => 'transfer-key-${(++keys).toString().padLeft(8, '0')}',
      pollEvery: const Duration(hours: 1),
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
