// Synthetic deposits BFF for tests. Every value here is test data; nothing is
// shown to a person. Shapes mirror the API's deposits.* procedures
// (chumbucket-social-calls-api src/api/deposits.ts).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/deposits/data/deposits_client.dart';
import 'package:chumbucket/features/deposits/domain/deposit_wallet_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const walletA = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const walletB = 'GsbwXfJraMomNxBcjYLcG3mxkBUiyWXAB32fGbSMQRdW';
const orderOne = '3f1d6a2e-7c41-4b8e-9a0f-2d5e8c1b7a90';
const orderTwo = '8b2c0d4e-1a3f-4e5d-8c7b-6a9f0e1d2c3b';
final syntheticTx = '5' * 64;

http.Response trpcOk(Object? data) => http.Response(
  jsonEncode({
    'result': {
      'data': {'json': data},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response trpcError(String code, String message, {int status = 400}) =>
    http.Response(
      jsonEncode({
        'error': {
          'json': {
            'message': message,
            'code': -32600,
            'data': {'code': code, 'httpStatus': status},
          },
        },
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> walletJson(
  String address, {
  String type = 'mwa',
  bool primary = true,
  bool session = true,
}) => {
  'address': address,
  'walletType': type,
  'primary': primary,
  'session': session,
};

Map<String, Object?> statusJson({
  bool available = true,
  String environment = 'production',
  List<Map<String, Object?>>? wallets,
  bool needsEmail = false,
  String? accountIssue,
  Map<String, Object?>? reason,
  bool balanceAvailable = true,
  List<String> presets = const ['10', '25', '50', '100'],
}) => {
  'available': available,
  'reason': reason,
  'provider': 'Crossmint',
  'environment': available ? environment : null,
  'asset': 'USDC',
  'chain': 'solana',
  'deliveryNetwork':
      available
          ? (environment == 'staging' ? 'solana-devnet' : 'solana-mainnet')
          : null,
  'limits': available ? {'minUsd': '5', 'maxUsd': '500'} : null,
  'presetsUsd': available ? presets : <String>[],
  'paymentMethods': ['card', 'apple_pay', 'google_pay'],
  'balanceAvailable': balanceAvailable,
  'account':
      accountIssue != null
          ? null
          : {
            'wallets': wallets ?? [walletJson(walletA)],
            'receiptEmail': needsEmail ? null : 'ad•••@example.com',
            'needsEmail': needsEmail,
          },
  'accountIssue': accountIssue,
};

Map<String, Object?> balanceJson({
  String wallet = walletA,
  String lamports = '250000000',
  String usdc = '12500000',
}) => {
  'wallet': wallet,
  'network': 'solana-mainnet',
  'lamports': lamports,
  'usdcBaseUnits': usdc,
  'slot': 1,
  'readAt': DateTime.now().toUtc().toIso8601String(),
};

Map<String, Object?> quoteJson(
  String amountUsd, {
  String recipient = walletA,
}) => {
  'amountUsd': amountUsd,
  'currency': 'usd',
  'totalUsd': amountUsd,
  'receiveUsdc': {'min': '24.1', 'max': '24.4'},
  'networkFeeUsd': null,
  'expiresAt': null,
  'recipient': recipient,
  'deliveryNetwork': 'solana-mainnet',
};

Map<String, Object?> orderJson({
  String orderId = orderOne,
  String state = 'awaiting_payment',
  String recipient = walletA,
  String? totalUsd = '25',
  Map<String, String>? receive = const {'min': '24.1', 'max': '24.4'},
  String? txId,
  String network = 'solana-mainnet',
  String? proof,
  Map<String, Object?>? failure,
  String? refundedUsd,
}) => {
  'orderId': orderId,
  'state': state,
  'terminal': const {
    'delivered',
    'delivery_failed',
    'identity_failed',
    'expired',
  }.contains(state),
  'phase': 'payment',
  'paymentStatus': null,
  'deliveryStatus': null,
  'totalUsd': totalUsd,
  'receiveUsdc': receive,
  'txId': txId,
  'recipient': recipient,
  'deliveryNetwork': network,
  'failure': failure,
  'refundedUsd': refundedUsd,
  'walletProofMessage': proof,
  'quoteExpiresAt': null,
};

String checkoutUrl({
  String orderId = orderOne,
  String host = 'www.crossmint.com',
}) =>
    Uri.https(host, '/sdk/2024-03-05/embedded-checkout', {
      'orderId': orderId,
      'clientSecret': 'synthetic-client-secret',
      'apiKey': 'ck_production_synthetic',
      'payment': '{}',
      'appearance': '{}',
    }).toString();

typedef DepositsHandler =
    FutureOr<http.Response> Function(Map<String, Object?> input);

/// A scripted BFF. Each procedure has a default; tests replace what they need.
/// `orderStates` is consumed one per `deposits.order` call; the last repeats.
class FakeDepositsBff {
  FakeDepositsBff() {
    client = MockClient((request) async {
      requests.add(request);
      final procedure = request.url.path.split('/').last;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final input = (body['json'] as Map).cast<String, Object?>();
      calls.add((procedure, input));
      final handler = handlers[procedure];
      if (handler == null) throw StateError('Unexpected $procedure');
      return handler(input);
    });
    handlers.addAll({
      'deposits.status': (_) => trpcOk(status),
      'deposits.balance': (_) => trpcOk(balance),
      // The server funds the named wallet when it is one of the account's.
      'deposits.quote':
          (input) => trpcOk(
            quoteJson(
              input['amountUsd'] as String,
              recipient: (input['wallet'] as String?) ?? walletA,
            ),
          ),
      'deposits.create':
          (input) => trpcOk({
            'order': orderJson(totalUsd: input['amountUsd'] as String),
            'checkoutUrl': checkoutUrl(),
          }),
      'deposits.order': (_) {
        final next =
            orderStates.length > 1
                ? orderStates.removeAt(0)
                : orderStates.first;
        return trpcOk(next);
      },
      'deposits.verifyWallet': (_) => trpcOk(orderJson()),
    });
  }

  late final MockClient client;
  final requests = <http.Request>[];
  final calls = <(String, Map<String, Object?>)>[];
  final handlers = <String, DepositsHandler>{};
  Map<String, Object?> status = statusJson();
  Map<String, Object?> balance = balanceJson();
  List<Map<String, Object?>> orderStates = [orderJson()];

  Iterable<Map<String, Object?>> inputs(String procedure) =>
      calls.where((c) => c.$1 == 'deposits.$procedure').map((c) => c.$2);

  DepositsClient newClient({String? token = 'synthetic-session-token'}) =>
      DepositsClient(
        baseUri: Uri.parse('https://bff.invalid/trpc'),
        token: () => token,
        client: client,
        timeout: const Duration(seconds: 2),
      );
}

/// A device wallet that signs with a scripted answer.
class FakeWalletSource implements DepositWalletSource {
  FakeWalletSource(this.address, {this.kind = DepositWalletKind.device});

  @override
  final String? address;
  @override
  final DepositWalletKind kind;
  bool current = true;
  Object? failWith;
  final signed = <Uint8List>[];

  @override
  bool get isCurrent => current;

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    signed.add(message);
    if (failWith != null) throw failWith!;
    return Uint8List.fromList(List<int>.generate(64, (i) => i));
  }
}

/// Real-timer wait for a condition (controller tests use tiny intervals).
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition not met in $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
