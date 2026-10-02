/// The person's funded Panta positions and their win claims.
///
/// Reads come from the BFF only (`pantaTrading.positions`), keyed by the
/// canonical session; nothing here reads a wallet balance or invents a value.
/// While an order or a claim is still being confirmed the list refreshes on
/// its own; the server reconciler does the actual checking.
///
/// A claim follows the buy's rules exactly: one durable intent per attempt
/// (the same key is reused until it settles), a server-reviewed transaction,
/// local structural checks, the wallet signer picked by [PantaSignerResolver],
/// a re-check that the signed message is unchanged, and the identical signed
/// bytes on every retry. Approval is not a payout: only the server's chain
/// proof turns a claim into "Claimed".
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/panta_lifecycle_models.dart';
import 'data/panta_trading_client.dart';
import 'data/panta_trading_models.dart';
import 'domain/panta_signer.dart';
import 'domain/panta_transaction_validator.dart';
import 'domain/panta_wallet_port.dart';

enum PantaClaimPhase { idle, preparing, approving, submitting, submitted, done }

class PantaClaimProgress {
  const PantaClaimProgress({
    this.phase = PantaClaimPhase.idle,
    this.message,
    this.canRetrySubmit = false,
  });
  final PantaClaimPhase phase;

  /// Fixed local copy for the person, or null.
  final String? message;
  final bool canRetrySubmit;
  bool get busy =>
      phase == PantaClaimPhase.preparing ||
      phase == PantaClaimPhase.approving ||
      phase == PantaClaimPhase.submitting;
}

class PantaPositionsController extends ChangeNotifier {
  PantaPositionsController({
    required PantaTradingClient client,
    required PantaSignerResolver signerFor,
    DateTime Function()? now,
    String Function()? newIdempotencyKey,
    this.refreshEvery = const Duration(seconds: 15),
    this.walletApprovalTimeout = const Duration(minutes: 2),
  }) : _client = client,
       _signerFor = signerFor,
       _now = now ?? DateTime.now,
       _newKey = newIdempotencyKey ?? const Uuid().v4;

  final PantaTradingClient _client;
  final PantaSignerResolver _signerFor;
  final DateTime Function() _now;
  final String Function() _newKey;
  final Duration refreshEvery;
  final Duration walletApprovalTimeout;
  final _validator = const PantaTransactionValidator();

  PantaPositionsPage? _page;
  PantaException? _error;
  bool _loading = false;
  bool _disposed = false;
  Timer? _timer;
  final Map<String, PantaClaimProgress> _claims = {};
  final Map<String, String> _claimKeys = {};
  final Map<String, ({String claimId, String signed, String accountId})>
  _signedClaims = {};

  PantaPositionsPage? get page => _page;
  PantaException? get error => _error;
  bool get loading => _loading;
  PantaClaimProgress claimProgress(String orderId) =>
      _claims[orderId] ?? const PantaClaimProgress();

  bool get _needsRefresh =>
      (_page?.needsRefresh ?? false) ||
      _claims.values.any((c) => c.phase == PantaClaimPhase.submitted);

  /// Loads the positions. A failed refresh keeps the last good page visible.
  Future<void> load({bool silent = false}) async {
    if (_disposed || _loading) return;
    _loading = true;
    if (!silent) _publish();
    try {
      final session = await _client.currentSession();
      if (session == null) throw const PantaException(PantaErrorCode.signedOut);
      final page = await _client.positions(accountId: session.accountId);
      if (_disposed) return;
      _page = page;
      _error = null;
      // A claim the server now reports as settled no longer needs local state.
      for (final p in page.positions) {
        final claim = p.claim;
        if (claim != null &&
            (claim.state == PantaClaimState.confirmed ||
                claim.state == PantaClaimState.failed)) {
          _claims.remove(p.orderId);
          _signedClaims.remove(p.orderId);
          _claimKeys.remove(p.orderId);
        }
      }
    } on PantaException catch (e) {
      if (!_disposed) _error = e;
    } catch (_) {
      if (!_disposed) {
        _error = const PantaException(PantaErrorCode.invalidResponse);
      }
    } finally {
      _loading = false;
      _schedule();
      _publish();
    }
  }

