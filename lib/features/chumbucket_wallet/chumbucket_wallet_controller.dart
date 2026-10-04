/// The Chumbucket wallet for the signed-in account: one wallet that follows
/// the account across iPhone, Android and the web, and the default for trades
/// (behind `CHUMBUCKET_WALLET_ENABLED`).
///
/// What the server already knows comes first and costs nothing: `wallet.status`
/// names the account's linked Chumbucket wallet, so a returning account shows
/// its wallet (and its balance) without starting a provider session. The
/// provider is only signed in when something must be signed, or on first need
/// ([ensure]): then the wallet is made if the account has none, and linked to
/// the account with the same single-use Sign-in-with-Solana proof every wallet
/// uses (`auth.requestWalletNonce` -> sign -> `auth.linkWallet`, labelled
/// "chumbucket"). No transaction, nothing moves.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';

import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';

import 'chumbucket_wallet_backend.dart';
import 'signed_transaction.dart';

/// `linked_wallets.wallet_type` of the Chumbucket wallet.
const chumbucketWalletType = 'chumbucket';

enum ChumbucketWalletPhase {
  /// Signed out.
  idle,

  /// Asking the server which wallet the account has.
  loading,

  /// The account has no Chumbucket wallet yet.
  none,

  /// Making it, or linking it to the account.
  settingUp,

  /// Linked to the account and ready to sign.
  ready,
}

/// Signs for the account's Chumbucket wallet; every call re-checks that the
/// wallet is still this account's.
abstract interface class ChumbucketWalletSigner {
  String get address;

  /// The 64-byte signature over exactly [message].
  Future<Uint8List> signMessage(Uint8List message);

  /// [unsigned] signed by this wallet in [slot], nothing else changed.
  Future<Uint8List> signTransaction(Uint8List unsigned, {int slot = 0});
}

class ChumbucketWalletController extends ChangeNotifier {
  ChumbucketWalletController({
    required ChumbucketWalletBackend backend,
    required SessionBffClient bff,
    required Future<String?> Function() authToken,
    bool ownsBff = false,
  }) : _backend = backend,
       _bff = bff,
       _authToken = authToken,
       _ownsBff = ownsBff;

  final ChumbucketWalletBackend _backend;
  final SessionBffClient _bff;
  final Future<String?> Function() _authToken;
  final bool _ownsBff;

  String? _userId;
  String? _authUserId;
  int _epoch = 0;
  bool _disposed = false;
  bool _signedIn = false;
  ChumbucketWalletPhase _phase = ChumbucketWalletPhase.idle;
  String? _address;
  String? _error;
  Future<ChumbucketWalletSigner>? _ensuring;

  ChumbucketWalletPhase get phase => _phase;
  String? get userId => _userId;

  /// The linked wallet's address; null until the server has it linked.
  String? get address =>
      _phase == ChumbucketWalletPhase.ready ? _address : null;
  bool get isBusy =>
      _phase == ChumbucketWalletPhase.loading ||
      _phase == ChumbucketWalletPhase.settingUp;

  /// Copy for the last failure; null when there was none.
  String? get error => _error;

