/// State for proposing, reviewing and publishing markets.
///
/// [MarketCreationController] owns the lists (mine, the review queue) and the
/// non-money actions. [PublishMarketController] owns one paid Panta create:
/// review the fee -> wallet signs -> submit -> confirm. It keeps the signed
/// bytes in memory so an uncertain submit is retried with the IDENTICAL
/// approval, never a new quote; they are not persisted across app restarts
/// (the server already committed them before broadcasting).
library;

import 'dart:async';
import 'dart:convert';

import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/market_creation_client.dart';
import 'data/market_creation_models.dart';
import 'domain/create_transaction_check.dart';

String _messageOf(Object error) => switch (error) {
  // The transport's default copy is about calls; say what this needs.
  CallsSignedOutException() => 'Sign in again to manage your markets.',
  CallsException(:final message) => message,
  PantaWalletCancelled() =>
    'You cancelled in your wallet. Nothing was signed or sent.',
  PantaException(:final message) => message,
  CreateTransactionRejected() =>
    'The wallet returned a different transaction than the one reviewed. Nothing was sent.',
  _ => 'Something went wrong. Nothing was charged by this step.',
};

class MarketCreationController extends ChangeNotifier {
  MarketCreationController({
    required MarketCreationClient client,
    String Function()? newKey,
  }) : _client = client,
       _newKey = newKey ?? (() => const Uuid().v4());

  final MarketCreationClient _client;
  final String Function() _newKey;
  bool _disposed = false;

  MarketCreationStatus? status;
  String? statusError;
  bool loadingStatus = false;

  List<MarketProposal> mine = const [];
  bool loadingMine = false;
  String? mineError;

  ReviewQueue? queue;
  bool loadingQueue = false;
  String? queueError;

  final Set<String> _busy = {};
  bool isBusy(String proposalId) => _busy.contains(proposalId);

  // One key per draft content, reused on retry so a dropped reply can never
  // create a second proposal.
  String? _draftKey;
  String? _draftFingerprint;
  bool proposing = false;

  MarketCreationRules get rules => status?.rules ?? const MarketCreationRules();
  bool get isReviewer => status?.viewerIsReviewer ?? false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadStatus() async {
    loadingStatus = true;
    statusError = null;
    _notify();
    try {
      status = await _client.status();
    } catch (error) {
      statusError = _messageOf(error);
    } finally {
      loadingStatus = false;
      _notify();
    }
  }

  Future<void> loadMine() async {
    loadingMine = true;
    mineError = null;
    _notify();
    try {
      mine = await _client.mine();
      for (final p in mine) {
        _known[p.id] = p;
      }
    } catch (error) {
      mineError = _messageOf(error);
    } finally {
      loadingMine = false;
      _notify();
    }
  }

  Future<void> loadQueue() async {
    if (!isReviewer) return;
    loadingQueue = true;
    queueError = null;
    _notify();
    try {
      final loaded = await _client.reviewQueue();
      queue = loaded;
      for (final p in [...loaded.pending, ...loaded.approved]) {
        _known[p.id] = p;
      }
    } catch (error) {
      queueError = _messageOf(error);
    } finally {
      loadingQueue = false;
      _notify();
    }
  }

  /// Send a normalised, locally valid draft. Throws [CallsException].
  Future<MarketProposal> propose(MarketDraft draft) async {
    final fingerprint = jsonEncode(draft.toJson(idempotencyKey: ''));
    if (_draftFingerprint != fingerprint) {
      _draftFingerprint = fingerprint;
      _draftKey = _newKey();
    }
    proposing = true;
    _notify();
    try {
      final proposal = await _client.propose(draft, idempotencyKey: _draftKey!);
      _draftKey = null;
      _draftFingerprint = null;
      _upsert(proposal);
      return proposal;
    } finally {
      proposing = false;
      _notify();
    }
  }

  Future<MarketProposal?> _act(
    String proposalId,
    Future<MarketProposal> Function() action,
    void Function(String message) onError,
  ) async {
    if (!_busy.add(proposalId)) return null;
    _notify();
    try {
      final updated = await action();
      _upsert(updated);
      return updated;
    } catch (error) {
      onError(_messageOf(error));
      return null;
    } finally {
      _busy.remove(proposalId);
      _notify();
    }
  }

  Future<MarketProposal?> refresh(
    String proposalId, {
    required void Function(String) onError,
  }) => _act(proposalId, () async {
    final current = find(proposalId);
    return current?.status == ProposalStatus.publishing
        ? _client.refreshPublish(proposalId)
        : _client.get(proposalId);
  }, onError);

  Future<MarketProposal?> withdraw(
    String proposalId, {
    required void Function(String) onError,
  }) => _act(proposalId, () => _client.withdraw(proposalId), onError);

  Future<MarketProposal?> approve(
    String proposalId, {
    required void Function(String) onError,
  }) => _act(proposalId, () => _client.approve(proposalId), onError);

