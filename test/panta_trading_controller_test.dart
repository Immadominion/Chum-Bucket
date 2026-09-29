import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana/base58.dart';

// Synthetic wire-layout fixtures only. The nonzero signature slots below are
// NOT cryptographic signatures, approved wallets, network traffic, or trades.
const syntheticTime = 1790686800000;
const syntheticKey = '11111111-1111-4111-8111-111111111111';
const syntheticMarket = '22222222-2222-4222-8222-222222222222';
const syntheticCall = '33333333-3333-4333-8333-333333333333';
final syntheticWalletAddress = base58encode(List.filled(32, 1));
final syntheticVenueMarket = base58encode(List.filled(32, 8));
final syntheticFillSignature = base58encode(List.filled(64, 9));

Uint8List syntheticUnsigned({
  int ownerByte = 1,
  int instructionByte = 7,
  bool withLookup = false,
}) => Uint8List.fromList([
  1, ...List.filled(64, 0), // signature vector and placeholder
  128, 1, 0, 1, // native v0 prefix and header
  2, ...List.filled(32, ownerByte), ...List.filled(32, 2), // static keys
  ...List.filled(32, 3), // blockhash
  1, 1, withLookup ? 3 : 1, 0,
  if (withLookup) ...[2, 3],
  1, instructionByte, // instruction data
  if (withLookup) ...[1, ...List.filled(32, 4), 1, 9, 1, 10] else 0,
]);

Uint8List syntheticSigned(Uint8List unsigned) =>
    Uint8List.fromList(unsigned)..fillRange(1, 65, 5);

Map<String, Object?> syntheticPrepareJson({
  Map<String, dynamic>? input,
  int now = syntheticTime,
  Uint8List? bytes,
}) => {
  'order': {
    'orderId': 'synthetic-order',
    'venue': 'panta',
    'venueMarketId': syntheticVenueMarket,
    'owner': syntheticWalletAddress,
    'side': 'YES',
    'amountBaseUnits': input?['amountBaseUnits'] ?? '10000000',
    'quotedProbability': null,
    'fundingState': 'QUOTED',
    'transaction': <String, Object?>{
      'venue': 'panta',
      'encoding': 'solana-tx-base64',
      'payload': base64Encode(bytes ?? syntheticUnsigned()),
      'expiresAt': now + 60000,
      'demo': false,
    },
    'idempotencyKey': input?['idempotencyKey'] ?? syntheticKey,
    'createdAt': now,
    'expiresAt': now + 60000,
    'demo': false,
  },
  'review': {
    'amountUsdc':
        input == null ? '10' : _usdc(input['amountBaseUnits'] as String),
    'amountBaseUnits': input?['amountBaseUnits'] ?? '10000000',
    'expectedShares': '7.920792079207920792',
    'avgPrice': '1.250000000000000001',
    'feeUsdc': '0.1',
    'maxSlippageBps': 100,
    'attribution': 'Powered by Panta',
  },
};

String _usdc(String units) =>
    '${BigInt.parse(units) ~/ BigInt.from(1000000)}.'
    '${(BigInt.parse(units) % BigInt.from(1000000)).toString().padLeft(6, '0')}';

Map<String, Object?> syntheticOrderJson({
  String state = 'SUBMITTED',
  String amount = '10000000',
  String key = syntheticKey,
  int updatedAt = syntheticTime + 1000,
}) => {
  'orderId': 'synthetic-order',
  'venueOrderId': 'synthetic-venue-order',
  'venue': 'panta',
  'venueMarketId': syntheticVenueMarket,
  'owner': syntheticWalletAddress,
  'side': 'YES',
  'amountBaseUnits': amount,
  'filledBaseUnits':
      state == 'FILLED'
          ? amount
          : state == 'PARTIAL'
          ? '5000000'
          : '0',
  'fundingState': state,
  'fillTxSignature': state == 'FILLED' ? syntheticFillSignature : null,
  'createdAt': syntheticTime,
  'updatedAt': updatedAt,
  'idempotencyKey': key,
  'demo': false,
};

