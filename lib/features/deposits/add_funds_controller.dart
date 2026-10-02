import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/deposit_order_memory.dart';
import 'data/deposits_client.dart';
import 'data/deposits_models.dart';
import 'domain/deposit_wallet_source.dart';

/// Where the Add funds journey is.
enum AddFundsStage {
  loading,
  signedOut,

  /// Deposits are off, the account can't be read, or it has no wallet. The
  /// sheet still shows the balance and the "send from another wallet" path.
  unavailable,
  choose,
  starting,

  /// Crossmint's checkout is (or is about to be) on screen.
  checkout,

  /// The checkout closed before a final answer; we keep checking.
  tracking,

  /// Crossmint asks the receiving wallet to sign an ownership message.
  walletProof,
  delivered,
  failed,
}

/// One Add funds session. Nothing here invents a number: balances, quotes and
/// order states are exactly what the BFF returned, or absent.
class AddFundsController extends ChangeNotifier {
  AddFundsController({
    required DepositsClient client,
    this.walletSource,
    DepositOrderMemory? memory,
    this.accountId,
    this.requiredUsdcBaseUnits,
    this.preferredWallet,
    this.pollInterval = const Duration(seconds: 3),
    this.slowPollInterval = const Duration(seconds: 6),
    this.slowAfter = const Duration(minutes: 2),
    this.giveUpAfter = const Duration(minutes: 20),
    this.quoteDebounce = const Duration(milliseconds: 450),
    String Function()? newIdempotencyKey,
    DateTime Function()? now,
  }) : _client = client,
       _memory = memory ?? InMemoryDepositOrderMemory(),
       _newKey = newIdempotencyKey ?? (() => const Uuid().v4()),
       _now = now ?? DateTime.now;

  final DepositsClient _client;
  final DepositWalletSource? walletSource;
  final DepositOrderMemory _memory;

  /// The canonical account id, used only to key the resume memory.
  final String? accountId;

  /// What the trade in progress needs, when Add funds was opened from it.
  final BigInt? requiredUsdcBaseUnits;

  /// The wallet a trade in progress spends from. Funds go there when the
  /// account has proven it; otherwise the server's own choice stands and the
  /// sheet says funds land elsewhere. Only ever a hint, never a recipient.
  final String? preferredWallet;
  final Duration pollInterval;
  final Duration slowPollInterval;
  final Duration slowAfter;
  final Duration giveUpAfter;
  final Duration quoteDebounce;
  final String Function() _newKey;
  final DateTime Function() _now;

  AddFundsStage _stage = AddFundsStage.loading;
  DepositsStatus? _status;
  DepositsException? _statusError;
  WalletBalance? _balance;
  DepositsException? _balanceError;
  bool _balanceLoading = false;
  UsdAmount? _amount;
  bool _amountTouched = false;
  bool _customAmount = false;
  String _customText = '';
  DepositQuote? _quote;
  DepositsException? _quoteError;
  bool _quoteLoading = false;
  String _email = '';
  DepositOrder? _order;
  Uri? _checkoutUri;
  DepositsException? _error;
  String? _idempotencyKey;
  bool _busy = false;
  bool _checkoutOpen = false;
  bool _checkoutSeen = false;
  bool _pollGaveUp = false;
  bool _disposed = false;
  Timer? _pollTimer;
  Timer? _quoteTimer;
  DateTime? _pollStarted;
  int _quoteRevision = 0;
  int _balanceRevision = 0;

  AddFundsStage get stage => _stage;
  DepositsStatus? get status => _status;
  DepositsException? get statusError => _statusError;
  WalletBalance? get balance => _balance;
  DepositsException? get balanceError => _balanceError;
  bool get balanceLoading => _balanceLoading;
  UsdAmount? get amount => _amount;
  bool get isCustomAmount => _customAmount;
  String get customText => _customText;
  DepositQuote? get quote => _quote;
  DepositsException? get quoteError => _quoteError;
  bool get quoteLoading => _quoteLoading;
  String get email => _email;
  DepositOrder? get order => _order;
  Uri? get checkoutUri => _checkoutUri;
  DepositsException? get error => _error;
  bool get busy => _busy;
  bool get pollGaveUp => _pollGaveUp;
  bool get isCheckoutOpen => _checkoutOpen;

  /// The person has had this order's checkout on screen at least once.
  bool get checkoutSeen => _checkoutSeen;

