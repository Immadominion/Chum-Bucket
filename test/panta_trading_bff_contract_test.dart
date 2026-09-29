import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Stdio, not localhost HTTP: real BFF router/service with synthetic boundaries.
/// No .env files or inherited credential environment enter the harness.
class _BffPipe {
  _BffPipe(this.process) {
    _output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final message = jsonDecode(line) as Map<String, dynamic>;
          final pending = _pending.remove(message['id']);
          if (message['failed'] == true) {
            pending?.completeError(
              StateError('Synthetic BFF harness refused the operation.'),
            );
          } else {
            pending?.complete(message['result'] as Map<String, dynamic>);
          }
        });
    // Drain diagnostics without exposing potentially sensitive response detail.
    _errors = process.stderr.listen((_) {});
  }
  final Process process;
  late final StreamSubscription<String> _output;
  late final StreamSubscription<List<int>> _errors;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _sequence = 0;

  static Future<_BffPipe> start() async {
    final root = Directory.current.absolute;
    final apiRoot = Directory(
      '${root.parent.path}/chumbucket-social-calls-api',
    );
    final script =
        '${root.path}/lib/features/panta_trading/testing/bff_contract_harness.ts';
    if (!File('${apiRoot.path}/src/api/pantaTrading.ts').existsSync()) {
      throw StateError(
        'The sibling real BFF is required for this contract test.',
      );
    }
    return _BffPipe(
      await Process.start(
        '/opt/homebrew/bin/bun',
        ['--no-env-file', script, apiRoot.path],
        workingDirectory: apiRoot.path,
        includeParentEnvironment: false,
        environment: {'PATH': '/opt/homebrew/bin:/usr/bin:/bin'},
      ),
    );
  }

  Future<Map<String, dynamic>> request(Map<String, Object?> input) {
    final id = ++_sequence;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(jsonEncode({...input, 'id': id}));
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await _output.cancel();
    await _errors.cancel();
  }
}

class _BffTransport extends http.BaseClient {
  _BffTransport(this.pipe);
  final _BffPipe pipe;
  final inputs = <Map<String, dynamic>>[];
  bool dropNextSubmit = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.decode(await request.finalize().toBytes());
    expect(request.followRedirects, isFalse);
    expect(request.url.hasQuery, isFalse);
    final input = jsonDecode(body) as Map<String, dynamic>;
    inputs.add({
      'procedure': request.url.path.split('/').last,
      'input': input['json'],
    });
    final response = await pipe.request({
      'method': request.method,
      'path': request.url.path,
      'headers': request.headers,
      'body': body,
    });
    if (request.url.path.endsWith('.submit') && dropNextSubmit) {
      dropNextSubmit = false;
      throw http.ClientException(
        'Synthetic lost reply after real router completed.',
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(response['body'] as String)),
      response['status'] as int,
    );
  }
}

/// Deterministic test signing only. Does not represent MWA or user approval.
class _SyntheticBffWallet implements PantaWalletPort {
  _SyntheticBffWallet(this.pipe);
  final _BffPipe pipe;
  int count = 0;
  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    count++;
    final result = await pipe.request({
      'op': 'sign',
      'payload': base64Encode(unsigned),
    });
    return base64Decode(result['payload'] as String);
  }
}

