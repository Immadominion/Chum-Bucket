// Synthetic money BFF for tests. Every value here is test data: the signature
// slots are not cryptographic signatures and nothing touches a network. The
// shapes follow `docs/money-api.md` (money.*) and the existing pantaTrading.*
// contract the flows reuse.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/money/data/money_client.dart';
import 'package:chumbucket/features/money/domain/money_transfer_signer.dart';
import 'package:chumbucket/features/money/domain/usdc_transfer_check.dart';
import 'package:chumbucket/features/money/money_call_controller.dart';
import 'package:chumbucket/features/money/presentation/money_dependencies.dart';
import 'package:chumbucket/features/money/money_controller.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:solana/base58.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart'
    show Ed25519HDPublicKey, Signature, findAssociatedTokenAddress;

import 'bff_calls_fixtures.dart';

const viewerId = 'user_me';
const moneyCallId = '44444444-4444-4444-8444-444444444444';
const targetCallId = '55555555-5555-4555-8555-555555555555';
const pantaMarketId = '11111111-1111-5111-8111-111111111111';
const transferId = '66666666-6666-4666-8666-666666666666';
const claimId = '77777777-7777-4777-8777-777777777777';
const orderId = 'money-order-1';
const moneyNow = 1790686800000;

/// Quotes and claims that are still live whenever the suite runs.
final farFuture = DateTime.utc(2100).millisecondsSinceEpoch;

/// The signer's wallet: the fee payer key of [moneyUnsigned].
final signerWallet = base58encode(List.filled(32, 1));
final otherWallet = base58encode(List.filled(32, 6));
final venueMarket = base58encode(List.filled(32, 8));
final fillSignature = base58encode(List.filled(64, 9));

/// A structurally valid unsigned v0 transaction whose only signer is
/// [signerWallet] (the panta buy check is the signer port's job, faked here).
Uint8List moneyUnsigned() => Uint8List.fromList([
  1, ...List.filled(64, 0),
  128, 1, 0, 1,
  2, ...List.filled(32, 1), ...List.filled(32, 2),
  ...List.filled(32, 3),
  1, 1, 1, 0, 1, 7, 0,
]);

Uint8List moneySigned(Uint8List unsigned) =>
    Uint8List.fromList(unsigned)..fillRange(1, 65, 5);

Map<String, dynamic> pantaPriceJson() => {
  'id': '22222222-2222-5222-8222-222222222222',
  'marketId': pantaMarketId,
  'venue': 'panta',
  'currency': 'USDC',
  'unit': 'per_share',
  'yesPrice': '0.62',
  'noPrice': '0.38',
  'observedAt': kNowMs,
  'source': 'venue',
  'attribution': 'Powered by Panta',
  'executable': false,
};

Map<String, dynamic> pantaMarketJson() => {
  ...marketJson(id: pantaMarketId, venue: 'panta'),
  'venueMarketId': venueMarket,
};

/// A feed entry on the Panta market.
Map<String, dynamic> pantaEntryJson({
  String id = moneyCallId,
  String userId = viewerId,
  String side = 'YES',
  String? parentCallId,
  Map<String, dynamic>? money,
  Map<String, dynamic>? funding,
}) => {
  ...feedEntryJson(
    call: {
      ...callJson(
        id: id,
        userId: userId,
        marketId: pantaMarketId,
        side: side,
        entryProbability: null,
        snapshotId: null,
        parentCallId: parentCallId,
      ),
      'lockedAt': kNowMs,
      'createdAt': kNowMs,
      'entryPrice': pantaPriceJson(),
    },
    author: personJson(id: userId, handle: 'me', displayName: 'Me Myself'),
    market: pantaMarketJson(),
  ),
  if (money != null) 'money': money,
  if (funding != null) 'funding': funding,
};

Map<String, dynamic> moneyCallJson({
  String kind = 'own',
  String? target,
  String side = 'YES',
  String amount = '5000000',
  String state = 'PENDING',
  String trade = 'QUOTED',
  String? order = orderId,
  String? wallet,
  bool canRetry = false,
  bool canKeepFree = false,
  bool canDiscard = true,
}) => {
  'callId': moneyCallId,
  'kind': kind,
  'targetCallId': target ?? (kind == 'own' ? null : targetCallId),
  'marketId': pantaMarketId,
  'side': side,
  'amountBaseUnits': amount,
  'wallet': wallet ?? signerWallet,
  'state': state,
  'trade': trade,
  'orderId': order,
  'filledBaseUnits': state == 'FUNDED' ? amount : null,
  'createdAt': moneyNow,
  'updatedAt': moneyNow,
  'expiresAt': moneyNow + 600000,
  'canRetry': canRetry,
  'canKeepFree': canKeepFree,
  'canDiscard': canDiscard,
};

