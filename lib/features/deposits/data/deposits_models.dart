/// Wire models for the BFF's `deposits.*` procedures (Crossmint onramp).
///
/// Parsing is strict about the things that matter — addresses, amounts as
/// integer base units, the checkout host — and tolerant of fields the server
/// may add later. A malformed answer is an error, never a guessed default.
library;

const usdcDecimals = 6;
const lamportsPerSol = 1000000000;

/// Crossmint's checkout pages are served from exactly these hosts. A checkout
/// URL pointing anywhere else is refused before it reaches a WebView.
const crossmintCheckoutHosts = {'staging.crossmint.com', 'www.crossmint.com'};
const crossmintCheckoutPath = '/sdk/2024-03-05/embedded-checkout';

enum DepositsErrorKind {
  signedOut,
  notLinked,
  unavailable,
  noWallet,
  forbidden,
  invalid,
  rateLimited,
  conflict,
  notFound,
  provider,
  connection,
  invalidResponse,
}

class DepositsException implements Exception {
  const DepositsException(this.kind, [this.serverMessage]);
  final DepositsErrorKind kind;

  /// The BFF's own copy (never provider text), when it sent one.
  final String? serverMessage;

  String get message =>
      serverMessage ??
      switch (kind) {
        DepositsErrorKind.signedOut => 'Sign in to add funds.',
        DepositsErrorKind.notLinked =>
          'Finish setting up your account to add funds.',
        DepositsErrorKind.unavailable =>
          'Adding funds isn\'t available right now.',
        DepositsErrorKind.noWallet => 'Connect a wallet to your account first.',
        DepositsErrorKind.forbidden =>
          'That wallet isn\'t connected to your account.',
        DepositsErrorKind.invalid => 'Check the amount and try again.',
        DepositsErrorKind.rateLimited =>
          'That\'s a lot of tries in a minute. Give it a moment.',
        DepositsErrorKind.conflict => 'This payment changed. Start a new one.',
        DepositsErrorKind.notFound => 'We couldn\'t find that payment.',
        DepositsErrorKind.provider =>
          'We couldn\'t reach our payment partner. Nothing was charged.',
        DepositsErrorKind.connection =>
          'You\'re offline or the connection dropped. Try again.',
        DepositsErrorKind.invalidResponse =>
          'Something didn\'t look right. Nothing was charged. Try again.',
      };

  @override
  String toString() => 'DepositsException(${kind.name})';
}

Never _bad() =>
    throw const DepositsException(DepositsErrorKind.invalidResponse);

T _as<T>(Object? value) => value is T ? value : _bad();
T? _opt<T>(Object? value) => value == null ? null : _as<T>(value);

final _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
final _decimal = RegExp(r'^[0-9]{1,12}(\.[0-9]{1,12})?$');
final _integer = RegExp(r'^[0-9]{1,30}$');

String _address(Object? value) {
  final s = _as<String>(value);
  if (!_base58.hasMatch(s)) _bad();
  return s;
}

String? _decimalOrNull(Object? value) {
  if (value == null) return null;
  final s = _as<String>(value);
  if (!_decimal.hasMatch(s)) _bad();
  return s;
}

/// A USD amount as whole cents. Two decimals at most; no floats anywhere.
class UsdAmount implements Comparable<UsdAmount> {
  const UsdAmount._(this.cents);
  final int cents;

  static UsdAmount? tryParse(String input) {
    final match = RegExp(
      r'^(0|[1-9][0-9]{0,5})(?:\.([0-9]{1,2}))?$',
    ).firstMatch(input.trim());
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = int.parse((match.group(2) ?? '').padRight(2, '0'));
    return UsdAmount._(whole * 100 + fraction);
  }

  factory UsdAmount.cents(int cents) {
    if (cents < 0) throw ArgumentError.value(cents, 'cents');
    return UsdAmount._(cents);
  }

