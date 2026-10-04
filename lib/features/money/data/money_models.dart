/// The `money.*` contract (`docs/money-api.md` in the API), parsed strictly.
///
/// Money is integers on the wire (USDC base units, 6 decimals, as decimal
/// strings) and dollars on screen. A shape that is not what the contract says
/// is a [MoneyException] of kind [MoneyErrorKind.invalidResponse], never a
/// silent default: nothing here invents or estimates an amount.
library;

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart'
    show callFeedEntryFromJson;
import 'package:chumbucket/features/calls/data/calls_repository.dart'
    show CallFeedEntry;
import 'package:chumbucket/features/panta_trading/panta_trading.dart'
    show PantaMoney, PantaPreparedTrade, PantaVenueOrder, validatePantaWallet;

enum MoneyErrorKind {
  signedOut,
  forbidden,

  /// `MONEY_CALLS_ENABLED` off, trading paused, market not taking calls, or
  /// the money call is not in a state that allows this.
  unavailable,
  notFound,

  /// An order is still going through, or a key was reused differently.
  conflict,
  invalid,
  walletNotLinked,
  rateLimited,

  /// The database, Panta or the RPC could not answer; nothing was charged.
  provider,
  connection,
  invalidResponse,
}

/// The server's own short copy when it sent one, else fixed local copy.
class MoneyException implements Exception {
  const MoneyException(this.kind, [this.serverMessage]);
  final MoneyErrorKind kind;
  final String? serverMessage;

  String get message =>
      serverMessage ??
      switch (kind) {
        MoneyErrorKind.signedOut => 'Sign in to use money.',
        MoneyErrorKind.forbidden => 'Finish setting up your account first.',
        MoneyErrorKind.unavailable => 'Not available right now.',
        MoneyErrorKind.notFound => 'That’s gone.',
        MoneyErrorKind.conflict => 'Still going through.',
        MoneyErrorKind.invalid => 'Check the amount and try again.',
        MoneyErrorKind.walletNotLinked => 'Link this wallet first.',
        MoneyErrorKind.rateLimited => 'Too many tries. Wait a moment.',
        MoneyErrorKind.provider => 'Couldn’t reach Solana. Nothing was charged.',
        MoneyErrorKind.connection => 'No answer. Try again.',
        MoneyErrorKind.invalidResponse => 'Something didn’t check out.',
      };

  @override
  String toString() => 'MoneyException(${kind.name})';
}

Never _invalid() =>
    throw const MoneyException(MoneyErrorKind.invalidResponse);

void _expect(bool condition) {
  if (!condition) _invalid();
}

Map<String, dynamic> moneyObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return _invalid();
}

String _string(Map<String, dynamic> json, String key, {int max = 4096}) {
  final value = json[key];
  return value is String && value.isNotEmpty && value.length <= max
      ? value
      : _invalid();
}

