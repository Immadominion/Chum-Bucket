/// `Collect $9.20`: a won position's payout, through the existing claim path
/// (`pantaTrading.claimPrepare` → sign → `claimSubmit` → `pantaTrading.claim`
/// until CONFIRMED, payout proven on chain). Never auto-signed: each collect
/// is the person's tap.
///
/// The claim's discipline is the positions screen's: one key per attempt
/// (reused only after a lost reply), the claim shape check before an
/// embedded signer signs (`checkPantaClaimForEmbeddedSigning`, run by the
/// signer the resolver hands out), the signed message re-checked unchanged,
/// and the identical signed bytes on every resend.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'data/money_models.dart';

enum MoneyCollectStep { idle, preparing, signing, submitting, collecting, done }

class MoneyCollectProgress {
  const MoneyCollectProgress({this.step = MoneyCollectStep.idle, this.message});
  final MoneyCollectStep step;
  final String? message;
  bool get busy =>
      step == MoneyCollectStep.preparing ||
      step == MoneyCollectStep.signing ||
      step == MoneyCollectStep.submitting;
}

class MoneyWinningsController extends ChangeNotifier {
  MoneyWinningsController({
    required PantaTradingClient client,
    required PantaSignerResolver signerFor,
    String Function()? newIdempotencyKey,
    DateTime Function()? now,
    this.pollEvery = const Duration(seconds: 4),
    this.onCollected,
  }) : _client = client,
       _signerFor = signerFor,
       _newKey = newIdempotencyKey ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final PantaTradingClient _client;
  final PantaSignerResolver _signerFor;
  final String Function() _newKey;
  final DateTime Function() _now;
  final Duration pollEvery;

  /// Called once a payout is proven on chain (refresh balance and winnings).
  final VoidCallback? onCollected;
  final _validator = const PantaTransactionValidator();

  final Map<String, MoneyCollectProgress> _progress = {};
  final Map<String, String> _keys = {};
  final Map<String, ({String claimId, String signed, String accountId})>
  _signed = {};
  final Map<String, Timer> _polls = {};
  bool _disposed = false;

  MoneyCollectProgress progress(String orderId) =>
      _progress[orderId] ?? const MoneyCollectProgress();

  bool get anyBusy => _progress.values.any((p) => p.busy);