void main() {
  late _BffPipe pipe;
  late _BffTransport transport;
  late PantaTradingClient client;
  late _SyntheticBffWallet wallet;
  late PantaTradeController controller;
  late DateTime now;
  late Map<String, dynamic> meta;

  setUp(() async {
    pipe = await _BffPipe.start();
    meta = await pipe.request({'op': 'meta'});
    now = DateTime.fromMillisecondsSinceEpoch(meta['now'] as int);
    transport = _BffTransport(pipe);
    wallet = _SyntheticBffWallet(pipe);
    client = PantaTradingClient(
      baseUri: Uri.parse('https://synthetic.invalid/trpc'),
      client: transport,
      session:
          () => const PantaSession(
            accountId: 'canonical-synthetic-account',
            accessToken: 'synthetic-session',
          ),
    );
    controller = PantaTradeController(
      callId: meta['callId'] as String,
      marketId: meta['marketId'] as String,
      venueMarketId: meta['venueMarketId'] as String,
      side: Side.yes,
      wallet: meta['wallet'] as String,
      client: client,
      walletPort: wallet,
      selectedWallet: () => meta['wallet'] as String,
      now: () => now,
    );
  });
  tearDown(() async {
    controller.dispose();
    client.close();
    transport.close();
    await pipe.close();
  });

  test(
    'Dart client decodes real tRPC POST status/prepare/submit/order',
    () async {
      expect((await client.status()).enabled, isTrue);
      controller.editAmount('1');
      await controller.prepare();
      expect(controller.error, isNull);
      expect(controller.phase, PantaTradePhase.review);
      expect(controller.prepared!.review.avgPrice, '1.25');
      expect(wallet.count, 0);
      await controller.approveReview();
      expect(controller.error, isNull);
      expect(controller.order!.fundingState, PantaFundingState.submitted);
      expect(controller.isFunded, isFalse);
      await pipe.request({'op': 'confirm'});
      await controller.refreshOrder();
      expect(controller.error, isNull);
      expect(controller.isFunded, isTrue);
      expect(controller.order!.fillTxSignature, isNotNull);
      expect(wallet.count, 1);
      expect((await pipe.request({'op': 'metrics'}))['quoteCount'], 1);
    },
  );

  test(
    'real BFF expired retry preserves signed bytes and reconciles by order',
    () async {
      controller.editAmount('1');
      await controller.prepare();
      transport.dropNextSubmit = true;
      await controller.approveReview();
      expect(controller.phase, PantaTradePhase.signed);
      expect(controller.isFunded, isFalse);
      final advanced = await pipe.request({'op': 'advance', 'millis': 180000});
      now = DateTime.fromMillisecondsSinceEpoch(advanced['now'] as int);
      await controller.retrySignedSubmit();
      expect(controller.error!.code, PantaErrorCode.rejected);
      expect(controller.phase, PantaTradePhase.signed);
      expect(controller.isFunded, isFalse);
      final submissions =
          transport.inputs
              .where((row) => row['procedure'] == 'pantaTrading.submit')
              .toList();
      expect(submissions[0]['input'], submissions[1]['input']);
      expect(wallet.count, 1);
      expect((await pipe.request({'op': 'metrics'}))['quoteCount'], 1);
      await pipe.request({'op': 'confirm'});
      await controller.refreshOrder();
      expect(controller.error, isNull);
      expect(controller.isFunded, isTrue);
    },
  );

  test(
    'real expired UUID is refused until explicit cancel starts fresh intent',
    () async {
      controller.editAmount('1');
      await controller.prepare();
      final quote = controller.prepared!.order;
      final advanced = await pipe.request({'op': 'advance', 'millis': 61000});
      now = DateTime.fromMillisecondsSinceEpoch(advanced['now'] as int);
      await controller.approveReview();
      expect(controller.error!.code, PantaErrorCode.expired);
      expect(wallet.count, 0);
      await expectLater(
        client.prepare(
          PantaPrepareInput(
            callId: meta['callId'] as String,
            wallet: meta['wallet'] as String,
            amountBaseUnits: '1000000',
            idempotencyKey: quote.idempotencyKey,
          ),
          accountId: 'canonical-synthetic-account',
        ),
        throwsA(isA<PantaException>()),
      );
      expect(controller.cancel(), isTrue);
      controller.editAmount('1');
      await controller.prepare();
      expect(controller.error, isNull);
      expect(
        controller.prepared!.order.idempotencyKey,
        isNot(quote.idempotencyKey),
      );
      expect(controller.phase, PantaTradePhase.review);
      expect(wallet.count, 0);
    },
  );

  test(
    'real router rejects a forged identity/body and unsigned submit',
    () async {
      final refused = await pipe.request({
        'method': 'POST',
        'path': '/trpc/pantaTrading.prepare',
        'headers': {
          'content-type': 'application/json',
          'authorization': 'Bearer synthetic-session',
        },
        'body': jsonEncode({
          'json': {
            'callId': meta['callId'],
            'wallet': meta['wallet'],
            'amountBaseUnits': '1000000',
            'idempotencyKey': 'synthetic-intent',
            'maxSlippageBps': 100,
            'userId': 'forged-user',
          },
        }),
      });
      expect(refused['status'], 400);
      controller.editAmount('1');
      await controller.prepare();
      await expectLater(
        client.submit(
          orderId: controller.prepared!.order.orderId,
          signedTransaction: controller.prepared!.order.transaction.payload,
          accountId: 'canonical-synthetic-account',
        ),
        throwsA(isA<PantaException>()),
      );
      expect((await pipe.request({'op': 'metrics'}))['broadcastCount'], 0);
      expect(controller.isFunded, isFalse);
    },
  );

  for (final filled in [false, true]) {
    test(
      'actual BFF restores ${filled ? 'FILLED' : 'SUBMITTED'} into a fresh controller',
      () async {
        controller.editAmount('1');
        await controller.prepare();
        await controller.approveReview();
        if (filled) {
          await pipe.request({'op': 'confirm'});
          await controller.refreshOrder();
        }
        final freshWallet = _SyntheticBffWallet(pipe);
        final fresh = PantaTradeController(
          callId: meta['callId'] as String,
          marketId: meta['marketId'] as String,
          venueMarketId: meta['venueMarketId'] as String,
          side: Side.yes,
          wallet: meta['wallet'] as String,
          client: client,
          walletPort: freshWallet,
          selectedWallet: () => meta['wallet'] as String,
          now: () => now,
        );
        addTearDown(fresh.dispose);
        await fresh.loadStatus();
        expect(fresh.error, isNull);
        expect(fresh.phase, PantaTradePhase.order);
        expect(fresh.prepared, isNull);
        expect(fresh.isFunded, filled);
        expect(fresh.canRetrySigned, isFalse);
        await fresh.prepare();
        await fresh.approveReview();
        expect(freshWallet.count, 0);
        expect((await pipe.request({'op': 'metrics'}))['quoteCount'], 1);
        await pipe.request({'op': 'confirm'});
        await fresh.refreshOrder();
        expect(fresh.error, isNull);
        expect(fresh.isFunded, isTrue);
        expect(freshWallet.count, 0);
      },
    );
  }
}
