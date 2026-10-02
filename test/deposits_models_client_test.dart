import 'dart:convert';

import 'package:chumbucket/features/deposits/data/deposits_client.dart';
import 'package:chumbucket/features/deposits/data/deposits_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'deposits_fakes.dart';

void main() {
  group('UsdAmount', () {
    test('parses whole cents and writes the BFF wire form', () {
      expect(UsdAmount.tryParse('25')!.cents, 2500);
      expect(UsdAmount.tryParse('25.5')!.cents, 2550);
      expect(UsdAmount.tryParse(' 25.05 ')!.wire, '25.05');
      expect(UsdAmount.tryParse('25.50')!.wire, '25.50');
      expect(UsdAmount.tryParse('25')!.label, r'$25');
    });

    test('refuses anything that is not a plain amount', () {
      for (final bad in [
        '',
        '-1',
        '1e3',
        '01',
        '1.234',
        'abc',
        '1,000',
        '1234567',
      ]) {
        expect(UsdAmount.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('number formatting never overstates', () {
    test('base units format with grouping and trimmed decimals', () {
      expect(formatBaseUnits(BigInt.from(12500000), 6), '12.50');
      expect(formatBaseUnits(BigInt.from(1234567890000), 6), '1,234,567.89');
      expect(formatBaseUnits(BigInt.zero, 6), '0.00');
      expect(
        formatBaseUnits(BigInt.from(250000000), 9, maxDecimals: 4),
        '0.25',
      );
      expect(
        formatBaseUnits(BigInt.from(1234567), 9, maxDecimals: 4),
        '0.0012',
      );
    });

    test('USDC decimals past six are dropped, not rounded up', () {
      expect(usdcToBaseUnits('1.9999999'), BigInt.from(1999999));
      expect(usdcRangeLabel('24.1', '24.4'), '24.10–24.40');
      expect(usdcRangeLabel('24.21', '24.21'), '24.21');
      expect(usdcRangeLabel(null, '1'), isNull);
    });
  });

  group('wire models are strict', () {
    test('status parses limits, presets, account and test mode', () {
      final s = DepositsStatus.fromJson(
        statusJson(environment: 'staging', needsEmail: true),
      );
      expect(s.available, isTrue);
      expect(s.isTestMode, isTrue);
      expect(s.minUsd!.cents, 500);
      expect(s.presets.map((p) => p.wire), ['10', '25', '50', '100']);
      expect(s.account!.wallets.single.address, walletA);
      expect(s.account!.needsEmail, isTrue);
    });

    test('a balance from anything but mainnet is refused', () {
      final json = balanceJson()..['network'] = 'solana-devnet';
      expect(
        () => WalletBalance.fromJson(json),
        throwsA(isA<DepositsException>()),
      );
      final ok = WalletBalance.fromJson(balanceJson());
      expect(ok.usdcLabel, '12.50');
      expect(ok.solLabel, '0.25');
    });

    test('a checkout URL off Crossmint is refused before any WebView', () {
      for (final url in [
        checkoutUrl(host: 'evil.example'),
        checkoutUrl().replaceFirst('https', 'http'),
        checkoutUrl().replaceFirst('/sdk/2024-03-05/embedded-checkout', '/x'),
        checkoutUrl().replaceFirst(
          'ck_production_synthetic',
          'sk_production_x',
        ),
      ]) {
        expect(
          () => CreatedDeposit.fromJson({
            'order': orderJson(),
            'checkoutUrl': url,
          }),
          throwsA(isA<DepositsException>()),
          reason: url,
        );
      }
      final created = CreatedDeposit.fromJson({
        'order': orderJson(),
        'checkoutUrl': checkoutUrl(),
      });
      expect(isCrossmintCheckoutUri(created.checkoutUri), isTrue);
    });

    test('orders: unknown states, bad ids and bad tx ids are errors', () {
      expect(
        () => DepositOrder.fromJson(orderJson(state: 'teleported')),
        throwsA(isA<DepositsException>()),
      );
      expect(
        () => DepositOrder.fromJson(orderJson(orderId: 'nope')),
        throwsA(isA<DepositsException>()),
      );
      expect(
        () =>
            DepositOrder.fromJson(orderJson(state: 'delivered', txId: '0OIl')),
        throwsA(isA<DepositsException>()),
      );
      final done = DepositOrder.fromJson(
        orderJson(
          state: 'delivered',
          txId: syntheticTx,
          network: 'solana-devnet',
        ),
      );
      expect(done.explorerUri!.queryParameters['cluster'], 'devnet');
      expect(done.state.isTerminal, isTrue);
    });

    test('only in-flight or reviewed orders are resumed', () {
      final resumable = DepositOrderState.values.where(
        (s) => s.isWorthResuming,
      );
      // Not a proof-waiting order: its checkout link is gone, so once signed
      // it still couldn't be paid. A fresh order asks for the signature.
      expect(resumable, {
        DepositOrderState.paymentProcessing,
        DepositOrderState.delivering,
        DepositOrderState.identityReview,
      });
    });
  });

  group('DepositsClient', () {
    test('POSTs tRPC envelopes with the session in the header only', () async {
      final bff = FakeDepositsBff();
      final client = bff.newClient();
      await client.create(
        amount: UsdAmount.tryParse('25')!,
        idempotencyKey: 'k' * 20,
        wallet: walletA,
      );
      final request = bff.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://bff.invalid/trpc/deposits.create',
      );
      expect(
        request.headers['authorization'],
        'Bearer synthetic-session-token',
      );
      expect(request.url.query, isEmpty);
      final input = (jsonDecode(request.body) as Map)['json'] as Map;
      // The client names which proven wallet; it never sends a recipient.
      expect(
        input.keys,
        unorderedEquals(['amountUsd', 'idempotencyKey', 'wallet']),
      );
      expect(input['amountUsd'], '25');
    });

    test('status works signed out; everything else needs a session', () async {
      final bff = FakeDepositsBff();
      final client = bff.newClient(token: null);
      await client.status();
      expect(bff.requests.single.headers.containsKey('authorization'), isFalse);
      await expectLater(
        client.balance(),
        throwsA(
          isA<DepositsException>().having(
            (e) => e.kind,
            'kind',
            DepositsErrorKind.signedOut,
          ),
        ),
      );
      expect(bff.requests, hasLength(1));
    });

    test('maps BFF errors and keeps only its short copy', () async {
      final bff = FakeDepositsBff();
      final client = bff.newClient();
      bff.handlers['deposits.quote'] =
          (_) => trpcError('BAD_REQUEST', r'Choose an amount from $5 to $500.');
      await expectLater(
        client.quote(amount: UsdAmount.tryParse('1')!),
        throwsA(
          isA<DepositsException>()
              .having((e) => e.kind, 'kind', DepositsErrorKind.invalid)
              .having(
                (e) => e.message,
                'message',
                r'Choose an amount from $5 to $500.',
              ),
        ),
      );
      // A validator dump is never shown; local copy instead.
      bff.handlers['deposits.quote'] =
          (_) => trpcError('BAD_REQUEST', '[{"code":"invalid_string"}]');
      await expectLater(
        client.quote(amount: UsdAmount.tryParse('1')!),
        throwsA(
          isA<DepositsException>().having(
            (e) => e.message,
            'message',
            'Check the amount and try again.',
          ),
        ),
      );
      bff.handlers['deposits.order'] =
          (_) => trpcError(
            'NOT_FOUND',
            'We couldn\'t find that payment on your account.',
            status: 404,
          );
      await expectLater(
        client.order(orderOne),
        throwsA(
          isA<DepositsException>().having(
            (e) => e.kind,
            'kind',
            DepositsErrorKind.notFound,
          ),
        ),
      );
      bff.handlers['deposits.balance'] =
          (_) => trpcError('SERVICE_UNAVAILABLE', 'x', status: 503);
      await expectLater(
        client.balance(),
        throwsA(
          isA<DepositsException>().having(
            (e) => e.kind,
            'kind',
            DepositsErrorKind.provider,
          ),
        ),
      );
    });

    test('refuses redirects, oversized bodies and non-HTTPS bases', () async {
      final redirecting = DepositsClient(
        baseUri: Uri.parse('https://bff.invalid/trpc'),
        token: () => 't',
        client: MockClient(
          (_) async =>
              http.Response('', 302, headers: {'location': 'https://x'}),
        ),
      );
      await expectLater(
        redirecting.status(),
        throwsA(
          isA<DepositsException>().having(
            (e) => e.kind,
            'kind',
            DepositsErrorKind.invalidResponse,
          ),
        ),
      );
      final huge = DepositsClient(
        baseUri: Uri.parse('https://bff.invalid/trpc'),
        token: () => 't',
        client: MockClient((_) async => http.Response('x' * 200000, 200)),
      );
      await expectLater(huge.status(), throwsA(isA<DepositsException>()));
      expect(
        () => DepositsClient(
          baseUri: Uri.parse('http://bff.invalid/trpc'),
          token: () => 't',
        ),
        throwsArgumentError,
      );
    });

    test('a dropped connection reads as offline, never a crash', () async {
      final client = DepositsClient(
        baseUri: Uri.parse('https://bff.invalid/trpc'),
        token: () => 't',
        client: MockClient((_) async => throw http.ClientException('reset')),
      );
      await expectLater(
        client.status(),
        throwsA(
          isA<DepositsException>().having(
            (e) => e.kind,
            'kind',
            DepositsErrorKind.connection,
          ),
        ),
      );
    });
  });
}