  Future<void> collect(MoneyWinning item) async {
    final orderId = item.orderId;
    if (_disposed || progress(orderId).busy) return;
    if (_signed.containsKey(orderId)) return _submit(orderId);
    if (item.collecting && item.claimId != null) {
      // Already going through: only watch it.
      _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.collecting));
      _watch(orderId, item.claimId!);
      return;
    }
    _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.preparing));
    try {
      final session = await _client.currentSession();
      if (session == null) throw const PantaException(PantaErrorCode.signedOut);
      final key = _keys[orderId] ??= _newKey();
      final PantaClaimPrepared prepared;
      try {
        prepared = await _client.claimPrepare(
          orderId: orderId,
          idempotencyKey: key,
          accountId: session.accountId,
        );
      } on PantaException catch (e) {
        if (e.code != PantaErrorCode.connection) _keys.remove(orderId);
        rethrow;
      }
      final tx = prepared.transaction;
      final review = prepared.review;
      if (prepared.claim.state == PantaClaimState.failed) {
        _keys.remove(orderId);
        throw const PantaException(PantaErrorCode.rejected);
      }
      if (tx == null || review == null) {
        // In flight or settled on the server: watch it, never re-sign.
        _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.collecting));
        _watch(orderId, prepared.claim.claimId);
        return;
      }
      if (prepared.claim.owner != item.wallet ||
          prepared.claim.orderId != orderId ||
          review.outcome != item.side) {
        throw const PantaException(PantaErrorCode.invalidResponse);
      }
      if (_now().millisecondsSinceEpoch >= tx.expiresAt) {
        _keys.remove(orderId);
        throw const PantaException(PantaErrorCode.expired);
      }
      final signer = _signerFor(
        item.wallet,
        PantaClaimSigningIntent(
          owner: item.wallet,
          venueMarketId: prepared.claim.venueMarketId,
          outcome: review.outcome,
          winningShares: review.winningShares,
        ),
      );
      if (signer == null) {
        _set(
          orderId,
          const MoneyCollectProgress(
            message: 'Open the wallet that holds this to collect.',
          ),
        );
        return;
      }
      final unsigned = tx.bytes;
      _validator.validateUnsigned(unsigned, item.wallet);
      _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.signing));
      final signed = await signer
          .signTransaction(unsigned)
          .timeout(const Duration(minutes: 2));
      _validator.validateSigned(unsigned, signed, item.wallet);
      if (_now().millisecondsSinceEpoch >= tx.expiresAt) {
        _keys.remove(orderId);
        throw const PantaException(PantaErrorCode.expired);
      }
      _signed[orderId] = (
        claimId: prepared.claim.claimId,
        signed: base64Encode(signed),
        accountId: session.accountId,
      );
      await _submit(orderId);
    } on PantaWalletCancelled {
      _set(orderId, const MoneyCollectProgress(message: 'Cancelled.'));
    } on TimeoutException {
      _set(orderId, const MoneyCollectProgress(message: 'No answer. Try again.'));
    } on PantaException catch (e) {
      _set(orderId, MoneyCollectProgress(message: _copy(e.code)));
    } catch (_) {
      _set(
        orderId,
        const MoneyCollectProgress(message: 'Couldn’t collect. Try again.'),
      );
    }
  }

  Future<void> _submit(String orderId) async {
    final signed = _signed[orderId]!;
    _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.submitting));
    try {
      final view = await _client.claimSubmit(
        claimId: signed.claimId,
        signedTransaction: signed.signed,
        accountId: signed.accountId,
      );
      _accept(orderId, view);
    } on PantaException catch (e) {
      // The bytes may have gone out: keep them for an exact resend.
      _set(
        orderId,
        MoneyCollectProgress(
          message:
              e.code == PantaErrorCode.connection
                  ? 'No answer yet. Tap to send the same claim again.'
                  : _copy(e.code),
        ),
      );
    }
  }

  void _accept(String orderId, PantaClaimView view) {
    switch (view.state) {
      case PantaClaimState.confirmed:
        _done(orderId);
      case PantaClaimState.failed:
        _signed.remove(orderId);
        _keys.remove(orderId);
        _polls.remove(orderId)?.cancel();
        _set(
          orderId,
          const MoneyCollectProgress(message: 'That didn’t go through. Try again.'),
        );
      default:
        _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.collecting));
        _watch(orderId, view.claimId);
    }
  }

  void _done(String orderId) {
    _signed.remove(orderId);
    _keys.remove(orderId);
    _polls.remove(orderId)?.cancel();
    _set(orderId, const MoneyCollectProgress(step: MoneyCollectStep.done));
    onCollected?.call();
  }

  void _watch(String orderId, String claimId) {
    if (_disposed || _polls.containsKey(orderId)) return;
    _polls[orderId] = Timer.periodic(pollEvery, (_) async {
      final session = await _client.currentSession();
      if (_disposed || session == null) return;
      try {
        final view = await _client.claim(
          claimId: claimId,
          accountId: session.accountId,
        );
        if (!_disposed) _accept(orderId, view);
      } on PantaException {
        // The next read tries again.
      }
    });
  }

  static String _copy(PantaErrorCode code) => switch (code) {
    PantaErrorCode.unavailable => 'Collecting isn’t available yet.',
    PantaErrorCode.expired => 'That expired. Tap to try again.',
    PantaErrorCode.walletChanged => 'Your wallet changed. Nothing was signed.',
    PantaErrorCode.signedOut => 'Sign in again to collect.',
    PantaErrorCode.connection => 'No answer. Try again.',
    _ => 'Couldn’t collect yet. Try again.',
  };

  void _set(String orderId, MoneyCollectProgress progress) {
    if (_disposed) return;
    _progress[orderId] = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _polls.values) {
      timer.cancel();
    }
    _polls.clear();
    super.dispose();
  }
}
