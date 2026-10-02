/// A fake `solTopUp.*` BFF and its JSON, shared by the SOL top-up tests.
library;

import 'dart:convert';

import 'package:chumbucket/features/sol_topup/data/sol_topup_client.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'deposits_fakes.dart' show trpcOk;
import 'fixtures/jupiter_gasless_fixtures.dart';

// ── a fake BFF ──────────────────────────────────────────────────────────────

typedef TopUpHandler = http.Response Function(Map<String, Object?> input);

Map<String, Object?> topUpStatusJson({bool available = true, String? reason}) =>
    {
      'available': available,
      'reason':
          available
              ? null
              : {'code': 'NOT_CONFIGURED', 'message': reason ?? 'not set up'},
      'provider': 'Jupiter',
      'from': 'USDC',
      'to': 'SOL',
      'network': 'solana-mainnet',
      'limits':
          available
              ? {'minBaseUnits': '1000000', 'maxBaseUnits': '25000000'}
              : null,
    };

Map<String, Object?> topUpPlanJson({
  String lamports = '0',
  String usdc = '20000000',
  String? blocker,
  String suggestion = '1000000',
  int coveredNow = 0,
}) => {
  'wallet': kSwapOwner,
  'network': 'solana-mainnet',
  'lamports': lamports,
  'usdcBaseUnits': usdc,
  'readAt': '2026-10-02T12:00:00.000Z',
  'perTradeLamports': '1686400',
  'floorLamports': '650240',
  'tradesCoveredNow': coveredNow,
  'needsSol': coveredNow == 0,
  'gaslessEligible': true,
  'blocker': blocker,
  'suggestion':
      blocker == null
          ? {
            'amountBaseUnits': suggestion,
            'estimatedLamports': '8470153',
            'tradesCovered': 4,
          }
          : null,
  'limits': {'minBaseUnits': '1000000', 'maxBaseUnits': '25000000'},
};

/// The server's view of the real Metis fixture, as `solTopUp.order` sends it.
Map<String, Object?> metisOrderJson({String feePayer = jupiterGasWallet}) => {
  'status': 'READY',
  'requestId': 'req-metis-0001',
  'transaction': kMetisSwapBase64,
  'expiresAt':
      DateTime.fromMillisecondsSinceEpoch(
        (kMetisBlockTime + 60) * 1000,
        isUtc: true,
      ).toIso8601String(),
  'review': {
    'wallet': kSwapOwner,
    'usdcInBaseUnits': '$kMetisInAmount',
    'solOutLamports': '$kMetisOutAmount',
    'solOutMinLamports': '105660949',
    'simulatedLamports': '106119149',
    'feeBps': kMetisFeeBps,
    'router': 'metis',
    'networkFeePaidBy': 'jupiter',
    'feePayer': feePayer,
    'tradesCovered': 62,
  },
};

class FakeTopUpBff {
  FakeTopUpBff() {
    client = MockClient((request) async {
      final procedure = request.url.path.split('/').last;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final input = (body['json'] as Map).cast<String, Object?>();
      calls.add((procedure, input, request.headers['authorization']));
      final handler = handlers[procedure];
      if (handler == null) throw StateError('Unexpected $procedure');
      return handler(input);
    });
    handlers.addAll({
      'solTopUp.status': (_) => trpcOk(status),
      'solTopUp.plan': (_) => trpcOk(plan),
      'solTopUp.order': (_) => trpcOk(order),
      'solTopUp.execute': (_) => trpcOk(execute),
    });
  }

  late final MockClient client;
  final calls = <(String, Map<String, Object?>, String?)>[];
  final handlers = <String, TopUpHandler>{};
  Map<String, Object?> status = topUpStatusJson();
  Map<String, Object?> plan = topUpPlanJson(suggestion: '$kMetisInAmount');
  Map<String, Object?> order = metisOrderJson();
  Map<String, Object?> execute = {
    'status': 'SUCCESS',
    'signature': '5' * 88,
    'usdcSpentBaseUnits': '$kMetisInAmount',
    'solReceivedLamports': '106119149',
  };

  Iterable<Map<String, Object?>> inputs(String procedure) =>
      calls.where((c) => c.$1 == 'solTopUp.$procedure').map((c) => c.$2);

  SolTopUpClient newClient() => SolTopUpClient(
    baseUri: Uri.parse('https://bff.invalid/trpc'),
    token: () => 'synthetic-session-token',
    client: client,
    timeout: const Duration(seconds: 2),
  );
}
