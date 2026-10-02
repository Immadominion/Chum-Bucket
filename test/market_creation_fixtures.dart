/// A scripted `marketCreation.*` BFF at the HTTP level, so tests drive the
/// real [MarketCreationClient], transport and parsing. All data is synthetic:
/// no real person, market, wallet or Panta response.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/market_creation/market_creation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana/base58.dart';

const kTestBase = 'https://bff.synthetic.invalid';
final syntheticWallet = base58encode(List.filled(32, 1));
final otherWallet = base58encode(List.filled(32, 9));
final syntheticEvent = base58encode(List.filled(32, 3));
final hour = const Duration(hours: 1).inMilliseconds;

/// A one-signer v0 transaction paid by [payerByte]'s key, unsigned.
Uint8List syntheticCreateTx({int payerByte = 1, int dataByte = 7}) =>
    Uint8List.fromList([
      1, ...List.filled(64, 0), // one empty signature slot
      128, 1, 0, 1, // v0 prefix and header: 1 signer
      2, ...List.filled(32, payerByte), ...List.filled(32, 2), // keys
      ...List.filled(32, 4), // blockhash
      1, 1, 1, 0, 1, dataByte, // one instruction
      0, // no lookup tables
    ]);

Uint8List signedCopy(Uint8List unsigned) =>
    Uint8List.fromList(unsigned)..fillRange(1, 65, 5);

Map<String, Object?> rulesJson() => {
  'categories': [for (final c in MarketCategory.values) c.wire],
  'outcomes': ['YES', 'NO'],
  'questionMin': 10,
  'questionMax': 512,
  'rulesMin': 20,
  'rulesMax': 2048,
  'descriptionMax': 1000,
  'sourcesMax': 20,
  'sourceUrlMax': 512,
  'proposeMinLeadMs': 3 * hour,
  'publishMinLeadMs': 2 * hour,
  'maxHorizonMs': 730 * 24 * hour,
  'maxResolutionGapMs': 90 * 24 * hour,
};

Map<String, Object?> proposalJson({
  String id = '30000000-0000-4000-8000-000000000001',
  String status = 'pending_review',
  bool viewerIsProposer = true,
  bool canPublish = false,
  bool canWithdraw = true,
  Map<String, Object?>? review,
  Map<String, Object?>? live,
  String question = 'Will synthetic BTC close above 120,000 on 31 Dec 2026?',
  int? closesAt,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final close = closesAt ?? now + 72 * hour;
  return {
    'id': id,
    'question': question,
    'category': 'crypto',
    'outcomes': ['YES', 'NO'],
    'closesAt': close,
    'resolvesAt': close + hour,
    'rules':
        'Resolves YES if the synthetic source reports a close above 120,000.',
    'sources': ['https://example.com/btc'],
    'description': null,
    'status': status,
    'createdAt': now - hour,
    'updatedAt': now,
    'publishDeadline': close - 2 * hour,
    'proposer': {'id': 'person-1', 'handle': 'ada', 'displayName': 'Ada'},
    'viewerIsProposer': viewerIsProposer,
    'review': review,
    'canWithdraw': canWithdraw,
    'canPublish': canPublish,
    'publish':
        status == 'publishing'
            ? {'wallet': syntheticWallet, 'submittedAt': now}
            : null,
    'live': live,
    'attribution': 'Powered by Panta',
  };
}

Map<String, Object?> reviewJson({
  String proposalId = '30000000-0000-4000-8000-000000000001',
  String? wallet,
  Uint8List? tx,
  int? expiresAt,
  String fee = '50000000',
}) => {
  'sessionId': '40000000-0000-4000-8000-000000000001',
  'proposalId': proposalId,
  'wallet': wallet ?? syntheticWallet,
  'eventAddress': syntheticEvent,
  'feeBaseUnits': fee,
  'liquidityBaseUnits': '10000000',
  'platformBaseUnits': '${int.parse(fee) - 10000000}',
  'currency': 'USDC',
  'network': 'solana-mainnet',
  'transaction': base64Encode(tx ?? syntheticCreateTx()),
  'expiresAt': expiresAt ?? DateTime.now().millisecondsSinceEpoch + 60000,
  'closesAt': DateTime.now().millisecondsSinceEpoch + 72 * hour,
  'resolvesAt': DateTime.now().millisecondsSinceEpoch + 73 * hour,
  'attribution': 'Powered by Panta',
};

typedef Handler = Object? Function(Map<String, dynamic> input);

/// Answers tRPC calls by procedure; records every request.
class FakeMarketBff {
  final requests =
      <
        ({
          String method,
          String path,
          Map<String, dynamic> input,
          Map<String, String> headers,
        })
      >[];
  final handlers = <String, Handler>{};
  final errors = <String, ({String code, String message, int status})>{};
  bool offline = false;

  late final http.Client client = MockClient((request) async {
    if (offline) throw http.ClientException('synthetic offline');
    final path = request.url.path.replaceFirst('/', '');
    final Map<String, dynamic> input;
    if (request.method == 'GET') {
      final raw = request.url.queryParameters['input'];
      input =
          raw == null
              ? {}
              : (jsonDecode(raw)['json'] as Map).cast<String, dynamic>();
    } else {
      input = (jsonDecode(request.body)['json'] as Map).cast<String, dynamic>();
    }
    requests.add((
      method: request.method,
      path: path,
      input: input,
      headers: request.headers,
    ));
    final error = errors[path];
    if (error != null) {
      return http.Response(
        jsonEncode({
          'error': {
            'json': {
              'message': error.message,
              'data': {'code': error.code, 'httpStatus': error.status},
            },
          },
        }),
        error.status,
      );
    }
    final handler = handlers[path];
    if (handler == null) {
      return http.Response('{"error":{"json":{"message":"no route"}}}', 404);
    }
    return http.Response(
      jsonEncode({
        'result': {
          'data': {'json': handler(input)},
        },
      }),
      200,
    );
  });

  MarketCreationClient marketClient({String? token = 'synthetic-session'}) =>
      MarketCreationClient(
        transport: CallsBffTransport(
          baseUrl: kTestBase,
          httpClient: client,
          authToken: () => token,
          verbose: false,
        ),
      );

  List<String> paths() => [for (final r in requests) r.path];

  void status({
    bool proposals = true,
    bool publishing = true,
    bool reviewer = false,
    String? reason,
  }) {
    handlers['marketCreation.status'] =
        (_) => {
          'proposalsEnabled': proposals,
          'publishingEnabled': publishing,
          'reason': reason,
          'viewerIsReviewer': reviewer,
          'maxFeeBaseUnits': '100000000',
          'rules': rulesJson(),
          'attribution': 'Powered by Panta',
        };
  }
}
