import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'panta_trading_controller_test.dart'
    show
        syntheticPrepareJson,
        syntheticOrderJson,
        syntheticUnsigned,
        syntheticSigned,
        syntheticWalletAddress,
        syntheticCall,
        syntheticKey,
        syntheticWire,
        syntheticInput;

Matcher pantaError(PantaErrorCode code) =>
    throwsA(isA<PantaException>().having((error) => error.code, 'code', code));

void main() {
  for (final entry
      in {
        '0.000001': '1',
        '1': '1000000',
        '1.2': '1200000',
        '0001.200000': '1200000',
        '99.999999': '99999999',
        '100': '100000000',
      }.entries) {
    test('exact decimal ${entry.key} converts to ${entry.value}', () {
      expect(PantaUsdcAmount.parse(entry.key).baseUnits, entry.value);
    });
  }
  for (final invalid in [
    '',
    '0',
    '0.000000',
    '-1',
    '+1',
    '1e1',
    '1E1',
    'NaN',
    'Infinity',
    '0x10',
    '.1',
    '1.',
    '1.0000001',
    ' 1',
    '1 ',
    '1,000',
    '100.000001',
    '101',
    '12345678901234567890123456789012345',
  ]) {
    test('invalid amount $invalid is refused without rounding', () {
      expect(
        () => PantaUsdcAmount.parse(invalid),
        pantaError(PantaErrorCode.invalidAmount),
      );
    });
  }

  test('canonical UnsignedOrder/review and VenueOrder round trip exactly', () {
    final json = syntheticPrepareJson();
    final prepared = PantaPreparedTrade.fromJson(json);
    expect(prepared.toJson(), json);
    expect(prepared.review.avgPrice, '1.250000000000000001');
    expect(prepared.order.quotedProbability, isNull);
    final normalized = syntheticOrderJson(state: 'FILLED');
    expect(PantaVenueOrder.fromJson(normalized).toJson(), normalized);
  });

  for (final patch in <Map<String, Object?>>[
    {'venue': 'fixture'},
    {'demo': true},
    {'encoding': 'demo-non-executable'},
    {'expiresAt': 'tomorrow'},
    {'expiresAt': -1},
    {'expiresAt': 1.5},
    {'payload': ''},
    {'payload': '%%%bad'},
    {'payload': 'AQ'},
    {'payload': 'AQ==\n'},
    {'payload': 'data:application/octet-stream;base64,AQ=='},
  ]) {
    test(
      'transaction envelope rejects ${patch.keys.first}: ${patch.values.first}',
      () {
        final json = syntheticPrepareJson();
        ((json['order'] as Map)['transaction'] as Map).addAll(patch);
        expect(
          () => PantaPreparedTrade.fromJson(json),
          pantaError(PantaErrorCode.invalidResponse),
        );
      },
    );
  }
  for (final patch in <Map<String, Object?>>[
    {'amountUsdc': 10},
    {'amountUsdc': '11'},
    {'amountBaseUnits': '10000001'},
    {'expectedShares': '1e10'},
    {'expectedShares': '0'},
    {'avgPrice': '-1'},
    {'avgPrice': 1.25},
    {'feeUsdc': '-0.01'},
    {'maxSlippageBps': 200},
    {'attribution': 'Some provider'},
  ]) {
    test('review decimal/attribution rejects ${patch.keys.first}', () {
      final json = syntheticPrepareJson();
      (json['review'] as Map).addAll(patch);
      expect(
        () => PantaPreparedTrade.fromJson(json),
        pantaError(PantaErrorCode.invalidResponse),
      );
    });
  }
  for (final patch in <Map<String, Object?>>[
    {'filledBaseUnits': '0'},
    {'filledBaseUnits': '9999999'},
    {'fillTxSignature': null},
    {'fillTxSignature': 'not-a-signature'},
    {'fillTxSignature': List.filled(64, '1').join()},
    {'demo': true},
    {'venue': 'fixture'},
    {'fundingState': 'FUNDED'},
    {'filledBaseUnits': 10000000},
    {'amountBaseUnits': '1e7'},
  ]) {
    test('FILLED requires canonical fill evidence ${patch.keys.first}', () {
      expect(
        () => PantaVenueOrder.fromJson({
          ...syntheticOrderJson(state: 'FILLED'),
          ...patch,
        }),
        pantaError(PantaErrorCode.invalidResponse),
      );
    });
  }

  test('all normalized states have honest funding labels', () {
    for (final state in PantaFundingState.values) {
      expect(state.label.contains('Funded'), state == PantaFundingState.filled);
    }
    for (final state in ['QUOTED', 'SUBMITTED', 'PARTIAL']) {
      expect(
        PantaVenueOrder.fromJson(syntheticOrderJson(state: state)).isFunded,
        isFalse,
      );
    }
  });

  test(
    'native v0 encoder validates round-trip message including lookup tables',
    () {
      const validator = PantaTransactionValidator();
      for (final lookups in [false, true]) {
        final bytes = syntheticUnsigned(withLookup: lookups);
        validator.validateUnsigned(bytes, syntheticWalletAddress);
        validator.validateSigned(
          bytes,
          syntheticSigned(bytes),
          syntheticWalletAddress,
        );
        expect(
          () => validator.validateUnsigned(
            Uint8List.fromList([...bytes, 0]),
            syntheticWalletAddress,
          ),
          pantaError(PantaErrorCode.invalidResponse),
        );
      }
    },
  );

  test(
    'native v0 rejects legacy/version mismatch and wrong selected signer',
    () {
      const validator = PantaTransactionValidator();
      final bytes = syntheticUnsigned();
      for (final invalid in [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList(bytes)..[65] = 129,
        Uint8List.fromList(bytes)..[65] = 1,
        syntheticUnsigned(ownerByte: 2),
      ]) {
        expect(
          () => validator.validateUnsigned(invalid, syntheticWalletAddress),
          pantaError(PantaErrorCode.invalidResponse),
        );
      }
    },
  );

  group('injected HTTP transport', () {
    late MockClient transport;
    late PantaTradingClient client;
    final requests = <http.Request>[];
    PantaSession? session;
    setUp(() {
      requests.clear();
      session = const PantaSession(
        accountId: 'canonical-account',
        accessToken: 'synthetic-bearer',
      );
      transport = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('.status')) {
          return syntheticWire({
            'enabled': true,
            'reason': null,
            'venue': 'panta',
            'attribution': 'Powered by Panta',
          });
        }
        if (request.url.path.endsWith('.forCall')) {
          return syntheticWire({'order': syntheticOrderJson()});
        }
        if (request.url.path.endsWith('.prepare')) {
          return syntheticWire(syntheticPrepareJson());
        }
        return syntheticWire(syntheticOrderJson());
      });
      client = PantaTradingClient(
        baseUri: Uri.parse('https://bff.invalid/trpc/'),
        session: () => session,
        client: transport,
      );
    });
    tearDown(() {
      client.close();
      transport.close();
    });

    Future<PantaPreparedTrade> prepare() => client.prepare(
      PantaPrepareInput(
        callId: syntheticCall,
        wallet: syntheticWalletAddress,
        amountBaseUnits: '10000000',
        idempotencyKey: syntheticKey,
      ),
      accountId: 'canonical-account',
    );

    test(
      'exact POST procedures, private bodies, and bearer-only header',
      () async {
        await client.status();
        await prepare();
        final payload = base64Encode(syntheticSigned(syntheticUnsigned()));
        await client.submit(
          orderId: 'synthetic-order',
          signedTransaction: payload,
          accountId: 'canonical-account',
        );
        await client.order(
          orderId: 'synthetic-order',
          accountId: 'canonical-account',
        );
        expect(
          (await client.forCall(
            callId: syntheticCall,
            wallet: syntheticWalletAddress,
            accountId: 'canonical-account',
          ))!.fundingState,
          PantaFundingState.submitted,
        );
        expect(requests.map((request) => request.url.path), [
          '/trpc/pantaTrading.status',
          '/trpc/pantaTrading.prepare',
          '/trpc/pantaTrading.submit',
          '/trpc/pantaTrading.order',
          '/trpc/pantaTrading.forCall',
        ]);
        expect(syntheticInput(requests[0]), isEmpty);
        expect(requests[0].headers.containsKey('authorization'), isFalse);
        expect(syntheticInput(requests[1]), {
          'callId': syntheticCall,
          'wallet': syntheticWalletAddress,
          'amountBaseUnits': '10000000',
          'idempotencyKey': syntheticKey,
          'maxSlippageBps': 100,
        });
        expect(syntheticInput(requests[2]), {
          'orderId': 'synthetic-order',
          'signedTransaction': payload,
        });
        expect(syntheticInput(requests[3]), {'orderId': 'synthetic-order'});
        expect(syntheticInput(requests[4]), {
          'callId': syntheticCall,
          'wallet': syntheticWalletAddress,
        });
        for (final request in requests) {
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 0);
          expect(request.url.hasQuery, isFalse);
          expect(request.body, isNot(contains('synthetic-bearer')));
          expect(request.body, isNot(contains('canonical-account')));
          expect(request.url.toString(), isNot(contains('synthetic-bearer')));
        }
        for (final request in requests.skip(1)) {
          expect(request.headers['authorization'], 'Bearer synthetic-bearer');
        }
      },
    );

    test('status works without consulting a signed-in session', () async {
      session = null;
      expect((await client.status()).enabled, isTrue);
      await expectLater(prepare(), pantaError(PantaErrorCode.signedOut));
      expect(requests, hasLength(1));
    });

    test(
      'canonical account change never sends authenticated request',
      () async {
        session = const PantaSession(
          accountId: 'other-account',
          accessToken: 'other-bearer',
        );
        await expectLater(prepare(), pantaError(PantaErrorCode.sessionChanged));
        expect(requests, isEmpty);
      },
    );

    test('credential injection is refused locally', () async {
      session = const PantaSession(
        accountId: 'canonical-account',
        accessToken: 'token\r\nextra-header',
      );
      await expectLater(prepare(), pantaError(PantaErrorCode.signedOut));
      expect(requests, isEmpty);
    });
  });

  for (final uri in [
    'http://bff.invalid',
    'https://user:password@bff.invalid',
    'https://bff.invalid?token=synthetic',
    'https://bff.invalid#token',
    '/trpc',
  ]) {
    test('base URI rejects unsafe credential location $uri', () {
      expect(
        () => PantaTradingClient(baseUri: Uri.parse(uri), session: () => null),
        throwsArgumentError,
      );
    });
  }

  for (final entry in <(http.Response, PantaErrorCode)>[
    (
      http.Response('untrusted synthetic-bearer', 401),
      PantaErrorCode.signedOut,
    ),
    (
      http.Response(
        'untrusted synthetic-bearer',
        302,
        headers: {
          'location': 'https://provider.invalid?token=synthetic-bearer',
        },
      ),
      PantaErrorCode.rejected,
    ),
    (
      http.Response('not JSON synthetic-bearer', 200),
      PantaErrorCode.invalidResponse,
    ),
    (http.Response('{}', 200), PantaErrorCode.invalidResponse),
    (
      http.Response(
        jsonEncode({
          'error': {
            'json': {
              'message': 'untrusted synthetic-bearer',
              'data': {'code': 'BAD_GATEWAY'},
            },
          },
        }),
        502,
      ),
      PantaErrorCode.rejected,
    ),
    (
      http.Response(
        jsonEncode({
          'error': {
            'json': {
              'message': 'untrusted synthetic-bearer',
              'data': {'code': 'UNAUTHORIZED'},
            },
          },
        }),
        200,
      ),
      PantaErrorCode.signedOut,
    ),
  ]) {
    test(
      'HTTP ${entry.$1.statusCode} errors cannot expose response detail',
      () async {
        final transport = MockClient((_) async => entry.$1);
        final client = PantaTradingClient(
          baseUri: Uri.parse('https://bff.invalid'),
          session: () => null,
          client: transport,
        );
        addTearDown(() {
          client.close();
          transport.close();
        });
        try {
          await client.status();
          fail('Expected safe error.');
        } on PantaException catch (error) {
          expect(error.code, entry.$2);
          expect(error.toString(), isNot(contains('untrusted')));
          expect(error.toString(), isNot(contains('synthetic-bearer')));
        }
      },
    );
  }

  test(
    'send/body timeout has no automatic retry and hides transport errors',
    () async {
      var count = 0;
      final never = Completer<http.Response>();
      final slow = MockClient((_) {
        count++;
        return never.future;
      });
      final client = PantaTradingClient(
        baseUri: Uri.parse('https://bff.invalid'),
        session: () => null,
        client: slow,
        timeout: const Duration(milliseconds: 20),
      );
      addTearDown(() {
        client.close();
        slow.close();
      });
      await expectLater(client.status(), pantaError(PantaErrorCode.connection));
      expect(count, 1);
      never.complete(http.Response('{}', 200));
    },
  );

  test(
    'body read timeout is bounded separately from successful headers',
    () async {
      final body = StreamController<List<int>>();
      final transport = MockClient.streaming(
        (_, _) async => http.StreamedResponse(body.stream, 200),
      );
      final client = PantaTradingClient(
        baseUri: Uri.parse('https://bff.invalid'),
        session: () => null,
        client: transport,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(client.status(), pantaError(PantaErrorCode.connection));
      await body.close();
      client.close();
      transport.close();
    },
  );

  test('oversized server body fails with fixed copy', () async {
    final transport = MockClient(
      (_) async => http.Response(List.filled(65537, 'x').join(), 200),
    );
    final client = PantaTradingClient(
      baseUri: Uri.parse('https://bff.invalid'),
      session: () => null,
      client: transport,
    );
    addTearDown(() {
      client.close();
      transport.close();
    });
    await expectLater(
      client.status(),
      pantaError(PantaErrorCode.invalidResponse),
    );
  });
}