http.Response syntheticWire(Object? data) => http.Response(
  jsonEncode({
    'result': {
      'data': {'json': data},
    },
  }),
  200,
);
Map<String, dynamic> syntheticInput(http.Request request) =>
    (jsonDecode(request.body) as Map<String, dynamic>)['json']
        as Map<String, dynamic>;

class SyntheticWallet implements PantaWalletPort {
  int signCount = 0;
  FutureOr<Uint8List> Function(Uint8List)? reply;
  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    signCount++;
    return reply == null ? syntheticSigned(unsigned) : await reply!(unsigned);
  }
}

class SyntheticPantaRig {
  SyntheticPantaRig({Duration timeout = const Duration(seconds: 2)}) {
    transport = MockClient((request) async {
      requests.add(request);
      final intercepted = await intercept?.call(request);
      if (intercepted != null) return intercepted;
      switch (request.url.path.split('/').last) {
        case 'pantaTrading.status':
          return syntheticWire({
            'enabled': enabled,
            'reason': statusReason,
            'venue': 'panta',
            'attribution': 'Powered by Panta',
          });
        case 'pantaTrading.prepare':
          return syntheticWire(
            syntheticPrepareJson(
              input: syntheticInput(request),
              now: now.millisecondsSinceEpoch,
            ),
          );
        case 'pantaTrading.forCall':
          return syntheticWire({'order': recoveredOrder});
        case 'pantaTrading.submit':
        case 'pantaTrading.order':
          if (inputs('prepare').isEmpty && recoveredOrder != null) {
            return syntheticWire({
              ...recoveredOrder!,
              ...syntheticOrderJson(
                state: serverState,
                amount: recoveredOrder!['amountBaseUnits'] as String,
                key: recoveredOrder!['idempotencyKey'] as String,
                updatedAt: now.millisecondsSinceEpoch + 1000,
              ),
            });
          }
          final prepared = inputs('prepare').last;
          return syntheticWire(
            syntheticOrderJson(
              state: serverState,
              amount: prepared['amountBaseUnits'] as String,
              key: prepared['idempotencyKey'] as String,
              updatedAt: now.millisecondsSinceEpoch + 1000,
            ),
          );
        default:
          throw StateError('Unexpected procedure in synthetic transport.');
      }
    });
    client = PantaTradingClient(
      baseUri: Uri.parse('https://bff.invalid/trpc/'),
      session: () => session,
      client: transport,
      timeout: timeout,
    );
    controller = PantaTradeController(
      callId: syntheticCall,
      marketId: syntheticMarket,
      venueMarketId: syntheticVenueMarket,
      side: Side.yes,
      wallet: syntheticWalletAddress,
      client: client,
      walletPort: wallet,
      selectedWallet: () => selectedWallet,
      now: () => now,
      newIdempotencyKey: () {
        keysGenerated++;
        return '${keysGenerated.toString().padLeft(8, '0')}-1111-4111-8111-111111111111';
      },
    );
  }
  late final MockClient transport;
  late final PantaTradingClient client;
  late final PantaTradeController controller;
  final wallet = SyntheticWallet();
  final requests = <http.Request>[];
  FutureOr<http.Response?> Function(http.Request)? intercept;
  PantaSession? session = const PantaSession(
    accountId: 'existing-account',
    accessToken: 'synthetic-bearer',
  );
  String? selectedWallet = syntheticWalletAddress;
  DateTime now = DateTime.fromMillisecondsSinceEpoch(syntheticTime);
  bool enabled = true;
  String? statusReason;
  String serverState = 'SUBMITTED';
  Map<String, Object?>? recoveredOrder;
  int keysGenerated = 0;
  bool controllerDisposed = false;

  List<http.Request> procedure(String suffix) =>
      requests
          .where((request) => request.url.path.endsWith('pantaTrading.$suffix'))
          .toList();
  List<Map<String, dynamic>> inputs(String suffix) =>
      procedure(suffix).map(syntheticInput).toList();
  Future<void> review() async {
    controller.editAmount('10');
    await controller.prepare();
    expect(controller.phase, PantaTradePhase.review);
  }