  /// The signer for trades, once the wallet is linked to this account.
  ChumbucketWalletSigner? get signer {
    final address = this.address;
    return address == null ? null : _Signer(this, address, _epoch);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  /// Follows the signed-in account. Null signs the provider out too.
  Future<void> bind(String? userId, String? authUserId) async {
    if (_disposed || (userId == _userId && authUserId == _authUserId)) return;
    final epoch = ++_epoch;
    final wasSignedIn = _signedIn;
    _userId = userId;
    _authUserId = authUserId;
    _address = null;
    _error = null;
    _ensuring = null;
    _signedIn = false;
    if (wasSignedIn) unawaited(_backend.signOut());
    if (userId == null || authUserId == null) {
      _phase = ChumbucketWalletPhase.idle;
      _notify();
      return;
    }
    _phase = ChumbucketWalletPhase.loading;
    _notify();
    await refresh(epoch: epoch);
  }

  /// Re-reads the account's linked wallet from the server.
  Future<void> refresh({int? epoch}) async {
    final at = epoch ?? _epoch;
    if (!_current(at) || _userId == null) return;
    try {
      final token = await _authToken();
      if (!_current(at)) return;
      final linked = token == null ? null : await _bff.chumbucketWallet(token);
      if (!_current(at)) return;
      _address = linked;
      _phase =
          linked == null
              ? ChumbucketWalletPhase.none
              : ChumbucketWalletPhase.ready;
    } catch (_) {
      if (!_current(at)) return;
      // Not knowing is not "none": [ensure] asks the provider itself.
      _phase = ChumbucketWalletPhase.none;
    }
    _notify();
  }

  /// First need: signs in to the provider, makes the wallet if the account
  /// has none, links it to the account, and answers its signer. Concurrent
  /// callers share one attempt.
  Future<ChumbucketWalletSigner> ensure() {
    final ready = signer;
    if (ready != null) return Future.value(ready);
    return _ensuring ??= _setUp().whenComplete(() => _ensuring = null);
  }

  Future<ChumbucketWalletSigner> _setUp() async {
    final epoch = _epoch;
    final authUserId = _authUserId;
    if (_disposed || _userId == null || authUserId == null) {
      throw ChumbucketWalletException.signedOut;
    }
    _phase = ChumbucketWalletPhase.settingUp;
    _error = null;
    _notify();
    try {
      await _signIn(epoch, authUserId);
      final address = await _backend.wallet() ?? await _backend.createWallet();
      _check(epoch);
      await _link(epoch, address);
      _address = address;
      _phase = ChumbucketWalletPhase.ready;
      _notify();
      return _Signer(this, address, epoch);
    } catch (e) {
      if (_current(epoch)) {
        _phase = ChumbucketWalletPhase.none;
        _error = switch (e) {
          ChumbucketWalletException(:final message) => message,
          SessionException(:final error) => switch (error.code) {
            'NONCE_EXPIRED' ||
            'NONCE_REUSED' ||
            'NONCE_UNKNOWN' => ChumbucketWalletException.unavailable.message,
            _ => error.message,
          },
          _ => ChumbucketWalletException.unavailable.message,
        };
        _notify();
      }
      if (e is ChumbucketWalletException) rethrow;
      throw ChumbucketWalletException(
        _error ?? ChumbucketWalletException.unavailable.message,
      );
    }
  }

  void _check(int epoch) {
    if (!_current(epoch)) throw ChumbucketWalletException.signedOut;
  }

  Future<void> _signIn(int epoch, String authUserId) async {
    if (_signedIn) return;
    await _backend.signIn(authUserId);
    _check(epoch);
    _signedIn = true;
  }

  /// The server's single-use challenge for this account and [address], signed
  /// by the wallet; "reaffirmed" when it was already linked.
  Future<void> _link(int epoch, String address) async {
    final token = await _authToken();
    _check(epoch);
    if (token == null) throw ChumbucketWalletException.signedOut;
    final proof = await _bff.requestWalletLink(token, address: address);
    _check(epoch);
    final signature = await _backend.signMessage(
      address,
      Uint8List.fromList(utf8.encode(proof.message)),
    );
    _check(epoch);
    if (signature.length != 64) throw ChumbucketWalletException.refused;
    await _bff.linkWallet(
      token,
      address: address,
      proof: proof,
      signature: base58encode(signature),
      walletType: chumbucketWalletType,
    );
    _check(epoch);
  }

  Future<Uint8List> _signMessage(
    int epoch,
    String address,
    Uint8List message,
  ) async {
    _guard(epoch, address);
    await _signIn(epoch, _authUserId!);
    final signature = await _backend.signMessage(address, message);
    _guard(epoch, address);
    if (signature.length != 64) throw ChumbucketWalletException.refused;
    return signature;
  }

  Future<Uint8List> _signTransaction(
    int epoch,
    String address,
    Uint8List unsigned,
    int slot,
  ) async {
    _guard(epoch, address);
    await _signIn(epoch, _authUserId!);
    final answer = await _backend.signTransaction(address, unsigned);
    _guard(epoch, address);
    try {
      return adoptSignerAnswer(unsigned, answer, slot: slot);
    } on SignedTransactionMismatch {
      throw ChumbucketWalletException.refused;
    }
  }

  /// Signed out, another account, or another wallet since the signer was
  /// handed out: refuse.
  void _guard(int epoch, String address) {
    if (!_current(epoch) || _authUserId == null || this.address != address) {
      throw ChumbucketWalletException.signedOut;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (_signedIn) unawaited(_backend.signOut());
    if (_ownsBff) _bff.close();
    super.dispose();
  }
}

class _Signer implements ChumbucketWalletSigner {
  _Signer(this._owner, this.address, this._epoch);
  final ChumbucketWalletController _owner;
  final int _epoch;

  @override
  final String address;

  @override
  Future<Uint8List> signMessage(Uint8List message) =>
      _owner._signMessage(_epoch, address, message);

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned, {int slot = 0}) =>
      _owner._signTransaction(_epoch, address, unsigned, slot);
}

/// The Privy app id and this app's client id when the Chumbucket wallet is on
/// in this build (`CHUMBUCKET_WALLET_ENABLED` and both ids set); else null.
(String, String)? chumbucketWalletIds({
  bool enabled = AppConfig.chumbucketWalletEnabled,
  Map<String, String>? values,
}) {
  if (!enabled) return null;
  final config = values ?? AppConfig.values;
  final appId = config['CHUMBUCKET_PRIVY_APP_ID'] ?? '';
  final clientId = config['CHUMBUCKET_PRIVY_CLIENT_ID'] ?? '';
  return appId.isEmpty || clientId.isEmpty ? null : (appId, clientId);
}