  Future<MarketProposal?> reject(
    String proposalId, {
    required ReviewReason reason,
    String? note,
    required void Function(String) onError,
  }) => _act(
    proposalId,
    () => _client.reject(proposalId, reason: reason, note: note),
    onError,
  );

  // The newest copy of every proposal this controller has seen.
  final Map<String, MarketProposal> _known = {};

  MarketProposal? find(String proposalId) => _known[proposalId];

  /// Keep every list consistent with the newest copy of a proposal.
  void accept(MarketProposal proposal) {
    _upsert(proposal);
    _notify();
  }

  void _upsert(MarketProposal proposal) {
    _known[proposal.id] = proposal;
    if (proposal.viewerIsProposer) {
      final index = mine.indexWhere((p) => p.id == proposal.id);
      mine = [
        if (index < 0) proposal,
        for (final p in mine) p.id == proposal.id ? proposal : p,
      ];
    }
    final q = queue;
    if (q != null) {
      final rest = [
        ...q.pending,
        ...q.approved,
      ].where((p) => p.id != proposal.id);
      final all = [...rest, proposal];
      queue = ReviewQueue(
        pending: [
          for (final p in all)
            if (p.status == ProposalStatus.pendingReview) p,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        approved: [
          for (final p in all)
            if (p.status == ProposalStatus.approved ||
                p.status == ProposalStatus.publishing)
              p,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );
    }
  }

  MarketCreationClient get client => _client;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

enum PublishPhase { idle, preparing, review, signing, submitting, done, failed }

class PublishMarketController extends ChangeNotifier {
  PublishMarketController({
    required MarketCreationClient client,
    required this.proposal,
    required this.wallet,
    required PantaWalletPort walletPort,
    DateTime Function()? now,
  }) : _client = client,
       _walletPort = walletPort,
       _now = now ?? (() => DateTime.now().toUtc());

  final MarketCreationClient _client;
  final PantaWalletPort _walletPort;
  final DateTime Function() _now;
  final String wallet;
  MarketProposal proposal;
  bool _disposed = false;

  PublishPhase phase = PublishPhase.idle;
  PublishReview? review;
  String? error;
  String? _signed; // base64; memory only

  /// True once signed bytes exist: the create may already be on its way.
  bool get submitted => _signed != null;
  bool get canDismiss =>
      phase != PublishPhase.signing && phase != PublishPhase.submitting;
  bool get reviewExpired =>
      review != null && !_now().isBefore(review!.expiresAt);

  void _set(PublishPhase next, {String? message}) {
    phase = next;
    error = message;
    if (!_disposed) notifyListeners();
  }

  /// Fetch a fresh quote + unsigned create. Nothing is signed.
  Future<void> prepare() async {
    if (submitted) return;
    _set(PublishPhase.preparing);
    try {
      final fresh = await _client.preparePublish(proposal.id, wallet);
      if (fresh.wallet != wallet || fresh.proposalId != proposal.id) {
        throw const CreateTransactionRejected();
      }
      checkUnsignedCreate(base64Decode(fresh.transaction), wallet);
      review = fresh;
      _set(PublishPhase.review);
    } catch (e) {
      review = null;
      _set(PublishPhase.failed, message: _messageOf(e));
    }
  }

  /// Ask the wallet to sign the reviewed create, then submit it.
  Future<void> approveAndSubmit() async {
    if (_signed != null) return submit();
    final current = review;
    if (current == null || phase != PublishPhase.review) return;
    if (reviewExpired) {
      _set(
        PublishPhase.failed,
        message:
            'This quote expired before approval. Get a fresh quote; nothing was signed.',
      );
      review = null;
      return;
    }
    _set(PublishPhase.signing);
    try {
      final unsigned = base64Decode(current.transaction);
      final Uint8List signed = await _walletPort.signTransaction(unsigned);
      checkSignedCreate(unsigned, signed, wallet);
      _signed = base64Encode(signed);
    } catch (e) {
      _set(PublishPhase.review, message: _messageOf(e));
      return;
    }
    await submit();
  }

  /// Submit (or re-submit) the identical signed bytes.
  Future<void> submit() async {
    final signed = _signed, current = review;
    if (signed == null || current == null) return;
    _set(PublishPhase.submitting);
    try {
      proposal = await _client.submitPublish(
        proposalId: proposal.id,
        sessionId: current.sessionId,
        signedTransaction: signed,
      );
      _set(PublishPhase.done);
    } on CallsRejectedException catch (e) {
      // A definite refusal: the server will never broadcast these bytes (it
      // refuses a second create while one is in flight), so drop them and
      // offer a fresh quote instead of a retry that can only fail again.
      _signed = null;
      review = null;
      _set(PublishPhase.failed, message: e.message);
    } catch (e) {
      // Offline or a server error: the approval may have arrived and been
      // broadcast. Retry sends the identical bytes only, never a new quote.
      _set(PublishPhase.failed, message: _messageOf(e));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _signed = null;
    super.dispose();
  }
}