Map<String, dynamic> preparedTradeJson({
  String amount = '5000000',
  String side = 'YES',
  String? owner,
  String? market,
  int? expiresAt,
}) => _prepared(amount, side, owner, market, expiresAt ?? farFuture);

Map<String, dynamic> _prepared(
  String amount,
  String side,
  String? owner,
  String? market,
  int expiresAt,
) => {
  'order': {
    'orderId': orderId,
    'venue': 'panta',
    'venueMarketId': market ?? venueMarket,
    'owner': owner ?? signerWallet,
    'side': side,
    'amountBaseUnits': amount,
    'quotedProbability': null,
    'fundingState': 'QUOTED',
    'transaction': {
      'venue': 'panta',
      'encoding': 'solana-tx-base64',
      'payload': base64Encode(moneyUnsigned()),
      'expiresAt': expiresAt,
      'demo': false,
    },
    // The server's per-attempt trade key (MoneyCallsService.ts tradeKey).
    'idempotencyKey': '11111111-1111-4111-8111-111111111111.t1',
    'createdAt': moneyNow,
    'expiresAt': expiresAt,
    'demo': false,
  },
  'review': {
    'amountUsdc': _usdc(amount),
    'amountBaseUnits': amount,
    'expectedShares': '8.064516129032258064',
    'avgPrice': '0.62',
    'feeUsdc': '0.05',
    'maxSlippageBps': 100,
    'attribution': 'Powered by Panta',
  },
};

String _usdc(String units) {
  final value = BigInt.parse(units);
  final million = BigInt.from(1000000);
  final fraction = (value % million).toString().padLeft(6, '0');
  return '${value ~/ million}.$fraction';
}

Map<String, dynamic> readyJson({
  String kind = 'own',
  String side = 'YES',
  String amount = '5000000',
  String? owner,
  String? market,
  int? expiresAt,
}) => {
  'status': 'READY',
  'moneyCall': moneyCallJson(kind: kind, side: side, amount: amount),
  'call': pantaEntryJson(side: side, parentCallId: kind == 'own' ? null : targetCallId),
  'trade': preparedTradeJson(
    amount: amount,
    side: side,
    owner: owner,
    market: market,
    expiresAt: expiresAt,
  ),
};

Map<String, dynamic> needsFundsJson({
  String balance = '1000000',
  String needed = '5000000',
}) => {
  'status': 'NEEDS_FUNDS',
  'wallet': {'address': signerWallet, 'walletType': 'chumbucket'},
  'balanceBaseUnits': balance,
  'neededBaseUnits': needed,
  'shortfallBaseUnits':
      (BigInt.parse(needed) - BigInt.parse(balance)).toString(),
};

Map<String, dynamic> needsGasJson({String? topUp = '2000000'}) => {
  'status': 'NEEDS_GAS',
  'wallet': {'address': signerWallet, 'walletType': 'chumbucket'},
  'topUp': topUp == null ? null : {'amountBaseUnits': topUp},
};

Map<String, dynamic> callStatusJson({
  String state = 'PENDING',
  String trade = 'SUBMITTED',
  bool canRetry = false,
  bool canKeepFree = false,
  bool canDiscard = false,
}) => {
  'moneyCall': moneyCallJson(
    state: state,
    trade: trade,
    canRetry: canRetry,
    canKeepFree: canKeepFree,
    canDiscard: canDiscard,
  ),
  'order': null,
};

Map<String, dynamic> venueOrderJson({String state = 'SUBMITTED'}) => {
  'orderId': orderId,
  'venueOrderId': 'venue-1',
  'venue': 'panta',
  'venueMarketId': venueMarket,
  'owner': signerWallet,
  'side': 'YES',
  'amountBaseUnits': '5000000',
  'filledBaseUnits': state == 'FILLED' ? '5000000' : '0',
  'fundingState': state,
  'fillTxSignature': state == 'FILLED' ? fillSignature : null,
  'createdAt': moneyNow,
  'updatedAt': moneyNow + 1000,
  'idempotencyKey': '11111111-1111-4111-8111-111111111111.t1',
  'demo': false,
};

Map<String, dynamic> moneyStatusJson({
  bool enabled = true,
  String? defaultAmount = '5000000',
}) => {
  'enabled': enabled,
  'reason': enabled ? null : 'Off',
  'presetsBaseUnits': ['5000000', '10000000', '25000000'],
  'minBaseUnits': '1000000',
  'maxBaseUnits': '100000000',
  'defaultAmountBaseUnits': defaultAmount,
  'pendingTtlMs': 600000,
};

Map<String, dynamic> moneyWalletJson({
  String usdc = '12190000',
  String? address,
  bool noWallet = false,
}) => {
  'wallet':
      noWallet
          ? null
          : {'address': address ?? signerWallet, 'walletType': 'chumbucket'},
  'balance':
      noWallet
          ? null
          : {'usdcBaseUnits': usdc, 'lamports': '20000000', 'slot': 1},
  'gas': {'needsTopUp': false, 'topUp': null},
};

