/// The on-phone wallet for the signed-in account: load it, make one, link it
/// to the account, back it up, export it.
///
/// Linking reuses the server's existing proof flow, unchanged: the BFF issues a
/// single-use Sign-in-with-Solana challenge bound to this account and this
/// address (`auth.requestWalletNonce`, purpose `link_wallet`), the key signs
/// that exact message on the phone, and `auth.linkWallet` verifies it and
/// attaches the wallet (labelled "embedded"). No transaction, nothing moves.
///
/// Order matters when making a wallet: the key is saved to secure storage and
/// read back BEFORE it is linked or shown as usable, so a crash at any point
/// can never leave an account pointing at a key nobody holds.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';

import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';

import 'embedded_wallet_key.dart';
import 'embedded_wallet_vault.dart';

enum EmbeddedWalletPhase {
  /// No account bound (signed out).
  idle,

  /// Reading this account's wallet from the phone.
  loading,

  /// This account has no wallet on this phone.
  none,

  /// Making a key / importing a phrase.
  creating,

  /// Proving the wallet to the server.
  linking,

  /// A wallet is on this phone. [EmbeddedWalletController.linked] says whether
  /// the server has confirmed it yet.
  ready,
}

class EmbeddedWalletController extends ChangeNotifier {
  EmbeddedWalletController({
    required EmbeddedWalletVault vault,
    required SessionBffClient bff,
    required Future<String?> Function() authToken,
    Future<EmbeddedWalletKey> Function()? generate,
    bool ownsBff = false,
  }) : _vault = vault,
       _bff = bff,
       _ownsBff = ownsBff,
       _authToken = authToken,
       _generate = generate ?? EmbeddedWalletKey.generate;

  final EmbeddedWalletVault _vault;
  final SessionBffClient _bff;
  final bool _ownsBff;
  final Future<String?> Function() _authToken;
  final Future<EmbeddedWalletKey> Function() _generate;

  String? _userId;
  int _epoch = 0;
  bool _disposed = false;
  EmbeddedWalletPhase _phase = EmbeddedWalletPhase.idle;
  EmbeddedWalletRecord? _record;
  EmbeddedWalletKey? _key;
  WalletBackupOutcome? _backup;
  String? _error;

  EmbeddedWalletPhase get phase => _phase;
  String? get userId => _userId;
  String? get address => _record?.address;
  bool get hasWallet => _record != null;
  bool get linked => _record?.linked ?? false;
  bool get restoredFromBackup => _record?.restoredFromBackup ?? false;
  bool get isBusy =>
      _phase == EmbeddedWalletPhase.loading ||
      _phase == EmbeddedWalletPhase.creating ||
      _phase == EmbeddedWalletPhase.linking;

  /// How the last backup attempt went this session; null when not tried yet.
  WalletBackupOutcome? get backup => _backup;

  /// Human copy for the last failure; null when there was none.
  String? get error => _error;