  /// "25" or "25.50" — the wire form the BFF accepts.
  String get wire {
    final whole = cents ~/ 100;
    final fraction = cents % 100;
    return fraction == 0
        ? '$whole'
        : '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  /// "$25" or "$25.50".
  String get label => '\$$wire';

  @override
  int compareTo(UsdAmount other) => cents.compareTo(other.cents);

  bool operator <(UsdAmount other) => cents < other.cents;
  bool operator <=(UsdAmount other) => cents <= other.cents;
  bool operator >(UsdAmount other) => cents > other.cents;
  bool operator >=(UsdAmount other) => cents >= other.cents;

  @override
  bool operator ==(Object other) => other is UsdAmount && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;
}

/// Integer base units → a fixed-point string, trimmed to [maxDecimals].
String formatBaseUnits(
  BigInt units,
  int decimals, {
  int maxDecimals = 2,
  int minDecimals = 2,
}) {
  final negative = units.isNegative;
  final abs = units.abs();
  final scale = BigInt.from(10).pow(decimals);
  final whole = abs ~/ scale;
  var fraction = (abs % scale).toString().padLeft(decimals, '0');
  fraction = fraction.substring(0, maxDecimals.clamp(0, decimals));
  while (fraction.length > minDecimals && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  final grouped = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${negative ? '-' : ''}$grouped${fraction.isEmpty ? '' : '.$fraction'}';
}

/// "1.5" USDC → 1500000 base units. Digits past USDC's 6 decimals are
/// dropped (rounded down), so a displayed amount never overstates.
BigInt? usdcToBaseUnits(String decimal) {
  final match = RegExp(
    r'^([0-9]{1,12})(?:\.([0-9]{1,12}))?$',
  ).firstMatch(decimal);
  if (match == null) return null;
  var fraction = (match.group(2) ?? '').padRight(6, '0');
  fraction = fraction.substring(0, 6);
  return BigInt.parse(match.group(1)!) * BigInt.from(1000000) +
      BigInt.parse(fraction);
}

/// Two decimal USDC strings → "24.10–24.40", or "24.21" when they agree.
String? usdcRangeLabel(String? min, String? max) {
  if (min == null || max == null) return null;
  final lo = usdcToBaseUnits(min);
  final hi = usdcToBaseUnits(max);
  if (lo == null || hi == null) return null;
  final a = formatBaseUnits(lo, usdcDecimals);
  final b = formatBaseUnits(hi, usdcDecimals);
  return a == b ? a : '$a–$b';
}

/// "AbC1…xYz9": enough to recognise your own wallet, never the whole key.
String shortAddress(String address) =>
    address.length <= 10
        ? address
        : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

class DepositAccountWallet {
  const DepositAccountWallet({
    required this.address,
    required this.walletType,
    required this.primary,
    required this.session,
  });
  final String address;
  final String walletType;
  final bool primary;
  final bool session;

  factory DepositAccountWallet.fromJson(Map<String, dynamic> json) =>
      DepositAccountWallet(
        address: _address(json['address']),
        walletType: _as<String>(json['walletType']),
        primary: _as<bool>(json['primary']),
        session: _as<bool>(json['session']),
      );
}

class DepositsAccount {
  const DepositsAccount({
    required this.wallets,
    required this.receiptEmail,
    required this.needsEmail,
  });
  final List<DepositAccountWallet> wallets;

  /// Masked by the server ("ad•••@example.com").
  final String? receiptEmail;
  final bool needsEmail;

  factory DepositsAccount.fromJson(
    Map<String, dynamic> json,
  ) => DepositsAccount(
    wallets: _as<List<dynamic>>(json['wallets'])
        .map((w) => DepositAccountWallet.fromJson(_as<Map<String, dynamic>>(w)))
        .toList(growable: false),
    receiptEmail: _opt<String>(json['receiptEmail']),
    needsEmail: _as<bool>(json['needsEmail']),
  );
}

class DepositsStatus {
  const DepositsStatus({
    required this.available,
    required this.reasonCode,
    required this.reasonMessage,
    required this.environment,
    required this.deliveryNetwork,
    required this.minUsd,
    required this.maxUsd,
    required this.presets,
    required this.balanceAvailable,
    required this.account,
    required this.accountIssue,
  });

  final bool available;
  final String? reasonCode;
  final String? reasonMessage;

  /// `staging` | `production` | null when unavailable.
  final String? environment;

  /// `solana-devnet` | `solana-mainnet` | null.
  final String? deliveryNetwork;
  final UsdAmount? minUsd;
  final UsdAmount? maxUsd;
  final List<UsdAmount> presets;
  final bool balanceAvailable;
  final DepositsAccount? account;

  /// SIGNED_OUT | NOT_LINKED | UNAVAILABLE | null.
  final String? accountIssue;

  /// Crossmint staging: test cards, devnet test USDC.
  bool get isTestMode => environment == 'staging';

  factory DepositsStatus.fromJson(Map<String, dynamic> json) {
    final reason = _opt<Map<String, dynamic>>(json['reason']);
    final limits = _opt<Map<String, dynamic>>(json['limits']);
    UsdAmount amount(Object? v) => UsdAmount.tryParse(_as<String>(v)) ?? _bad();
    final account = _opt<Map<String, dynamic>>(json['account']);
    return DepositsStatus(
      available: _as<bool>(json['available']),
      reasonCode: reason == null ? null : _opt<String>(reason['code']),
      reasonMessage: reason == null ? null : _opt<String>(reason['message']),
      environment: _opt<String>(json['environment']),
      deliveryNetwork: _opt<String>(json['deliveryNetwork']),
      minUsd: limits == null ? null : amount(limits['minUsd']),
      maxUsd: limits == null ? null : amount(limits['maxUsd']),
      presets: _as<List<dynamic>>(
        json['presetsUsd'],
      ).map(amount).toList(growable: false),
      balanceAvailable: json['balanceAvailable'] == true,
      account: account == null ? null : DepositsAccount.fromJson(account),
      accountIssue: _opt<String>(json['accountIssue']),
    );
  }
}

class WalletBalance {
  const WalletBalance({
    required this.wallet,
    required this.lamports,
    required this.usdcBaseUnits,
    required this.slot,
    required this.readAt,
  });
  final String wallet;
  final BigInt lamports;
  final BigInt usdcBaseUnits;
  final int slot;
  final DateTime readAt;

  String get usdcLabel => formatBaseUnits(usdcBaseUnits, usdcDecimals);
  String get solLabel =>
      formatBaseUnits(lamports, 9, maxDecimals: 4, minDecimals: 2);

  /// No SOL at all. A Panta buy is paid for by its owner, so this wallet
  /// can't trade yet, and a card here only ever buys USDC.
  bool get hasNoSol => lamports == BigInt.zero;

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    if (json['network'] != 'solana-mainnet') _bad();
    final lamports = _as<String>(json['lamports']);
    final usdc = _as<String>(json['usdcBaseUnits']);
    if (!_integer.hasMatch(lamports) || !_integer.hasMatch(usdc)) _bad();
    return WalletBalance(
      wallet: _address(json['wallet']),
      lamports: BigInt.parse(lamports),
      usdcBaseUnits: BigInt.parse(usdc),
      slot: _as<num>(json['slot']).toInt(),
      readAt: DateTime.tryParse(_as<String>(json['readAt'])) ?? _bad(),
    );
  }
}

class DepositQuote {
  const DepositQuote({
    required this.amount,
    required this.totalUsd,
    required this.receiveMin,
    required this.receiveMax,
    required this.networkFeeUsd,
    required this.recipient,
    required this.deliveryNetwork,
  });
  final UsdAmount amount;
  final String? totalUsd;
  final String? receiveMin;
  final String? receiveMax;
  final String? networkFeeUsd;
  final String recipient;
  final String deliveryNetwork;