Map<String, dynamic> winningsJson({
  List<Map<String, dynamic>>? items,
  String total = '9200000',
}) => {
  'items':
      items ??
      [
        {
          'orderId': orderId,
          'callId': moneyCallId,
          'marketId': pantaMarketId,
          'question': 'Will BTC trade above 150k?',
          'side': 'YES',
          'wallet': signerWallet,
          'amountBaseUnits': total,
          'costBaseUnits': '5000000',
          'state': 'COLLECTABLE',
          'claimId': null,
        },
      ],
  'totalBaseUnits': total,
};

http.Response moneyOk(Object? data) => http.Response(
  jsonEncode({
    'result': {
      'data': {'json': data},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response moneyError(
  String code,
  String message, {
  int status = 400,
  String? reason,
}) => http.Response(
      jsonEncode({
        'error': {
          'json': {
            'message': message,
            'code': -32600,
            'data': {
              'code': code,
              'httpStatus': status,
              if (reason != null) 'details': {'reason': reason},
            },
          },
        },
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

typedef MoneyRoute = FutureOr<Object?> Function(Map<String, dynamic> input);

/// One in-memory BFF: each procedure answers from a queue of replies (the
/// last one repeats), and every request is recorded.
class FakeMoneyServer {
  final Map<String, List<Object>> _replies = {};
  final List<({String procedure, Map<String, dynamic> input, String? auth})>
  requests = [];

  /// Replies for [procedure], in order. An [http.Response] is sent as is; a
  /// [MoneyRoute] is called; anything else is wrapped as a tRPC result.
  void on(String procedure, List<Object> replies) =>
      _replies[procedure] = [...replies];

  List<Map<String, dynamic>> inputs(String procedure) => [
    for (final r in requests)
      if (r.procedure == procedure) r.input,
  ];

  int count(String procedure) => inputs(procedure).length;

  late final http.Client client = MockClient((request) async {
    final procedure = request.url.pathSegments.last;
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final input = (body['json'] as Map).cast<String, dynamic>();
    requests.add((
      procedure: procedure,
      input: input,
      auth: request.headers['authorization'],
    ));
    final queue = _replies[procedure];
    if (queue == null || queue.isEmpty) {
      return moneyError('NOT_FOUND', 'No such procedure in this fake.');
    }
    final reply = queue.length > 1 ? queue.removeAt(0) : queue.first;
    if (reply is http.Response) {
      return http.Response(
        reply.body,
        reply.statusCode,
        headers: reply.headers,
      );
    }
    if (reply is MoneyRoute) return moneyOk(await reply(input));
    return moneyOk(reply);
  });

  MoneyClient moneyClient() => MoneyClient(
    baseUri: Uri.parse('https://bff.test/trpc'),
    token: () => 'test-token',
    client: client,
  );

  PantaTradingClient tradingClient({String account = viewerId}) =>
      PantaTradingClient(
        baseUri: Uri.parse('https://bff.test/trpc'),
        session:
            () => PantaSession(accountId: account, accessToken: 'test-token'),
        client: client,
      );
}

/// A wallet port that signs by filling the slot (never a real signature),
/// and records what it was handed.
class FakeBuyPort implements PantaWalletPort {
  FakeBuyPort({this.cancel = false});
  final bool cancel;
  final List<Uint8List> signed = [];

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    if (cancel) throw const PantaWalletCancelled();
    signed.add(unsigned);
    return moneySigned(unsigned);
  }
}

class MemoryAmountMemory implements MoneyAmountMemory {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String accountId) async => values[accountId];
  @override
  Future<void> write(String accountId, String value) async =>
      values[accountId] = value;
}

/// A money controller bound to [viewerId] against [server].
Future<MoneyController> boundMoney(
  FakeMoneyServer server, {
  MoneyAmountMemory? memory,
}) async {
  final money = MoneyController(
    createClient: server.moneyClient,
    memory: memory ?? MemoryAmountMemory(),
    observeLifecycle: false,
  );
  await money.bind(viewerId);
  return money;
}

Map<String, dynamic> depositOptionsJson({
  bool card = false,
  bool testMode = false,
  bool fromWallet = true,
}) => {
  'tradingWallet': {'address': signerWallet, 'walletType': 'chumbucket'},
  'sendUsdc': {
    'address': signerWallet,
    'mint': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
    'network': 'solana-mainnet',
    'uri':
        'solana:$signerWallet?amount=4&spl-token='
        'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  },
  'card': {
    'available': card,
    'testMode': testMode,
    'reason': card ? null : 'Not live yet',
    'presetsUsd': card ? ['10', '25'] : <String>[],
    'limits': card ? {'minUsd': '5', 'maxUsd': '500'} : null,
  },
  'fromWallet': {
    'wallets': [
      if (fromWallet) {'address': otherWallet, 'walletType': 'mwa'},
    ],
  },
};

Map<String, dynamic> claimViewJson({String state = 'BUILT'}) => {
  'claimId': claimId,
  'orderId': orderId,
  'venueMarketId': venueMarket,
  'owner': signerWallet,
  'state': state,
  'signature': state == 'CONFIRMED' ? fillSignature : null,
  'payoutBaseUnits': state == 'CONFIRMED' ? '9200000' : null,
  'expiresAt': farFuture,
  'attribution': 'Powered by Panta',
};

Map<String, dynamic> claimPreparedJson() => {
  'claim': claimViewJson(),
  'transaction': {
    'venue': 'panta',
    'encoding': 'solana-tx-base64',
    'payload': base64Encode(moneyUnsigned()),
    'expiresAt': farFuture,
    'demo': false,
  },
  'review': {
    'outcome': 'YES',
    'winningShares': '9.2',
    'estimatedPayoutUsdc': '9.2',
    'attribution': 'Powered by Panta',
  },
};

Future<Uint8List> _passThroughCheck(
  Uint8List bytes,
  ExpectedUsdcTransfer expected,
) async => Uint8List.fromList(bytes.sublist(65));

/// Test doubles for every money seam: the fake BFF, a filling signer, and a
/// transfer signer that runs the real check before "signing".
MoneyDependencies fakeMoneyDeps(
  FakeMoneyServer server, {
  FakeBuyPort? port,
  FakeBuyPort? claimPort,
  RawTransferSign? transferSign,
  String? walletApp,
  Future<bool> Function()? openCard,
  Duration pollEvery = const Duration(seconds: 5),
  Future<Uint8List> Function(Uint8List, ExpectedUsdcTransfer)? checkTransfer,
  Future<bool> Function()? setUpWallet,
  Set<String>? phoneWallets,
}) => MoneyDependencies(
  createClient: server.moneyClient,
  createTradingClient: server.tradingClient,
  buySigner:
      (reviewed) => MoneyBuySigner(
        address: signerWallet,
        port: port ?? FakeBuyPort(),
        selectedWallet: () => signerWallet,
      ),
  transferSigner:
      (wallet) =>
          wallet == signerWallet || wallet == walletApp
              ? MoneyTransferSigner(
                address: wallet,
                // The real check derives USDC accounts with async crypto that
                // a widget test's fake clock can't run; its own unit test
                // (money_transfer_check_test) covers it byte by byte.
                check: checkTransfer ?? _passThroughCheck,
                sign:
                    transferSign ??
                    (_, _) async => Uint8List.fromList(List.filled(64, 4)),
              )
              : null,
  claimSigners: (wallet, intent) => claimPort ?? FakeBuyPort(),
  walletApp: () => walletApp,
  openCard:
      openCard == null
          ? null
          : (context, {shortfall, wallet}) => openCard(),
  setUpWallet: setUpWallet == null ? null : (_) => setUpWallet(),
  phoneWallets: () => phoneWallets ?? {signerWallet},
  pollEvery: pollEvery,
);

const _usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';

Ed25519HDPublicKey _pk(String b58) => Ed25519HDPublicKey.fromBase58(b58);

/// A cash-out transfer exactly as contract (c) builds it.
Future<String> transferPayload({
  required String from,
  required String to,
  int amount = 5000000,
  String? destinationOverride,
}) async {
  Future<String> ata(String owner) async =>
      (await findAssociatedTokenAddress(owner: _pk(owner), mint: _pk(_usdcMint)))
          .toBase58();
  final amountLe = List<int>.generate(8, (i) => (amount >> (8 * i)) & 0xff);
  final compiled = Message(
    instructions: [
      Instruction(
        programId: _pk(_token),
        accounts: [
          AccountMeta(pubKey: _pk(await ata(from)), isWriteable: true, isSigner: false),
          AccountMeta(pubKey: _pk(_usdcMint), isWriteable: false, isSigner: false),
          AccountMeta(
            pubKey: _pk(destinationOverride ?? await ata(to)),
            isWriteable: true,
            isSigner: false,
          ),
          AccountMeta(pubKey: _pk(from), isWriteable: false, isSigner: true),
        ],
        data: ByteArray([12, ...amountLe, 6]),
      ),
    ],
  ).compileV0(
    recentBlockhash: 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k',
    feePayer: _pk(from),
  );
  return base64Encode(
    SignedTx(
      compiledMessage: compiled,
      signatures: [Signature(List.filled(64, 0), publicKey: _pk(from))],
    ).toByteArray().toList(),
  );
}