  /// The wallet being funded has no SOL, so it can't pay a trade's network
  /// fee yet. Card payments only buy USDC; SOL has to be sent in.
  bool get needsSol => _balance?.hasNoSol ?? false;

  List<UsdAmount> get presets => _status?.presets ?? const [];
  UsdAmount? get minAmount => _status?.minUsd;
  UsdAmount? get maxAmount => _status?.maxUsd;
  bool get needsEmail => _status?.account?.needsEmail ?? false;
  bool get emailValid => RegExp(
    r'^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,63}$',
  ).hasMatch(_email.trim());

  bool get amountInRange {
    final a = _amount, lo = minAmount, hi = maxAmount;
    return a != null && lo != null && hi != null && a >= lo && a <= hi;
  }

  bool get canStart =>
      _stage == AddFundsStage.choose &&
      !_busy &&
      amountInRange &&
      (!needsEmail || emailValid);

  /// The wallet funds will land in: the server's choice, mirrored here.
  String? get destination {
    if (_order != null) return _order!.recipient;
    if (_quote != null) return _quote!.recipient;
    final wallets = _status?.account?.wallets ?? const [];
    final hint = _walletHint;
    if (hint != null) return hint;
    for (final w in wallets) {
      if (w.session) return w.address;
    }
    for (final w in wallets) {
      if (w.primary) return w.address;
    }
    return wallets.isEmpty ? null : wallets.first.address;
  }