  /// "24.10–24.40" or "24.21", trimmed to cents for reading.
  String? get receiveLabel => usdcRangeLabel(receiveMin, receiveMax);

  factory DepositQuote.fromJson(Map<String, dynamic> json) {
    final range = _opt<Map<String, dynamic>>(json['receiveUsdc']);
    return DepositQuote(
      amount: UsdAmount.tryParse(_as<String>(json['amountUsd'])) ?? _bad(),
      totalUsd: _decimalOrNull(json['totalUsd']),
      receiveMin: range == null ? null : _decimalOrNull(range['min']),
      receiveMax: range == null ? null : _decimalOrNull(range['max']),
      networkFeeUsd: _decimalOrNull(json['networkFeeUsd']),
      recipient: _address(json['recipient']),
      deliveryNetwork: _as<String>(json['deliveryNetwork']),
    );
  }
}

enum DepositOrderState {
  awaitingWalletProof('awaiting_wallet_proof'),
  awaitingPayment('awaiting_payment'),
  verifyingIdentity('verifying_identity'),
  identityReview('identity_review'),
  identityFailed('identity_failed'),
  paymentProcessing('payment_processing'),
  paymentFailed('payment_failed'),
  delivering('delivering'),
  delivered('delivered'),
  deliveryFailed('delivery_failed'),
  expired('expired');