  void disposeController() {
    if (!controllerDisposed) {
      controllerDisposed = true;
      controller.dispose();
    }
  }

  void close() {
    disposeController();
    client.close();
    transport.close();
  }
}

void main() {
  late SyntheticPantaRig r;
  setUp(() => r = SyntheticPantaRig());
  tearDown(() => r.close());

  test('prepare shows review without any wallet approval or submit', () async {
    await r.review();
    expect(r.wallet.signCount, 0);
    expect(r.procedure('submit'), isEmpty);
    expect(r.controller.isFunded, isFalse);
    expect(r.inputs('prepare').single, {
      'callId': syntheticCall,
      'wallet': syntheticWalletAddress,
      'amountBaseUnits': '10000000',
      'idempotencyKey': '00000001-1111-4111-8111-111111111111',
      'maxSlippageBps': 100,
    });
  });

  for (final state in ['SUBMITTED', 'FILLED']) {
    for (final loadStatus in [true, false]) {
      test(
        'cold $state recovery via ${loadStatus ? 'status' : 'prepare'} prevents a new buy',
        () async {
          r.recoveredOrder = syntheticOrderJson(state: state);
          if (loadStatus) {
            await r.controller.loadStatus();
          } else {
            r.controller.editAmount('10');
            await r.controller.prepare();
          }
          expect(r.controller.error, isNull);
          expect(r.controller.phase, PantaTradePhase.order);
          expect(r.controller.prepared, isNull);
          expect(r.controller.order!.orderId, 'synthetic-order');
          expect(r.controller.isFunded, state == 'FILLED');
          expect(r.controller.canCheckOrder, isTrue);
          expect(r.controller.canRetrySigned, isFalse);
          expect(r.controller.canCancel, isFalse);
          r.controller.editAmount('20');
          await r.controller.prepare();
          await r.controller.approveReview();
          await r.controller.retrySignedSubmit();
          expect(r.keysGenerated, 0);
          expect(r.wallet.signCount, 0);
          expect(r.procedure('prepare'), isEmpty);
          expect(r.procedure('submit'), isEmpty);
          r.serverState = 'FILLED';
          await r.controller.refreshOrder();
          expect(r.controller.error, isNull);
          expect(r.controller.isFunded, isTrue);
          expect(r.inputs('order').single, {'orderId': 'synthetic-order'});
        },
      );
    }
  }

  for (final patch in <Map<String, Object?>>[
    {'owner': base58encode(List.filled(32, 2))},
    {'venueMarketId': base58encode(List.filled(32, 5))},
    {'side': 'NO'},
    {'venue': 'fixture'},
    {'demo': true},
    {'fundingState': 'QUOTED'},
    {'fundingState': 'FAILED'},
  ]) {
    test(
      'foreign recovered ${patch.keys.first}/${patch.values.first} blocks prepare',
      () async {
        r.recoveredOrder = {...syntheticOrderJson(), ...patch};
        await r.controller.loadStatus();
        expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
        expect(r.controller.order, isNull);
        r.controller.editAmount('10');
        await r.controller.prepare();
        expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
        expect(r.keysGenerated, 0);
        expect(r.wallet.signCount, 0);
        expect(r.procedure('prepare'), isEmpty);
      },
    );
  }

  test(
    'failed recovery lookup blocks a fresh prepare without generating a UUID',
    () async {
      r.intercept = (request) {
        if (request.url.path.endsWith('.forCall')) {
          throw http.ClientException('lost lookup');
        }
        return null;
      };
      r.controller.editAmount('10');
      await r.controller.prepare();
      expect(r.controller.error!.code, PantaErrorCode.connection);
      expect(r.keysGenerated, 0);
      expect(r.wallet.signCount, 0);
      expect(r.procedure('prepare'), isEmpty);
      r.intercept = null;
      await r.controller.prepare();
      expect(r.controller.phase, PantaTradePhase.review);
      expect(r.keysGenerated, 1);
    },
  );

  test(
    'signed-out status remains public and cannot recover private orders',
    () async {
      r.session = null;
      await r.controller.loadStatus();
      expect(r.controller.status!.enabled, isTrue);
      expect(r.controller.error, isNull);
      expect(r.procedure('forCall'), isEmpty);
    },
  );

  test(
    'canonical account change during recovery never adopts returned order',
    () async {
      r.recoveredOrder = syntheticOrderJson();
      r.intercept = (request) {
        if (request.url.path.endsWith('.forCall')) {
          r.session = const PantaSession(
            accountId: 'another-account',
            accessToken: 'other-bearer',
          );
        }
        return null;
      };
      await r.controller.loadStatus();
      expect(r.controller.error!.code, PantaErrorCode.sessionChanged);
      expect(r.controller.order, isNull);
      expect(r.controller.isFunded, isFalse);
    },
  );

  test(
    'recovered order refresh retains captured account and rejects foreign order IDs',
    () async {
      r.recoveredOrder = syntheticOrderJson();
      await r.controller.loadStatus();
      r.session = const PantaSession(
        accountId: 'another-account',
        accessToken: 'other-bearer',
      );
      await r.controller.refreshOrder();
      expect(r.controller.error!.code, PantaErrorCode.sessionChanged);
      expect(r.procedure('order'), isEmpty);
      r.session = const PantaSession(
        accountId: 'existing-account',
        accessToken: 'refreshed-bearer',
      );
      r.intercept = (request) {
        if (request.url.path.endsWith('.order')) {
          return syntheticWire({
            ...syntheticOrderJson(state: 'FILLED'),
            'orderId': 'foreign-order',
          });
        }
        return null;
      };
      await r.controller.refreshOrder();
      expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
      expect(r.controller.isFunded, isFalse);
      expect(r.controller.order!.orderId, 'synthetic-order');
    },
  );

  test('disabled status makes no authenticated prepare/sign request', () async {
    r.enabled = false;
    r.statusReason = 'untrusted provider detail';
    r.controller.editAmount('10');
    await r.controller.prepare();
    expect(r.controller.error!.code, PantaErrorCode.unavailable);
    expect(r.controller.error!.message, isNot(contains(r.statusReason)));
    expect(r.procedure('prepare'), isEmpty);
    expect(r.wallet.signCount, 0);
  });

  test('signed-out session cannot prepare', () async {
    r.session = null;
    r.controller.editAmount('10');
    await r.controller.prepare();
    expect(r.controller.error!.code, PantaErrorCode.signedOut);
    expect(r.procedure('prepare'), isEmpty);
  });

  test('dropped prepare retries retain exactly one UUID', () async {
    var drop = true;
    r.intercept = (request) {
      if (request.url.path.endsWith('.prepare') && drop) {
        drop = false;
        throw http.ClientException('untrusted provider detail');
      }
      return null;
    };
    r.controller.editAmount('10');
    await r.controller.prepare();
    expect(r.controller.error!.code, PantaErrorCode.connection);
    await r.controller.prepare();
    expect(r.controller.phase, PantaTradePhase.review);
    expect(r.keysGenerated, 1);
    expect(r.inputs('prepare')[0], r.inputs('prepare')[1]);
  });

  test('explicit edit and cancellation create new intents', () async {
    await r.review();
    r.controller.editAmount('11');
    await r.controller.prepare();
    expect(r.keysGenerated, 2);
    expect(r.inputs('prepare').last['amountBaseUnits'], '11000000');
    expect(r.controller.cancel(), isTrue);
    r.controller.editAmount('12');
    await r.controller.prepare();
    expect(r.keysGenerated, 3);
    expect(r.wallet.signCount, 0);
  });

  test('repeated prepare taps have one in-flight request', () async {
    final reached = Completer<void>();
    final reply = Completer<http.Response>();
    r.intercept = (request) {
      if (request.url.path.endsWith('.prepare')) {
        reached.complete();
        return reply.future;
      }
      return null;
    };
    r.controller.editAmount('10');
    final first = r.controller.prepare();
    await reached.future;
    await r.controller.prepare();
    reply.complete(
      syntheticWire(syntheticPrepareJson(input: r.inputs('prepare').single)),
    );
    await first;
    expect(r.procedure('prepare'), hasLength(1));
  });

  for (final patch in <Map<String, Object?>>[
    {'owner': base58encode(List.filled(32, 2))},
    {'side': 'NO'},
    {'venueMarketId': base58encode(List.filled(32, 4))},
    {'idempotencyKey': syntheticKey},
    {'amountBaseUnits': '12000000'},
    {'demo': true},
    {'venue': 'fixture'},
    {'fundingState': 'FILLED'},
  ]) {
    test('quote binding rejects ${patch.keys.first}', () async {
      r.intercept = (request) {
        if (!request.url.path.endsWith('.prepare')) return null;
        final json = syntheticPrepareJson(input: syntheticInput(request));
        (json['order'] as Map).addAll(patch);
        return syntheticWire(json);
      };
      r.controller.editAmount('10');
      await r.controller.prepare();
      expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
      expect(r.wallet.signCount, 0);
      expect(r.controller.isFunded, isFalse);
    });
  }

  for (final accountChanged in [true, false]) {
    test(
      '${accountChanged ? 'account' : 'wallet'} recheck before sign',
      () async {
        await r.review();
        if (accountChanged) {
          r.session = const PantaSession(
            accountId: 'other-account',
            accessToken: 'another-bearer',
          );
        } else {
          r.selectedWallet = base58encode(List.filled(32, 2));
        }
        await r.controller.approveReview();
        expect(
          r.controller.error!.code,
          accountChanged
              ? PantaErrorCode.sessionChanged
              : PantaErrorCode.walletChanged,
        );
        expect(r.wallet.signCount, 0);
        expect(r.procedure('submit'), isEmpty);
      },
    );

    test(
      '${accountChanged ? 'account' : 'wallet'} recheck after wallet returns',
      () async {
        await r.review();
        r.wallet.reply = (unsigned) {
          if (accountChanged) {
            r.session = const PantaSession(
              accountId: 'other-account',
              accessToken: 'another-bearer',
            );
          } else {
            r.selectedWallet = base58encode(List.filled(32, 2));
          }
          return syntheticSigned(unsigned);
        };
        await r.controller.approveReview();
        expect(
          r.controller.error!.code,
          accountChanged
              ? PantaErrorCode.sessionChanged
              : PantaErrorCode.walletChanged,
        );
        expect(r.procedure('submit'), isEmpty);
        expect(r.controller.isFunded, isFalse);
      },
    );
  }

  test('same canonical account may refresh its bearer token', () async {
    await r.review();
    r.session = const PantaSession(
      accountId: 'existing-account',
      accessToken: 'refreshed-bearer',
    );
    await r.controller.approveReview();
    expect(
      r.procedure('submit').single.headers['authorization'],
      'Bearer refreshed-bearer',
    );
    expect(r.controller.phase, PantaTradePhase.order);
    expect(r.controller.isFunded, isFalse);
  });

  test('wallet decline cancels locally and never submits', () async {
    await r.review();
    r.wallet.reply = (_) => throw const PantaWalletCancelled();
    await r.controller.approveReview();
    expect(r.controller.phase, PantaTradePhase.cancelled);
    expect(r.controller.error!.code, PantaErrorCode.walletCancelled);
    expect(r.procedure('submit'), isEmpty);
    expect(r.controller.isFunded, isFalse);
  });

  test('cancellation invalidates a late wallet callback', () async {
    await r.review();
    final reached = Completer<Uint8List>();
    final reply = Completer<Uint8List>();
    r.wallet.reply = (unsigned) {
      reached.complete(unsigned);
      return reply.future;
    };
    final first = r.controller.approveReview();
    final bytes = await reached.future;
    await r.controller.approveReview();
    expect(r.wallet.signCount, 1);
    expect(r.controller.cancel(), isTrue);
    reply.complete(syntheticSigned(bytes));
    await first;
    expect(r.controller.phase, PantaTradePhase.cancelled);
    expect(r.procedure('submit'), isEmpty);
    expect(r.controller.isFunded, isFalse);
  });

  test(
    'disposal invalidates pending wallet callbacks and sends no submit',
    () async {
      await r.review();
      final reached = Completer<Uint8List>();
      final reply = Completer<Uint8List>();
      r.wallet.reply = (unsigned) {
        reached.complete(unsigned);
        return reply.future;
      };
      final pending = r.controller.approveReview();
      final bytes = await reached.future;
      r.disposeController();
      reply.complete(syntheticSigned(bytes));
      await pending;
      expect(r.procedure('submit'), isEmpty);
    },
  );

  test(
    'expired quote requires explicit cancellation and fresh review',
    () async {
      await r.review();
      final oldExpiry = r.controller.prepared!.order.expiresAt;
      r.now = r.now.add(const Duration(seconds: 61));
      await r.controller.approveReview();
      expect(r.wallet.signCount, 0);
      expect(r.procedure('submit'), isEmpty);
      expect(r.controller.phase, PantaTradePhase.review);
      expect(r.controller.error!.code, PantaErrorCode.expired);
      expect(r.controller.prepared!.order.expiresAt, oldExpiry);
      expect(r.keysGenerated, 1);
      expect(r.procedure('prepare'), hasLength(1));
      expect(r.controller.cancel(), isTrue);
      r.controller.editAmount('10');
      await r.controller.prepare();
      expect(r.controller.prepared!.order.expiresAt, greaterThan(oldExpiry));
      expect(r.keysGenerated, 2);
      expect(r.wallet.signCount, 0);
    },
  );

  test(
    'expiry during wallet approval requires a fresh intent without submit',
    () async {
      await r.review();
      r.wallet.reply = (unsigned) {
        r.now = r.now.add(const Duration(seconds: 61));
        return syntheticSigned(unsigned);
      };
      await r.controller.approveReview();
      expect(r.controller.phase, PantaTradePhase.review);
      expect(r.controller.error!.code, PantaErrorCode.expired);
      expect(r.wallet.signCount, 1);
      expect(r.keysGenerated, 1);
      expect(r.procedure('prepare'), hasLength(1));
      expect(r.procedure('submit'), isEmpty);
    },
  );

  test('changed message or untouched signature slots never submit', () async {
    await r.review();
    r.wallet.reply = (unsigned) {
      unsigned[unsigned.length - 2] = 99;
      return syntheticSigned(unsigned);
    };
    await r.controller.approveReview();
    expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
    expect(r.procedure('submit'), isEmpty);
    r.wallet.reply = (unsigned) => unsigned;
    await r.controller.approveReview();
    expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
    expect(r.procedure('submit'), isEmpty);
  });

  test('SDK exception detail is replaced by fixed local copy', () async {
    await r.review();
    r.wallet.reply =
        (_) => throw StateError('provider detail synthetic-bearer');
    await r.controller.approveReview();
    expect(r.controller.error!.code, PantaErrorCode.signingFailed);
    expect(r.controller.error.toString(), isNot(contains('synthetic-bearer')));
    expect(r.procedure('submit'), isEmpty);
  });

  test(
    'dropped submit retries exact signed bytes past expiry without resigning',
    () async {
      await r.review();
      var drop = true;
      r.intercept = (request) {
        if (request.url.path.endsWith('.submit') && drop) {
          drop = false;
          throw http.ClientException('dropped reply');
        }
        return null;
      };
      await r.controller.approveReview();
      expect(r.controller.phase, PantaTradePhase.signed);
      expect(r.controller.canCancel, isFalse);
      expect(r.controller.cancel(), isFalse);
      expect(r.controller.canEditAmount, isFalse);
      r.controller.editAmount('20');
      await r.controller.prepare();
      r.now = r.now.add(const Duration(minutes: 10));
      await r.controller.retrySignedSubmit();
      expect(r.inputs('submit')[0], r.inputs('submit')[1]);
      expect(r.procedure('prepare'), hasLength(1));
      expect(r.keysGenerated, 1);
      expect(r.wallet.signCount, 1);
      expect(r.controller.isFunded, isFalse);
    },
  );

  test('retry rechecks account and wallet without resigning', () async {
    await r.review();
    r.intercept = (request) {
      if (request.url.path.endsWith('.submit')) {
        throw http.ClientException('drop');
      }
      return null;
    };
    await r.controller.approveReview();
    r.selectedWallet = null;
    await r.controller.retrySignedSubmit();
    expect(r.controller.error!.code, PantaErrorCode.walletChanged);
    r.selectedWallet = syntheticWalletAddress;
    r.session = const PantaSession(
      accountId: 'other-account',
      accessToken: 'other-bearer',
    );
    await r.controller.retrySignedSubmit();
    expect(r.controller.error!.code, PantaErrorCode.sessionChanged);
    expect(r.procedure('submit'), hasLength(1));
    expect(r.wallet.signCount, 1);
    expect(r.controller.canRetrySigned, isTrue);
  });

  test(
    'late submit response after timeout cannot imply a confirmed fill',
    () async {
      r.close();
      r = SyntheticPantaRig(timeout: const Duration(milliseconds: 100));
      await r.review();
      final reply = Completer<http.Response>();
      var wait = true;
      r.intercept = (request) {
        if (request.url.path.endsWith('.submit') && wait) {
          wait = false;
          return reply.future;
        }
        return null;
      };
      await r.controller.approveReview();
      expect(r.controller.phase, PantaTradePhase.signed);
      reply.complete(
        syntheticWire(
          syntheticOrderJson(
            state: 'FILLED',
            key: r.inputs('prepare').single['idempotencyKey'] as String,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(r.controller.isFunded, isFalse);
      await r.controller.retrySignedSubmit();
      expect(r.inputs('submit')[0], r.inputs('submit')[1]);
      expect(r.wallet.signCount, 1);
    },
  );

  test(
    'manual polling distinguishes QUOTED/SUBMITTED/PARTIAL from FILLED',
    () async {
      await r.review();
      await r.controller.approveReview();
      for (final state in ['QUOTED', 'SUBMITTED', 'PARTIAL', 'FILLED']) {
        r.serverState = state;
        await r.controller.refreshOrder();
        expect(r.controller.order!.fundingState.wire, state);
        expect(r.controller.isFunded, state == 'FILLED');
      }
      expect(r.wallet.signCount, 1);
      expect(r.procedure('order'), hasLength(4));
    },
  );

  test(
    'dropped submit can reconcile FILLED by order without resubmitting',
    () async {
      await r.review();
      r.intercept = (request) {
        if (request.url.path.endsWith('.submit')) {
          throw http.ClientException('drop');
        }
        return null;
      };
      await r.controller.approveReview();
      r.serverState = 'FILLED';
      await r.controller.refreshOrder();
      expect(r.controller.isFunded, isTrue);
      expect(r.controller.canRetrySigned, isFalse);
      expect(r.procedure('submit'), hasLength(1));
      expect(r.wallet.signCount, 1);
    },
  );

  test(
    'bad order evidence cannot turn a pending request into Funded',
    () async {
      await r.review();
      r.intercept = (request) {
        if (!request.url.path.endsWith('.submit')) return null;
        return syntheticWire({
          ...syntheticOrderJson(state: 'FILLED'),
          'fillTxSignature': null,
        });
      };
      await r.controller.approveReview();
      expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
      expect(r.controller.isFunded, isFalse);
      expect(r.controller.canRetrySigned, isTrue);
    },
  );

  test(
    'order binding and older status cannot overwrite confirmed evidence',
    () async {
      await r.review();
      r.serverState = 'FILLED';
      await r.controller.approveReview();
      expect(r.controller.isFunded, isTrue);
      r.intercept = (request) {
        if (!request.url.path.endsWith('.order')) return null;
        return syntheticWire({
          ...syntheticOrderJson(),
          'orderId': 'wrong-order',
        });
      };
      await r.controller.refreshOrder();
      expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
      expect(r.controller.isFunded, isTrue);
      r.intercept = null;
      r.serverState = 'SUBMITTED';
      await r.controller.refreshOrder();
      expect(r.controller.error!.code, PantaErrorCode.invalidResponse);
      expect(r.controller.isFunded, isTrue);
    },
  );
}