  /// The signer for trades, only once the server has confirmed this wallet
  /// is the account's. Bound to the account it was loaded for.
  EmbeddedWalletKey? get signer =>
      _phase == EmbeddedWalletPhase.ready && linked ? _key : null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Follows the signed-in account. Null (signed out) forgets everything in
  /// memory; the stored wallet stays on the phone for its account.
  Future<void> bind(String? userId) async {
    if (_disposed || userId == _userId) return;
    final epoch = ++_epoch;
    _userId = userId;
    _record = null;
    _key = null;
    _backup = null;
    _error = null;
    if (userId == null) {
      _phase = EmbeddedWalletPhase.idle;
      _notify();
      return;
    }
    _phase = EmbeddedWalletPhase.loading;
    _notify();
    try {
      final record = await _vault.load(userId);
      if (!_current(epoch)) return;
      if (record == null) {
        _phase = EmbeddedWalletPhase.none;
        _notify();
        return;
      }
      final key = await EmbeddedWalletKey.fromRecoveryPhrase(
        record.recoveryPhrase,
      );
      if (!_current(epoch)) return;
      if (key.address != record.address) {
        throw const EmbeddedWalletStorageException();
      }
      _record = record;
      _key = key;
      _phase = EmbeddedWalletPhase.ready;
      _notify();
      // Keeps the encrypted backup current (a screen lock added since, a
      // reinstall) and learns its state; a no-op when it already matches.
      unawaited(_refreshBackup(epoch, userId, key));
      // A wallet restored after a reinstall is re-proven to the server.
      if (!record.linked) unawaited(link());
    } catch (_) {
      if (!_current(epoch)) return;
      _phase = EmbeddedWalletPhase.none;
      _error =
          'Couldn’t open the wallet stored on this phone. Unlock your phone '
          'and try again.';
      _notify();
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  Future<void> _refreshBackup(
    int epoch,
    String userId,
    EmbeddedWalletKey key,
  ) async {
    final outcome = await _vault.backUp(userId, key.recoveryPhrase);
    if (!_current(epoch)) return;
    _backup = outcome;
    _notify();
  }

  /// Makes a new wallet for this account on this phone, saves it, backs it
  /// up when that can be end-to-end encrypted, then links it.
  Future<void> create() => _adopt(() => _generate());

  /// Puts an existing wallet (its 12-word phrase) on this phone for this
  /// account, then links it. Only when the account has none here.
  Future<void> importRecoveryPhrase(String phrase) =>
      _adopt(() => EmbeddedWalletKey.fromRecoveryPhrase(phrase));

  Future<void> _adopt(Future<EmbeddedWalletKey> Function() make) async {
    final userId = _userId;
    if (_disposed || userId == null || hasWallet || isBusy) return;
    final epoch = _epoch;
    _phase = EmbeddedWalletPhase.creating;
    _error = null;
    _notify();
    try {
      final key = await make();
      if (!_current(epoch)) return;
      final record = EmbeddedWalletRecord(
        address: key.address,
        recoveryPhrase: key.recoveryPhrase,
        linked: false,
        createdAt: DateTime.now().toUtc(),
      );
      await _vault.save(userId, record);
      if (!_current(epoch)) return;
      _record = record;
      _key = key;
      _phase = EmbeddedWalletPhase.ready;
      _notify();
      _backup = await _vault.backUp(userId, key.recoveryPhrase);
      if (!_current(epoch)) return;
      _notify();
      await link();
    } on EmbeddedWalletException catch (e) {
      if (!_current(epoch)) return;
      _phase = EmbeddedWalletPhase.none;
      _error = e.message;
      _notify();
    } catch (_) {
      if (!_current(epoch)) return;
      _phase = hasWallet ? EmbeddedWalletPhase.ready : EmbeddedWalletPhase.none;
      _error =
          'Couldn’t save a wallet on this phone. Unlock your phone and try '
          'again. Nothing was created.';
      _notify();
    }
  }

  /// Proves the wallet to the server and records the answer. Safe to repeat:
  /// the server answers "reaffirmed" for a wallet the account already holds.
  Future<void> link() async {
    final userId = _userId;
    final key = _key;
    final record = _record;
    if (_disposed ||
        userId == null ||
        key == null ||
        record == null ||
        _phase == EmbeddedWalletPhase.linking) {
      return;
    }
    final epoch = _epoch;
    _phase = EmbeddedWalletPhase.linking;
    _error = null;
    _notify();
    try {
      final token = await _authToken();
      if (!_current(epoch)) return;
      if (token == null) {
        throw const SessionException(
          SessionError.refused(
            'Sign in again to link this wallet.',
            code: SessionErrorCode.tokenInvalid,
          ),
        );
      }
      final proof = await _bff.requestWalletLink(token, address: key.address);
      if (!_current(epoch)) return;
      final signature = base58encode(
        await key.sign(utf8.encode(proof.message)),
      );
      await _bff.linkWallet(
        token,
        address: key.address,
        proof: proof,
        signature: signature,
        walletType: 'embedded',
      );
      if (!_current(epoch)) return;
      final linked = record.copyWith(linked: true);
      await _vault.save(userId, linked);
      if (!_current(epoch)) return;
      _record = linked;
      _phase = EmbeddedWalletPhase.ready;
      _notify();
    } on SessionException catch (e) {
      if (!_current(epoch)) return;
      _phase = EmbeddedWalletPhase.ready;
      _error = _linkCopy(e.error);
      _notify();
    } catch (_) {
      if (!_current(epoch)) return;
      _phase = EmbeddedWalletPhase.ready;
      _error = 'Couldn’t link the wallet. Try again.';
      _notify();
    }
  }

  static String _linkCopy(SessionError error) => switch (error.code) {
    'NONCE_EXPIRED' ||
    'NONCE_REUSED' ||
    'NONCE_UNKNOWN' => 'The link request expired. Try again.',
    _ => error.message,
  };

  /// Tries the end-to-end encrypted backup again (after adding a screen lock).
  Future<void> retryBackup() async {
    final userId = _userId;
    final key = _key;
    if (_disposed || userId == null || key == null) return;
    final epoch = _epoch;
    final outcome = await _vault.backUp(userId, key.recoveryPhrase);
    if (!_current(epoch)) return;
    _backup = outcome;
    _notify();
  }

  /// The 12-word recovery phrase — only for an explicit reveal.
  String? revealRecoveryPhrase() => _key?.recoveryPhrase;

  /// The base58 private key — only for an explicit export.
  Future<String?> exportPrivateKey() async => _key?.exportPrivateKey();

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (_ownsBff) _bff.close();
    super.dispose();
  }
}