String? _nullableString(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _string(json, key);

int _ms(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  if (value is num && value >= 0 && value == value.roundToDouble()) {
    return value.toInt();
  }
  return _invalid();
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is bool ? value : _invalid();
}

final _baseUnitsPattern = RegExp(r'^(0|[1-9][0-9]{0,19})$');

/// USDC base units as the wire carries them: a decimal integer string.
BigInt moneyBaseUnits(Object? value) {
  if (value is! String || !_baseUnitsPattern.hasMatch(value)) _invalid();
  return BigInt.parse(value);
}

BigInt _units(Map<String, dynamic> json, String key) => moneyBaseUnits(json[key]);

BigInt? _nullableUnits(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _units(json, key);

String _wallet(Map<String, dynamic> json, String key) {
  final value = _string(json, key, max: 64);
  try {
    validatePantaWallet(value);
  } catch (_) {
    _invalid();
  }
  return value;
}

Side _side(Object? value) => switch (value) {
  'YES' => Side.yes,
  'NO' => Side.no,
  _ => _invalid(),
};

Side? _nullableSide(Object? value) => value == null ? null : _side(value);

CallFeedEntry _entry(Object? value) {
  try {
    return callFeedEntryFromJson(moneyObject(value));
  } on MoneyException {
    rethrow;
  } catch (_) {
    return _invalid();
  }
}

/// Money as dollars, exactly: `$5`, `$12.19`.
String moneyDollars(BigInt baseUnits, {bool signed = false}) =>
    PantaMoney.dollars(baseUnits, signed: signed);

/// Whole dollars and cents for a person's own entry ("12", "12.5", "12.50"):
/// base units, or null when it is not a positive amount in whole cents.
BigInt? parseDollarAmount(String text) {
  final trimmed = text.trim().replaceFirst(RegExp(r'^\$'), '');
  final match = RegExp(r'^([0-9]{1,9})(?:\.([0-9]{0,2}))?$').firstMatch(trimmed);
  if (match == null) return null;
  final cents = (match.group(2) ?? '').padRight(2, '0');
  final units =
      BigInt.parse(match.group(1)!) * BigInt.from(1000000) +
      BigInt.parse(cents) * BigInt.from(10000);
  return units > BigInt.zero ? units : null;
}

/// `"$5 on YES"`: what a filled call carries on cards and receipts.
String moneyOnSide(BigInt baseUnits, Side side) =>
    '${moneyDollars(baseUnits)} on ${side.wire}';

// ---------------------------------------------------------------------------
// money.status
// ---------------------------------------------------------------------------

class MoneyStatus {
  const MoneyStatus({
    required this.enabled,
    required this.reason,
    required this.presets,
    required this.minBaseUnits,
    required this.maxBaseUnits,
    required this.defaultAmountBaseUnits,
    required this.pendingTtlMs,
  });

  final bool enabled;

  /// Why not, in words. Never shown as a banner: off means hidden.
  final String? reason;
  final List<BigInt> presets;
  final BigInt minBaseUnits;
  final BigInt? maxBaseUnits;

  /// Signed in: the last amount used on the server, else `$5`.
  final BigInt? defaultAmountBaseUnits;
  final int pendingTtlMs;

  static final disabled = MoneyStatus(
    enabled: false,
    reason: null,
    presets: const [],
    minBaseUnits: BigInt.from(1000000),
    maxBaseUnits: null,
    defaultAmountBaseUnits: null,
    pendingTtlMs: 0,
  );

  factory MoneyStatus.fromJson(Object? value) {
    final json = moneyObject(value);
    final presets = json['presetsBaseUnits'];
    _expect(presets is List);
    return MoneyStatus(
      enabled: _bool(json, 'enabled'),
      reason: _nullableString(json, 'reason'),
      presets: [for (final p in presets as List) moneyBaseUnits(p)],
      minBaseUnits: _units(json, 'minBaseUnits'),
      maxBaseUnits: _nullableUnits(json, 'maxBaseUnits'),
      defaultAmountBaseUnits: _nullableUnits(json, 'defaultAmountBaseUnits'),
      pendingTtlMs: _ms(json, 'pendingTtlMs'),
    );
  }
}

// ---------------------------------------------------------------------------
// Calls with an amount
// ---------------------------------------------------------------------------

enum MoneyCallKind {
  own('own'),
  back('back'),
  fade('fade');

  const MoneyCallKind(this.wire);
  final String wire;
}

enum MoneyCallState {
  pending('PENDING'),
  funded('FUNDED'),
  free('FREE'),
  expired('EXPIRED');

  const MoneyCallState(this.wire);
  final String wire;

  static MoneyCallState fromWire(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: _invalid);
}

enum MoneyTradeState {
  none('NONE'),
  quoted('QUOTED'),
  submitted('SUBMITTED'),
  filled('FILLED'),
  failed('FAILED');

  const MoneyTradeState(this.wire);
  final String wire;

  static MoneyTradeState fromWire(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: _invalid);
}

class MoneyCallView {
  const MoneyCallView({
    required this.callId,
    required this.kind,
    required this.targetCallId,
    required this.marketId,
    required this.side,
    required this.amountBaseUnits,
    required this.wallet,
    required this.state,
    required this.trade,
    required this.orderId,
    required this.filledBaseUnits,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.canRetry,
    required this.canKeepFree,
    required this.canDiscard,
  });

  final String callId;
  final MoneyCallKind kind;
  final String? targetCallId;
  final String marketId;
  final Side side;
  final BigInt amountBaseUnits;
  final String wallet;
  final MoneyCallState state;
  final MoneyTradeState trade;
  final String? orderId;

  /// Set only when [state] is FUNDED.
  final BigInt? filledBaseUnits;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;
  final bool canRetry;
  final bool canKeepFree;
  final bool canDiscard;

  bool get isFunded => state == MoneyCallState.funded;
  bool get isPending => state == MoneyCallState.pending;

  factory MoneyCallView.fromJson(Object? value) {
    final json = moneyObject(value);
    final kind = switch (json['kind']) {
      'own' => MoneyCallKind.own,
      'back' => MoneyCallKind.back,
      'fade' => MoneyCallKind.fade,
      _ => _invalid(),
    };
    final state = MoneyCallState.fromWire(json['state']);
    final filled = _nullableUnits(json, 'filledBaseUnits');
    // Only a funded call carries a fill (and may not, when the server could
    // not read its amount: then it reads "Funded", never an invented one).
    _expect(filled == null || state == MoneyCallState.funded);
    final target = _nullableString(json, 'targetCallId');
    _expect((kind == MoneyCallKind.own) == (target == null));
    final amount = _units(json, 'amountBaseUnits');
    _expect(amount > BigInt.zero);
    return MoneyCallView(
      callId: _string(json, 'callId', max: 256),
      kind: kind,
      targetCallId: target,
      marketId: _string(json, 'marketId', max: 256),
      side: _side(json['side']),
      amountBaseUnits: amount,
      wallet: _wallet(json, 'wallet'),
      state: state,
      trade: MoneyTradeState.fromWire(json['trade']),
      orderId: _nullableString(json, 'orderId'),
      filledBaseUnits: filled,
      createdAt: _ms(json, 'createdAt'),
      updatedAt: _ms(json, 'updatedAt'),
      expiresAt: _ms(json, 'expiresAt'),
      canRetry: _bool(json, 'canRetry'),
      canKeepFree: _bool(json, 'canKeepFree'),
      canDiscard: _bool(json, 'canDiscard'),
    );
  }
}

class MoneyWalletRef {
  const MoneyWalletRef({required this.address, required this.walletType});
  final String address;
  final String walletType;

  factory MoneyWalletRef.fromJson(Object? value) {
    final json = moneyObject(value);
    return MoneyWalletRef(
      address: _wallet(json, 'address'),
      walletType: _string(json, 'walletType', max: 64),
    );
  }

  static MoneyWalletRef? nullable(Object? value) =>
      value == null ? null : MoneyWalletRef.fromJson(value);
}

/// `money.prepareCall` / `money.retry`.
sealed class MoneyPrepareResult {
  const MoneyPrepareResult();

  factory MoneyPrepareResult.fromJson(Object? value, {bool allowSettled = true}) {
    final json = moneyObject(value);
    switch (json['status']) {
      case 'NEEDS_FUNDS':
        final balance = _units(json, 'balanceBaseUnits');
        final needed = _units(json, 'neededBaseUnits');
        final shortfall = _units(json, 'shortfallBaseUnits');
        _expect(shortfall > BigInt.zero && needed > balance);
        return MoneyNeedsFunds(
          wallet: MoneyWalletRef.fromJson(json['wallet']),
          balanceBaseUnits: balance,
          neededBaseUnits: needed,
          shortfallBaseUnits: shortfall,
        );
      case 'NEEDS_GAS':
        return MoneyNeedsGas(
          wallet: MoneyWalletRef.fromJson(json['wallet']),
          topUpBaseUnits: _topUp(json['topUp']),
        );
      case 'READY':
        final trade = moneyObject(json['trade']);
        final PantaPreparedTrade prepared;
        try {
          prepared = PantaPreparedTrade.fromJson(trade);
        } catch (_) {
          return _invalid();
        }
        return MoneyReady(
          moneyCall: MoneyCallView.fromJson(json['moneyCall']),
          call: _entry(json['call']),
          trade: prepared,
        );
      case 'SETTLED' when allowSettled:
        return MoneySettled(
          moneyCall: MoneyCallView.fromJson(json['moneyCall']),
          call: _entry(json['call']),
        );
      default:
        return _invalid();
    }
  }
}

BigInt? _topUp(Object? value) {
  if (value == null) return null;
  final amount = _units(moneyObject(value), 'amountBaseUnits');
  _expect(amount > BigInt.zero);
  return amount;
}

class MoneyNeedsFunds extends MoneyPrepareResult {
  const MoneyNeedsFunds({
    required this.wallet,
    required this.balanceBaseUnits,
    required this.neededBaseUnits,
    required this.shortfallBaseUnits,
  });
  final MoneyWalletRef wallet;
  final BigInt balanceBaseUnits;
  final BigInt neededBaseUnits;
  final BigInt shortfallBaseUnits;
}

class MoneyNeedsGas extends MoneyPrepareResult {
  const MoneyNeedsGas({required this.wallet, required this.topUpBaseUnits});
  final MoneyWalletRef wallet;

  /// The gasless USDC→SOL swap to run first; null when this server has none.
  final BigInt? topUpBaseUnits;
}

class MoneyReady extends MoneyPrepareResult {
  const MoneyReady({
    required this.moneyCall,
    required this.call,
    required this.trade,
  });
  final MoneyCallView moneyCall;
  final CallFeedEntry call;
  final PantaPreparedTrade trade;
}

class MoneySettled extends MoneyPrepareResult {
  const MoneySettled({required this.moneyCall, required this.call});
  final MoneyCallView moneyCall;
  final CallFeedEntry call;
}

/// `money.callStatus`.
class MoneyCallStatus {
  const MoneyCallStatus({required this.moneyCall, required this.order});
  final MoneyCallView moneyCall;
  final PantaVenueOrder? order;

  factory MoneyCallStatus.fromJson(Object? value) {
    final json = moneyObject(value);
    _expect(json.containsKey('order'));
    PantaVenueOrder? order;
    if (json['order'] != null) {
      try {
        order = PantaVenueOrder.fromJson(json['order']);
      } catch (_) {
        _invalid();
      }
    }
    return MoneyCallStatus(
      moneyCall: MoneyCallView.fromJson(json['moneyCall']),
      order: order,
    );
  }
}

/// `money.keepFree` / `money.pending` rows.
class MoneyCallWithEntry {
  const MoneyCallWithEntry({required this.moneyCall, required this.call});
  final MoneyCallView moneyCall;
  final CallFeedEntry call;

  factory MoneyCallWithEntry.fromJson(Object? value) {
    final json = moneyObject(value);
    return MoneyCallWithEntry(
      moneyCall: MoneyCallView.fromJson(json['moneyCall']),
      call: _entry(json['call']),
    );
  }
}

// ---------------------------------------------------------------------------
// The wallet sheet
// ---------------------------------------------------------------------------

class MoneyWalletInfo {
  const MoneyWalletInfo({
    required this.wallet,
    required this.usdcBaseUnits,
    required this.lamports,
    required this.needsTopUp,
    required this.topUpBaseUnits,
  });

  /// The trading wallet; null when the account has none yet.
  final MoneyWalletRef? wallet;

  /// The balance; null with no wallet.
  final BigInt? usdcBaseUnits;
  final BigInt? lamports;
  final bool needsTopUp;
  final BigInt? topUpBaseUnits;

  factory MoneyWalletInfo.fromJson(Object? value) {
    final json = moneyObject(value);
    final wallet = MoneyWalletRef.nullable(json['wallet']);
    final balance =
        json['balance'] == null ? null : moneyObject(json['balance']);
    // Null: no wallet yet, or fees could not be checked just now.
    final gas = json['gas'] == null ? null : moneyObject(json['gas']);
    _expect((wallet == null) == (balance == null));
    return MoneyWalletInfo(
      wallet: wallet,
      usdcBaseUnits: balance == null ? null : _units(balance, 'usdcBaseUnits'),
      lamports: balance == null ? null : _units(balance, 'lamports'),
      needsTopUp: gas == null ? false : _bool(gas, 'needsTopUp'),
      topUpBaseUnits: gas == null ? null : _topUp(gas['topUp']),
    );
  }
}

enum MoneyActivityKind { trade, claim, deposit, cashOut }

enum MoneyActivityState { pending, done, failed }

class MoneyActivityItem {
  const MoneyActivityItem({
    required this.id,
    required this.kind,
    required this.incoming,
    required this.amountBaseUnits,
    required this.state,
    required this.at,
    required this.signature,
    required this.callId,
    required this.side,
    required this.question,
    required this.counterparty,
  });

  final String id;
  final MoneyActivityKind kind;
  final bool incoming;
  final BigInt amountBaseUnits;
  final MoneyActivityState state;
  final int at;
  final String? signature;
  final String? callId;
  final Side? side;
  final String? question;
  final String? counterparty;

  factory MoneyActivityItem.fromJson(Object? value) {
    final json = moneyObject(value);
    return MoneyActivityItem(
      id: _string(json, 'id', max: 256),
      kind: switch (json['kind']) {
        'trade' => MoneyActivityKind.trade,
        'claim' => MoneyActivityKind.claim,
        'deposit' => MoneyActivityKind.deposit,
        'cash_out' => MoneyActivityKind.cashOut,
        _ => _invalid(),
      },
      incoming: switch (json['direction']) {
        'in' => true,
        'out' => false,
        _ => _invalid(),
      },
      amountBaseUnits: _units(json, 'amountBaseUnits'),
      state: switch (json['state']) {
        'pending' => MoneyActivityState.pending,
        'done' => MoneyActivityState.done,
        'failed' => MoneyActivityState.failed,
        _ => _invalid(),
      },
      at: _ms(json, 'at'),
      signature: _nullableString(json, 'signature'),
      callId: _nullableString(json, 'callId'),
      side: _nullableSide(json['side']),
      question: _nullableString(json, 'question'),
      counterparty: _nullableString(json, 'counterparty'),
    );
  }

  static List<MoneyActivityItem> listFromJson(Object? value) {
    final json = moneyObject(value);
    final items = json['items'];
    _expect(items is List);
    return [for (final item in items as List) MoneyActivityItem.fromJson(item)];
  }
}

// ---------------------------------------------------------------------------
// Transfers: cash out, and a top-up from one of your own wallets
// ---------------------------------------------------------------------------

class TransferReview {
  const TransferReview({
    required this.from,
    required this.to,
    required this.amountBaseUnits,
    required this.createsAccount,
  });
  final String from;
  final String to;
  final BigInt amountBaseUnits;

  /// The destination's USDC account is created (paid by [from], in SOL).
  final bool createsAccount;

  factory TransferReview.fromJson(Object? value) {
    final json = moneyObject(value);
    // SOL `from` pays; read for shape only, never shown as money.
    _units(json, 'networkFeeLamports');
    _units(json, 'rentLamports');
    final amount = _units(json, 'amountBaseUnits');
    _expect(amount > BigInt.zero);
    return TransferReview(
      from: _wallet(json, 'from'),
      to: _wallet(json, 'to'),
      amountBaseUnits: amount,
      createsAccount: _bool(json, 'createsAccount'),
    );
  }
}

enum TransferState { built, submitted, confirmed, failed }

class TransferView {
  const TransferView({
    required this.transferId,
    required this.isCashOut,
    required this.from,
    required this.to,
    required this.amountBaseUnits,
    required this.state,
    required this.signature,
    required this.expiresAt,
  });
  final String transferId;
  final bool isCashOut;
  final String from;
  final String to;
  final BigInt amountBaseUnits;
  final TransferState state;
  final String? signature;
  final int expiresAt;

  bool get settled =>
      state == TransferState.confirmed || state == TransferState.failed;

  factory TransferView.fromJson(Object? value) {
    final json = moneyObject(value);
    final id = _string(json, 'transferId', max: 64);
    _expect(_uuid.hasMatch(id));
    _ms(json, 'createdAt');
    _ms(json, 'updatedAt');
    return TransferView(
      transferId: id,
      isCashOut: switch (json['kind']) {
        'cash_out' => true,
        'deposit' => false,
        _ => _invalid(),
      },
      from: _wallet(json, 'from'),
      to: _wallet(json, 'to'),
      amountBaseUnits: _units(json, 'amountBaseUnits'),
      state: switch (json['state']) {
        'BUILT' => TransferState.built,
        'SUBMITTED' => TransferState.submitted,
        'CONFIRMED' => TransferState.confirmed,
        'FAILED' => TransferState.failed,
        _ => _invalid(),
      },
      signature: _nullableString(json, 'signature'),
      expiresAt: _ms(json, 'expiresAt'),
    );
  }
}

const _usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

sealed class TransferPrepareResult {
  const TransferPrepareResult();

  factory TransferPrepareResult.fromJson(Object? value) {
    final json = moneyObject(value);
    switch (json['status']) {
      case 'INVALID':
        return TransferInvalid(
          reason: _string(json, 'reason', max: 64),
          message: _string(json, 'message', max: 240),
        );
      case 'NEEDS_GAS':
        return TransferNeedsGas(
          wallet: MoneyWalletRef.fromJson(json['wallet']),
          topUpBaseUnits: _topUp(json['topUp']),
        );
      case 'READY':
        final transaction = moneyObject(json['transaction']);
        _expect(transaction['encoding'] == 'solana-tx-base64');
        final transfer = TransferView.fromJson(json['transfer']);
        final review = TransferReview.fromJson(json['review']);
        _expect(
          transfer.from == review.from &&
              transfer.to == review.to &&
              transfer.amountBaseUnits == review.amountBaseUnits,
        );
        return TransferReady(
          transfer: transfer,
          payload: _string(transaction, 'payload', max: 1644),
          expiresAt: _ms(transaction, 'expiresAt'),
          review: review,
        );
      default:
        return _invalid();
    }
  }
}

class TransferInvalid extends TransferPrepareResult {
  const TransferInvalid({required this.reason, required this.message});
  final String reason;

  /// The server's own words ("That's a token account, not a wallet.").
  final String message;
}

class TransferNeedsGas extends TransferPrepareResult {
  const TransferNeedsGas({required this.wallet, required this.topUpBaseUnits});
  final MoneyWalletRef wallet;
  final BigInt? topUpBaseUnits;
}

class TransferReady extends TransferPrepareResult {
  const TransferReady({
    required this.transfer,
    required this.payload,
    required this.expiresAt,
    required this.review,
  });
  final TransferView transfer;
  final String payload;
  final int expiresAt;
  final TransferReview review;
}

// ---------------------------------------------------------------------------
// Winnings
// ---------------------------------------------------------------------------

class MoneyWinning {
  const MoneyWinning({
    required this.orderId,
    required this.callId,
    required this.marketId,
    required this.question,
    required this.side,
    required this.wallet,
    required this.amountBaseUnits,
    required this.costBaseUnits,
    required this.collecting,
    required this.claimId,
  });
  final String orderId;
  final String callId;
  final String marketId;
  final String? question;
  final Side side;
  final String wallet;

  /// What collecting pays: the winning shares at $1.
  final BigInt amountBaseUnits;
  final BigInt costBaseUnits;
  final bool collecting;
  final String? claimId;

  factory MoneyWinning.fromJson(Object? value) {
    final json = moneyObject(value);
    final collecting = switch (json['state']) {
      'COLLECTABLE' => false,
      'COLLECTING' => true,
      _ => _invalid(),
    };
    final claimId = _nullableString(json, 'claimId');
    if (claimId != null) _expect(_uuid.hasMatch(claimId));
    return MoneyWinning(
      orderId: _string(json, 'orderId', max: 128),
      callId: _string(json, 'callId', max: 256),
      marketId: _string(json, 'marketId', max: 256),
      question: _nullableString(json, 'question'),
      side: _side(json['side']),
      wallet: _wallet(json, 'wallet'),
      amountBaseUnits: _units(json, 'amountBaseUnits'),
      costBaseUnits: _units(json, 'costBaseUnits'),
      collecting: collecting,
      claimId: claimId,
    );
  }
}

class MoneyWinnings {
  const MoneyWinnings({required this.items, required this.totalBaseUnits});
  final List<MoneyWinning> items;

  /// COLLECTABLE items only.
  final BigInt totalBaseUnits;

  static final empty = MoneyWinnings(items: const [], totalBaseUnits: BigInt.zero);

  MoneyWinning? forCall(String callId) {
    for (final item in items) {
      if (item.callId == callId) return item;
    }
    return null;
  }

  factory MoneyWinnings.fromJson(Object? value) {
    final json = moneyObject(value);
    final items = json['items'];
    _expect(items is List);
    return MoneyWinnings(
      items: [for (final item in items as List) MoneyWinning.fromJson(item)],
      totalBaseUnits: _units(json, 'totalBaseUnits'),
    );
  }
}

// ---------------------------------------------------------------------------
// Deposit options
// ---------------------------------------------------------------------------

class SendUsdcOption {
  const SendUsdcOption({
    required this.address,
    required this.mint,
    required this.uri,
  });
  final String address;
  final String mint;

  /// Solana Pay transfer request, for the QR.
  final String uri;
}

class CardOption {
  const CardOption({
    required this.available,
    required this.testMode,
    required this.presetsUsd,
  });
  final bool available;

  /// Staging, for admins only: says "Test" every time it shows.
  final bool testMode;
  final List<String> presetsUsd;
}

class DepositOptions {
  const DepositOptions({
    required this.tradingWallet,
    required this.sendUsdc,
    required this.card,
    required this.fromWallets,
  });
  final MoneyWalletRef? tradingWallet;
  final SendUsdcOption? sendUsdc;
  final CardOption card;

  /// The account's own proven wallets except the trading wallet.
  final List<MoneyWalletRef> fromWallets;

  factory DepositOptions.fromJson(Object? value) {
    final json = moneyObject(value);
    final send = json['sendUsdc'] == null ? null : moneyObject(json['sendUsdc']);
    SendUsdcOption? sendUsdc;
    if (send != null) {
      _expect(send['network'] == 'solana-mainnet');
      final address = _wallet(send, 'address');
      final mint = _wallet(send, 'mint');
      final uri = _string(send, 'uri', max: 512);
      // The QR pays exactly the address shown, in mainnet USDC, nothing else.
      final parsed = Uri.tryParse(uri);
      _expect(
        mint == _usdcMint &&
            parsed != null &&
            parsed.scheme == 'solana' &&
            parsed.path == address &&
            parsed.queryParameters['spl-token'] == mint &&
            parsed.queryParameters.keys.every(
              (key) => key == 'spl-token' || key == 'amount',
            ),
      );
      sendUsdc = SendUsdcOption(address: address, mint: mint, uri: uri);
    }
    final card = moneyObject(json['card']);
    final presets = card['presetsUsd'];
    _expect(presets is List && presets.every((p) => p is String));
    final from = moneyObject(json['fromWallet'])['wallets'];
    _expect(from is List);
    return DepositOptions(
      tradingWallet: MoneyWalletRef.nullable(json['tradingWallet']),
      sendUsdc: sendUsdc,
      card: CardOption(
        available: _bool(card, 'available'),
        testMode: _bool(card, 'testMode'),
        presetsUsd: (presets as List).cast<String>(),
      ),
      fromWallets: [for (final w in from as List) MoneyWalletRef.fromJson(w)],
    );
  }
}