  const DepositOrderState(this.wire);
  final String wire;

  static DepositOrderState parse(Object? value) => DepositOrderState.values
      .firstWhere((s) => s.wire == value, orElse: () => _bad());

  bool get isTerminal => switch (this) {
    delivered || deliveryFailed || identityFailed || expired => true,
    _ => false,
  };

  /// Money has left the card and the order is past the person's hands.
  bool get isInFlight => this == paymentProcessing || this == delivering;

  /// Worth picking up on a later visit without its checkout page: money is
  /// moving, or Crossmint is reviewing and its answer is news. An order
  /// waiting for a wallet signature is not: nothing was charged, and once
  /// signed it could not be paid anyway, because its checkout link (the
  /// client secret) is never stored. A fresh order asks for the signature.
  bool get isWorthResuming => isInFlight || this == identityReview;
}

class DepositOrder {
  const DepositOrder({
    required this.orderId,
    required this.state,
    required this.totalUsd,
    required this.receiveMin,
    required this.receiveMax,
    required this.txId,
    required this.recipient,
    required this.deliveryNetwork,
    required this.failureCode,
    required this.failureMessage,
    required this.refundedUsd,
    required this.walletProofMessage,
  });

  final String orderId;
  final DepositOrderState state;
  final String? totalUsd;
  final String? receiveMin;
  final String? receiveMax;
  final String? txId;
  final String recipient;
  final String deliveryNetwork;
  final String? failureCode;
  final String? failureMessage;
  final String? refundedUsd;
  final String? walletProofMessage;

  bool get isDevnet => deliveryNetwork == 'solana-devnet';

  /// Exact once payment fixes it; a range before.
  String? get receiveLabel => usdcRangeLabel(receiveMin, receiveMax);

  Uri? get explorerUri =>
      txId == null
          ? null
          : Uri.https(
            'explorer.solana.com',
            '/tx/$txId',
            isDevnet ? {'cluster': 'devnet'} : null,
          );

  factory DepositOrder.fromJson(Map<String, dynamic> json) {
    final range = _opt<Map<String, dynamic>>(json['receiveUsdc']);
    final failure = _opt<Map<String, dynamic>>(json['failure']);
    final orderId = _as<String>(json['orderId']);
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(orderId)) _bad();
    final txId = _opt<String>(json['txId']);
    if (txId != null &&
        !RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,100}$').hasMatch(txId)) {
      _bad();
    }
    return DepositOrder(
      orderId: orderId,
      state: DepositOrderState.parse(json['state']),
      totalUsd: _decimalOrNull(json['totalUsd']),
      receiveMin: range == null ? null : _decimalOrNull(range['min']),
      receiveMax: range == null ? null : _decimalOrNull(range['max']),
      txId: txId,
      recipient: _address(json['recipient']),
      deliveryNetwork: _as<String>(json['deliveryNetwork']),
      failureCode: failure == null ? null : _opt<String>(failure['code']),
      failureMessage: failure == null ? null : _opt<String>(failure['message']),
      refundedUsd: _decimalOrNull(json['refundedUsd']),
      walletProofMessage: _opt<String>(json['walletProofMessage']),
    );
  }
}

class CreatedDeposit {
  const CreatedDeposit({required this.order, required this.checkoutUri});
  final DepositOrder order;
  final Uri checkoutUri;

  factory CreatedDeposit.fromJson(Map<String, dynamic> json) {
    final uri = Uri.tryParse(_as<String>(json['checkoutUrl'])) ?? _bad();
    if (!isCrossmintCheckoutUri(uri)) _bad();
    return CreatedDeposit(
      order: DepositOrder.fromJson(_as<Map<String, dynamic>>(json['order'])),
      checkoutUri: uri,
    );
  }
}

/// Defence in depth: only Crossmint's own embedded-checkout page may load.
bool isCrossmintCheckoutUri(Uri uri) =>
    uri.scheme == 'https' &&
    crossmintCheckoutHosts.contains(uri.host) &&
    !uri.hasPort &&
    uri.userInfo.isEmpty &&
    uri.path == crossmintCheckoutPath &&
    (uri.queryParameters['orderId']?.isNotEmpty ?? false) &&
    (uri.queryParameters['clientSecret']?.isNotEmpty ?? false) &&
    (uri.queryParameters['apiKey']?.startsWith('ck_') ?? false);
