/// A wallet's real mainnet USDC and SOL, read by the server
/// (`deposits.balance`: genesis-pinned mainnet RPC, the account's own
/// verified wallets only). The one balance the calls product shows — never
/// the app's legacy devnet RPC.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/deposits_models.dart';
import 'deposits_dependencies.dart';

class MainnetBalanceView {
  const MainnetBalanceView({
    required this.balance,
    required this.loading,
    required this.error,
    required this.available,
    required this.refresh,
  });

  /// Exactly the server's read, or null.
  final WalletBalance? balance;
  final bool loading;
  final DepositsException? error;

  /// False when this build can't read balances at all.
  final bool available;
  final Future<void> Function() refresh;

  /// "12.40 USDC · 0.0085 SOL", or null when there is no read.
  String? get summary {
    final b = balance;
    return b == null ? null : '${b.usdcLabel} USDC · ${b.solLabel} SOL';
  }
}

class MainnetWalletBalance extends StatefulWidget {
  const MainnetWalletBalance({
    super.key,
    required this.wallet,
    required this.builder,
  });

  /// One of the account's verified wallets. Null reads nothing.
  final String? wallet;
  final Widget Function(BuildContext context, MainnetBalanceView view) builder;

  @override
  State<MainnetWalletBalance> createState() => _MainnetWalletBalanceState();
}

class _MainnetWalletBalanceState extends State<MainnetWalletBalance> {
  DepositsDependencies? _deps;
  WalletBalance? _balance;
  DepositsException? _error;
  bool _loading = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _deps = DepositsDependencies.of(context);
    _loading = _deps != null && widget.wallet != null;
    unawaited(_read(first: true));
  }

  @override
  void didUpdateWidget(covariant MainnetWalletBalance old) {
    super.didUpdateWidget(old);
    if (old.wallet != widget.wallet) {
      _balance = null;
      _error = null;
      unawaited(_read());
    }
  }

  Future<void> _read({bool first = false}) async {
    final deps = _deps, wallet = widget.wallet;
    final revision = ++_revision;
    if (deps == null || wallet == null) {
      if (mounted && !first) setState(() => _loading = false);
      return;
    }
    if (mounted && !first) setState(() => _loading = true);
    final client = deps.createClient();
    try {
      final read = await client.balance(wallet: wallet);
      if (!mounted || revision != _revision) return;
      if (read.wallet != wallet) {
        throw const DepositsException(DepositsErrorKind.invalidResponse);
      }
      setState(() {
        _balance = read;
        _error = null;
      });
    } on DepositsException catch (e) {
      if (!mounted || revision != _revision) return;
      setState(() => _error = e);
    } finally {
      client.close();
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    MainnetBalanceView(
      balance: _balance,
      loading: _loading,
      error: _error,
      available: _deps != null && widget.wallet != null,
      refresh: _read,
    ),
  );
}