  /// Keeps refreshing while something is still being confirmed.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_needsRefresh) return;
    _timer = Timer(refreshEvery, () => load(silent: true));
  }

  /// Starts (or resumes) a win claim for [position].
  Future<void> claim(PantaPosition position) async {
    final orderId = position.orderId;
    if (_disposed || claimProgress(orderId).busy) return;
    if (_signedClaims.containsKey(orderId)) return retryClaimSubmit(orderId);
    _set(orderId, const PantaClaimProgress(phase: PantaClaimPhase.preparing));
    try {
      final session = await _client.currentSession();
      if (session == null) throw const PantaException(PantaErrorCode.signedOut);
      final key = _claimKeys[orderId] ??= _newKey();
      final prepared = await _client.claimPrepare(
        orderId: orderId,
        idempotencyKey: key,
        accountId: session.accountId,
      );
      final tx = prepared.transaction;
      final review = prepared.review;
      if (tx == null || review == null) {
        // Already in flight or settled on the server: show that, never re-sign.
        _set(
          orderId,
          const PantaClaimProgress(phase: PantaClaimPhase.submitted),
        );
        await load(silent: true);
        return;
      }
      if (prepared.claim.owner != position.owner ||
          prepared.claim.venueMarketId != position.venueMarketId) {
        throw const PantaException(PantaErrorCode.invalidResponse);
      }
      if (_now().millisecondsSinceEpoch >= tx.expiresAt) {
        _claimKeys.remove(orderId);
        throw const PantaException(PantaErrorCode.expired);
      }
      final signer = _signerFor(
        position.owner,
        PantaClaimSigningIntent(
          owner: position.owner,
          venueMarketId: position.venueMarketId,
          outcome: review.outcome,
          winningShares: review.winningShares,
        ),
      );
      if (signer == null) {
        _set(
          orderId,
          const PantaClaimProgress(
            message:
                'Connect the wallet that holds this position to claim here, '
                'or claim on Panta.',
          ),
        );
        return;
      }
      final unsigned = tx.bytes;
      _validator.validateUnsigned(unsigned, position.owner);
      _set(orderId, const PantaClaimProgress(phase: PantaClaimPhase.approving));
      final signed = await signer
          .signTransaction(unsigned)
          .timeout(walletApprovalTimeout);
      _validator.validateSigned(unsigned, signed, position.owner);
      if (_now().millisecondsSinceEpoch >= tx.expiresAt) {
        _claimKeys.remove(orderId);
        throw const PantaException(PantaErrorCode.expired);
      }
      _signedClaims[orderId] = (
        claimId: prepared.claim.claimId,
        signed: base64Encode(signed),
        accountId: session.accountId,
      );
      await _submit(orderId);
    } on PantaWalletCancelled {
      _set(
        orderId,
        const PantaClaimProgress(message: 'Wallet approval was cancelled.'),
      );
    } on TimeoutException {
      _set(
        orderId,
        const PantaClaimProgress(
          message: 'The wallet did not answer. Try the claim again.',
        ),
      );
    } on PantaException catch (e) {
      _set(orderId, PantaClaimProgress(message: _claimCopy(e)));
    } catch (_) {
      _set(
        orderId,
        const PantaClaimProgress(
          message:
              'The claim could not be completed. Try again or claim on Panta.',
        ),
      );
    }
  }

  /// Re-sends the identical signed claim. Never re-prepares or re-signs.
  Future<void> retryClaimSubmit(String orderId) async {
    if (_disposed || claimProgress(orderId).busy) return;
    if (!_signedClaims.containsKey(orderId)) return;
    try {
      await _submit(orderId);
    } on PantaException catch (e) {
      _set(
        orderId,
        PantaClaimProgress(message: _claimCopy(e), canRetrySubmit: true),
      );
    }
  }

  Future<void> _submit(String orderId) async {
    final signed = _signedClaims[orderId]!;
    _set(orderId, const PantaClaimProgress(phase: PantaClaimPhase.submitting));
    try {
      final view = await _client.claimSubmit(
        claimId: signed.claimId,
        signedTransaction: signed.signed,
        accountId: signed.accountId,
      );
      _set(
        orderId,
        PantaClaimProgress(
          phase:
              view.state == PantaClaimState.confirmed
                  ? PantaClaimPhase.done
                  : PantaClaimPhase.submitted,
        ),
      );
      await load(silent: true);
    } on PantaException catch (e) {
      // The bytes may have reached the network. Keep them for an exact retry.
      _set(
        orderId,
        PantaClaimProgress(message: _claimCopy(e), canRetrySubmit: true),
      );
    }
  }

  String _claimCopy(PantaException e) => switch (e.code) {
    PantaErrorCode.unavailable =>
      'Claiming in the app is not available yet. Claim on Panta instead.',
    PantaErrorCode.expired =>
      'That claim approval expired before it was sent. Try again for a fresh one.',
    PantaErrorCode.rejected =>
      'Panta did not offer a claim for this position yet. Check again later or claim on Panta.',
    PantaErrorCode.connection =>
      'The reply did not arrive. Retry sends the same signed claim.',
    _ => e.message,
  };

  void _set(String orderId, PantaClaimProgress progress) {
    if (_disposed) return;
    _claims[orderId] = progress;
    _schedule();
    _publish();
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
