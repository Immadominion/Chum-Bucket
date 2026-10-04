/// The account's money, app-wide: whether calls with an amount are on
/// (`money.status`), the trading wallet's balance for the header pill
/// (`money.wallet`), and what can be collected (`money.winnings`).
///
/// Off — the build's `MONEY_CALLS_ENABLED` or the server's — means hidden:
/// no pill, no amount row, no money chrome anywhere. Nothing here is a
/// number the server did not send; a failed read keeps the last good one
/// on screen, and never shows a "last updated".
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/money_client.dart';
import 'data/money_models.dart';

/// An amount on a call: Free, or dollars as USDC base units.
@immutable
class MoneyAmount {
  const MoneyAmount.free() : baseUnits = null;
  const MoneyAmount(BigInt this.baseUnits);

  final BigInt? baseUnits;
  bool get isFree => baseUnits == null;

  /// "Free", "$5", "$7.50".
  String get label => isFree ? 'Free' : moneyDollars(baseUnits!);

  String get wire => baseUnits?.toString() ?? 'free';

  static MoneyAmount? fromWire(String? value) {
    if (value == 'free') return const MoneyAmount.free();
    if (value == null || !RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(value)) {
      return null;
    }
    return MoneyAmount(BigInt.parse(value));
  }

  @override
  bool operator ==(Object other) =>
      other is MoneyAmount && other.baseUnits == baseUnits;

  @override
  int get hashCode => baseUnits.hashCode;
}

/// The last amount used on this phone, per account.
abstract interface class MoneyAmountMemory {
  Future<String?> read(String accountId);
  Future<void> write(String accountId, String value);
}

class SharedPrefsMoneyAmountMemory implements MoneyAmountMemory {
  const SharedPrefsMoneyAmountMemory();

  static String _key(String accountId) => 'money.lastAmount.v1.$accountId';

  @override
  Future<String?> read(String accountId) async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key(accountId));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String accountId, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key(accountId),
        value,
      );
    } catch (_) {
      // Remembering is a convenience; the server keeps its own.
    }
  }
}

/// Per-trade ceiling the app's Panta review accepts (`PantaUsdcAmount`).
final moneyLocalMaxBaseUnits = BigInt.from(100000000);
final _fiveDollars = BigInt.from(5000000);

class MoneyController extends ChangeNotifier with WidgetsBindingObserver {
  MoneyController({
    required MoneyClient Function() createClient,
    MoneyAmountMemory memory = const SharedPrefsMoneyAmountMemory(),
    bool observeLifecycle = true,
  }) : _createClient = createClient,
       _memory = memory {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _observing = observeLifecycle;
  }

  final MoneyClient Function() _createClient;
  final MoneyAmountMemory _memory;
  late final bool _observing;
  MoneyClient? _client;
  String? _userId;
  bool _bound = false;
  int _epoch = 0;
  bool _disposed = false;

  MoneyStatus? _status;
  MoneyWalletInfo? _wallet;
  MoneyWinnings _winnings = MoneyWinnings.empty;
  MoneyAmount? _remembered;

  /// Signed in, and money is on for this account.
  bool get enabled => _userId != null && _status?.enabled == true;
  String? get userId => _userId;
  MoneyStatus? get status => _status;

  /// The trading wallet and its balance; null until read.
  MoneyWalletInfo? get wallet => _wallet;
  BigInt? get balance => _wallet?.usdcBaseUnits;
  MoneyWinnings get winnings => _winnings;

  MoneyClient get client => _client ??= _createClient();

  List<BigInt> get presets {
    final server = _status?.presets ?? const [];
    final shown = server.isEmpty
        ? [BigInt.from(5000000), BigInt.from(10000000), BigInt.from(25000000)]
        : server;
    return shown.where((p) => p >= minBaseUnits && p <= maxBaseUnits).toList();
  }

  BigInt get minBaseUnits => _status?.minBaseUnits ?? BigInt.from(1000000);

  /// The server's limit, never above what the app's review accepts.
  BigInt get maxBaseUnits {
    final server = _status?.maxBaseUnits;
    return server == null || server > moneyLocalMaxBaseUnits
        ? moneyLocalMaxBaseUnits
        : server;
  }

  /// The last amount used here, else the server's (its own last), else $5.
  MoneyAmount get defaultAmount {
    final remembered = _remembered;
    if (remembered != null && _fits(remembered)) return remembered;
    final server = _status?.defaultAmountBaseUnits;
    if (server != null && _fits(MoneyAmount(server))) return MoneyAmount(server);
    return MoneyAmount(_fiveDollars);
  }

  bool _fits(MoneyAmount amount) =>
      amount.isFree ||
      (amount.baseUnits! >= minBaseUnits && amount.baseUnits! <= maxBaseUnits);

  Future<void> remember(MoneyAmount amount) async {
    _remembered = amount;
    final account = _userId;
    if (account != null) await _memory.write(account, amount.wire);
  }

  /// Follows the signed-in account (`public.users.id`).
  Future<void> bind(String? userId) async {
    if (_disposed || (_bound && userId == _userId)) return;
    _bound = true;
    final epoch = ++_epoch;
    _userId = userId;
    _status = null;
    _wallet = null;
    _winnings = MoneyWinnings.empty;
    _remembered = null;
    _notify();
    if (userId == null) return;
    try {
      final status = await client.status();
      if (!_current(epoch)) return;
      _status = status;
      _remembered = MoneyAmount.fromWire(await _memory.read(userId));
      if (!_current(epoch)) return;
      _notify();
      if (status.enabled) await refresh();
    } on MoneyException {
      // Unknown is off: nothing money-shaped shows until the server says so.
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  /// Balance and winnings, quietly. A failed read keeps what is shown.
  Future<void> refresh() async {
    await Future.wait([refreshWallet(), refreshWinnings()]);
  }

  Future<MoneyWalletInfo?> refreshWallet() async {
    if (!enabled) return null;
    final epoch = _epoch;
    try {
      final info = await client.wallet();
      if (!_current(epoch)) return null;
      _wallet = info;
      _notify();
      return info;
    } on MoneyException {
      return _wallet;
    }
  }

  Future<void> refreshWinnings() async {
    if (!enabled) return;
    final epoch = _epoch;
    try {
      final winnings = await client.winnings();
      if (!_current(epoch)) return;
      _winnings = winnings;
      _notify();
    } on MoneyException {
      // Kept as shown.
    }
  }

  /// A balance someone else just read (the deposit sheet's watch).
  void adoptWallet(MoneyWalletInfo info) {
    if (!enabled) return;
    _wallet = info;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && enabled) unawaited(refresh());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _client?.close();
    super.dispose();
  }
}