  /// The trade's wallet, else this device's wallet — but only one the
  /// account has proven. The server re-checks it either way.
  String? get _walletHint {
    final wallets = _status?.account?.wallets ?? const [];
    for (final candidate in [preferredWallet, walletSource?.address]) {
      if (candidate != null && wallets.any((w) => w.address == candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// The wallet this person expects to fund (the trade's, else this
  /// device's), when the account hasn't proven it — so funds would land
  /// elsewhere. The sheet says so instead of hiding it.
  bool get localWalletNotLinked {
    final local = preferredWallet ?? walletSource?.address;
    final wallets = _status?.account?.wallets;
    return local != null &&
        wallets != null &&
        wallets.isNotEmpty &&
        !wallets.any((w) => w.address == local);
  }

  /// USDC still missing for the trade that opened this sheet.
  BigInt? get shortfallBaseUnits {
    final need = requiredUsdcBaseUnits, have = _balance?.usdcBaseUnits;
    if (need == null || have == null) return null;
    final gap = need - have;
    return gap > BigInt.zero ? gap : BigInt.zero;
  }

  /// Plain-words reason the sheet can't take a payment, when it can't.
  String? get unavailableMessage {
    if (_stage != AddFundsStage.unavailable) return null;
    if (_statusError != null) return _statusError!.message;
    final s = _status;
    if (s == null) return 'Adding funds isn\'t available right now.';
    switch (s.accountIssue) {
      case 'NOT_LINKED':
        return 'Finish setting up your account to add funds.';
      case 'UNAVAILABLE':
        return 'We couldn\'t confirm your account just now. Try again in a moment.';
    }
    if (s.account != null && s.account!.wallets.isEmpty) {
      return 'Connect a wallet to your account first. Funds can only go to a wallet you\'ve proven is yours.';
    }
    return s.reasonMessage ?? 'Adding funds isn\'t available right now.';
  }

  // ── loading ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    _stage = AddFundsStage.loading;
    _statusError = null;
    _publish();
    final DepositsStatus status;
    try {
      status = await _client.status();
    } on DepositsException catch (e) {
      if (_disposed) return;
      _statusError = e;
      _stage = AddFundsStage.unavailable;
      _publish();
      return;
    }
    if (_disposed) return;
    _status = status;
    final account = status.account;
    if (status.accountIssue == 'SIGNED_OUT') {
      _stage = AddFundsStage.signedOut;
      _publish();
      return;
    }
    if (account != null && account.wallets.isNotEmpty) {
      unawaited(refreshBalance());
    }
    if (account == null || account.wallets.isEmpty || !status.available) {
      _stage = AddFundsStage.unavailable;
      _publish();
      return;
    }
    // A payment still in flight comes first: offering a fresh amount while
    // one is pending invites a second charge.
    if (await _resumePending()) return;
    if (_disposed) return;
    _pickDefaultAmount();
    _stage = AddFundsStage.choose;
    _publish();
    _scheduleQuote(immediate: true);
  }

  Future<void> refreshBalance() async {
    final account = _status?.account;
    if (account == null || account.wallets.isEmpty) return;
    if (_status?.balanceAvailable == false) return;
    final revision = ++_balanceRevision;
    _balanceLoading = true;
    _balanceError = null;
    _publish();
    try {
      final read = await _client.balance(wallet: destination);
      if (_disposed || revision != _balanceRevision) return;
      _balance = read;
      if (!_amountTouched && _stage == AddFundsStage.choose) {
        final before = _amount;
        _pickDefaultAmount();
        // A trade's shortfall can move the default: quote what's shown.
        if (_amount != before) _setAmount(_amount);
      }
    } on DepositsException catch (e) {
      if (_disposed || revision != _balanceRevision) return;
      _balanceError = e;
    } finally {
      if (!_disposed && revision == _balanceRevision) {
        _balanceLoading = false;
        _publish();
      }
    }
  }

  void _pickDefaultAmount() {
    final list = presets;
    if (list.isEmpty) {
      _amount ??= minAmount;
      return;
    }
    final gap = shortfallBaseUnits;
    if (gap != null && gap > BigInt.zero) {
      // Card fees come out of the amount; aim 6% above the gap (a starting
      // point only — Crossmint's own quote is shown before anyone pays).
      // USDC base units × 106 / 10^6 = cents × 1.06, rounded up.
      final cents =
          ((gap * BigInt.from(106) + BigInt.from(999999)) ~/
                  BigInt.from(1000000))
              .toInt();
      final need = UsdAmount.cents(((cents + 99) ~/ 100) * 100);
      final fit = list.where((p) => p >= need);
      final max = maxAmount;
      _amount =
          fit.isNotEmpty ? fit.first : (max != null && need > max ? max : need);
      _customAmount = !list.contains(_amount);
      if (_customAmount) _customText = _amount!.wire;
      return;
    }
    _amount ??= list.length > 1 ? list[1] : list.first;
  }

  Future<bool> _resumePending() async {
    final id = accountId;
    if (id == null) return false;
    final pending = await _memory.pending(id);
    if (pending == null || _disposed) return false;
    try {
      final order = await _client.order(pending);
      if (_disposed) return false;
      if (order.state.isTerminal) {
        await _memory.forget(id);
        // A delivery that finished while the sheet was closed is still news.
        if (order.state == DepositOrderState.delivered) {
          _order = order;
          _stage = AddFundsStage.delivered;
          _publish();
          return true;
        }
        return false;
      }
      // Unpaid and abandoned: its checkout link left with the last visit
      // (the client secret is never stored), and nothing was charged. Offer a
      // fresh payment instead of a dead end.
      if (!order.state.isWorthResuming) {
        await _memory.forget(id);
        return false;
      }
      _order = order;
      _stage = AddFundsStage.tracking;
      _applyOrder(order);
      _startPolling();
      return true;
    } on DepositsException catch (e) {
      if (e.kind == DepositsErrorKind.notFound) await _memory.forget(id);
      return false;
    }
  }

  // ── amount, email, quote ────────────────────────────────────────────────

  void selectPreset(UsdAmount amount) {
    if (_stage != AddFundsStage.choose) return;
    _amountTouched = true;
    _customAmount = false;
    _setAmount(amount);
  }

  void useCustomAmount() {
    if (_stage != AddFundsStage.choose) return;
    _amountTouched = true;
    _customAmount = true;
    _customText = _amount?.wire ?? '';
    _publish();
  }

  void editCustomAmount(String text) {
    if (_stage != AddFundsStage.choose) return;
    _amountTouched = true;
    _customAmount = true;
    _customText = text;
    _setAmount(UsdAmount.tryParse(text));
  }

  void _setAmount(UsdAmount? amount) {
    if (amount != _amount) {
      _amount = amount;
      _idempotencyKey = null;
      _quote = null;
      _quoteError = null;
      _error = null;
    }
    _publish();
    _scheduleQuote();
  }

  void editEmail(String value) {
    if (_email == value) return;
    _email = value;
    _idempotencyKey = null;
    _error = null;
    _publish();
    if (emailValid) _scheduleQuote();
  }

  void _scheduleQuote({bool immediate = false}) {
    _quoteTimer?.cancel();
    final revision = ++_quoteRevision;
    if (!amountInRange || (needsEmail && !emailValid)) {
      _quoteLoading = false;
      _publish();
      return;
    }
    _quoteLoading = true;
    _publish();
    _quoteTimer = Timer(immediate ? Duration.zero : quoteDebounce, () async {
      try {
        final quote = await _client.quote(
          amount: _amount!,
          wallet: _walletHint,
          receiptEmail: needsEmail ? _email.trim() : null,
        );
        if (_disposed || revision != _quoteRevision) return;
        _quote = quote;
        _quoteError = null;
      } on DepositsException catch (e) {
        if (_disposed || revision != _quoteRevision) return;
        _quote = null;
        _quoteError = e;
      } finally {
        if (!_disposed && revision == _quoteRevision) {
          _quoteLoading = false;
          _publish();
        }
      }
    });
  }

  // ── checkout ─────────────────────────────────────────────────────────────

  /// Creates the Crossmint order. On success [checkoutUri] is ready to show.
  /// A retried tap reuses the same idempotency key, so it can't double-order.
  Future<bool> startCheckout() async {
    if (!canStart) return false;
    _busy = true;
    _error = null;
    _stage = AddFundsStage.starting;
    _publish();
    _idempotencyKey ??= _newKey();
    try {
      final created = await _client.create(
        amount: _amount!,
        idempotencyKey: _idempotencyKey!,
        wallet: _walletHint,
        receiptEmail: needsEmail ? _email.trim() : null,
      );
      if (_disposed) return false;
      _order = created.order;
      _checkoutUri = created.checkoutUri;
      if (accountId != null) {
        unawaited(_memory.remember(accountId!, created.order.orderId));
      }
      _stage = AddFundsStage.checkout;
      _applyOrder(created.order);
      _startPolling();
      return true;
    } on DepositsException catch (e) {
      if (_disposed) return false;
      if (e.kind == DepositsErrorKind.conflict) _idempotencyKey = null;
      _error = e;
      _stage = AddFundsStage.choose;
      return false;
    } finally {
      _busy = false;
      _publish();
    }
  }

  void checkoutOpened() {
    _checkoutOpen = true;
    _checkoutSeen = true;
    if (_order != null && !_order!.state.isTerminal) {
      _stage =
          _order!.state == DepositOrderState.awaitingWalletProof
              ? AddFundsStage.walletProof
              : AddFundsStage.checkout;
    }
    _publish();
  }

  /// The checkout screen closed. Ask once right away, then keep polling.
  Future<void> checkoutClosed() async {
    _checkoutOpen = false;
    if (_order != null &&
        !_order!.state.isTerminal &&
        _stage == AddFundsStage.checkout) {
      _stage = AddFundsStage.tracking;
    }
    _publish();
    await refreshOrder();
  }

  /// Back into the same order's checkout — never a new order.
  bool get canReturnToCheckout =>
      _checkoutUri != null &&
      _order != null &&
      !_order!.state.isTerminal &&
      !_order!.state.isInFlight &&
      _order!.state != DepositOrderState.identityReview;

  Future<void> refreshOrder() async {
    final current = _order;
    if (current == null) return;
    try {
      final next = await _client.order(current.orderId);
      if (_disposed || _order?.orderId != current.orderId) return;
      _applyOrder(next);
      if (!next.state.isTerminal && _pollTimer == null) _startPolling();
    } on DepositsException catch (e) {
      if (_disposed) return;
      _error = e;
      _publish();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollGaveUp = false;
    _pollStarted = _now();
    _schedulePoll();
  }

  void _schedulePoll() {
    final started = _pollStarted;
    if (_disposed || started == null) return;
    final elapsed = _now().difference(started);
    if (elapsed >= giveUpAfter) {
      _pollTimer = null;
      _pollGaveUp = true;
      _publish();
      return;
    }
    _pollTimer = Timer(
      elapsed >= slowAfter ? slowPollInterval : pollInterval,
      _pollOnce,
    );
  }

  Future<void> _pollOnce() async {
    final current = _order;
    if (_disposed || current == null) return;
    try {
      final next = await _client.order(current.orderId);
      if (_disposed || _order?.orderId != current.orderId) return;
      _error = null;
      _applyOrder(next);
    } on DepositsException catch (e) {
      if (_disposed) return;
      // Keep trying on a dropped connection; say so without alarming.
      if (e.kind != DepositsErrorKind.connection &&
          e.kind != DepositsErrorKind.provider &&
          e.kind != DepositsErrorKind.rateLimited) {
        _error = e;
      }
      _publish();
    }
    if (_order != null && !_order!.state.isTerminal && !_disposed) {
      _schedulePoll();
    } else {
      _pollTimer = null;
    }
  }

  void resumeChecking() {
    if (_order == null || _order!.state.isTerminal) return;
    _startPolling();
    unawaited(refreshOrder());
  }

  void _applyOrder(DepositOrder order) {
    final wasDelivered =
        _order?.state == DepositOrderState.delivered &&
        _stage == AddFundsStage.delivered;
    _order = order;
    switch (order.state) {
      case DepositOrderState.delivered:
        _stopPolling();
        if (!wasDelivered) {
          _stage = AddFundsStage.delivered;
          if (accountId != null) unawaited(_memory.forget(accountId!));
          unawaited(_refreshBalanceAfterDelivery());
        }
      case DepositOrderState.identityFailed ||
          DepositOrderState.deliveryFailed ||
          DepositOrderState.expired:
        _stopPolling();
        _stage = AddFundsStage.failed;
        if (accountId != null) unawaited(_memory.forget(accountId!));
      case DepositOrderState.awaitingWalletProof:
        _stage = AddFundsStage.walletProof;
      default:
        // Just created and about to open counts as "in checkout": no flash
        // of the tracking view under the checkout as it slides in.
        _stage =
            _checkoutOpen ||
                    _stage == AddFundsStage.starting ||
                    _stage == AddFundsStage.checkout
                ? AddFundsStage.checkout
                : AddFundsStage.tracking;
    }
    _publish();
  }

  /// RPC nodes can trail the delivery by a few seconds: read twice.
  Future<void> _refreshBalanceAfterDelivery() async {
    await refreshBalance();
    if (_disposed) return;
    await Future<void>.delayed(const Duration(seconds: 4));
    if (_disposed) return;
    await refreshBalance();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── wallet ownership proof ───────────────────────────────────────────────

  /// True when this device holds the wallet Crossmint wants a signature from.
  bool get canSignProof {
    final order = _order, source = walletSource;
    return order?.walletProofMessage != null &&
        source != null &&
        source.isCurrent &&
        source.address == order!.recipient;
  }

  /// True once Crossmint has the verified signature; the order then carries on
  /// to payment (the sheet reopens the checkout when it can).
  Future<bool> signOwnershipProof() async {
    final order = _order, source = walletSource;
    final message = order?.walletProofMessage;
    if (_busy || order == null || message == null) return false;
    if (source == null ||
        !source.isCurrent ||
        source.address != order.recipient) {
      _error = DepositsException(
        DepositsErrorKind.forbidden,
        'Open Chumbucket with the wallet ending ${shortAddress(order.recipient).split('…').last} connected, then sign.',
      );
      _publish();
      return false;
    }
    _busy = true;
    _error = null;
    _publish();
    try {
      final signature = await source.signMessage(
        Uint8List.fromList(utf8.encode(message)),
      );
      if (signature.length != 64) throw const DepositWalletDeclined();
      final next = await _client.verifyWallet(
        orderId: order.orderId,
        signatureBase64: base64Encode(signature),
      );
      if (_disposed) return false;
      _applyOrder(next);
      return true;
    } on DepositWalletDeclined {
      if (_disposed) return false;
      _error = const DepositsException(
        DepositsErrorKind.forbidden,
        'No signature was made. Your payment is waiting — sign when you\'re ready.',
      );
      return false;
    } on DepositsException catch (e) {
      if (_disposed) return false;
      _error = e;
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _publish();
      }
    }
  }

  // ── after an ending ─────────────────────────────────────────────────────

  /// Back to amount selection for a fresh payment.
  void startOver() {
    _stopPolling();
    _order = null;
    _checkoutUri = null;
    _idempotencyKey = null;
    _error = null;
    _pollGaveUp = false;
    _checkoutOpen = false;
    _checkoutSeen = false;
    if (accountId != null) unawaited(_memory.forget(accountId!));
    _stage =
        (_status?.available ?? false)
            ? AddFundsStage.choose
            : AddFundsStage.unavailable;
    _publish();
    _scheduleQuote(immediate: true);
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _quoteTimer?.cancel();
    super.dispose();
  }
}
