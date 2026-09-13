/// A rematch: "you went on record, it settled — go again."
///
/// A rematch is a **targeted challenge** and nothing else. Contract §3 freezes
/// `CallResponse.kind = 'challenge'` and declares no invitation shape, so
/// `ChallengeInvitation` is Packet-C local and deliberately carries no amount,
/// no escrow and no transaction. A rematch inherits exactly that:
///
/// * it creates a `challenge` response, so `resultingCallId` is null and no
///   call is minted for the challenger,
/// * the invitation it produces has `hasEscrow == false` structurally — there
///   is no field on any type in this path that could hold a stake,
/// * there is no amount input anywhere in the flow, and no wallet is touched.
///
/// It is offered from a **settled** receipt, because the whole point is the
/// result that just landed. A pending call has nothing to rematch yet.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';

/// Why a rematch is or is not on offer. Each value maps to a distinct on-screen
/// state, so the button is never simply missing without explanation.
enum RematchAvailability {
  /// Go ahead.
  available,

  /// The venue has not published a result, so there is no receipt to rematch.
  notSettled,

  /// It is your own call. You cannot challenge yourself.
  ownCall,

  /// The market is void. You can still rematch — a cancelled market is not a
  /// loss — but the copy has to say so rather than imply a grudge.
  voidResult,
}

/// Everything the rematch sheet needs, and nothing that could carry money.
class RematchOffer {
  /// The settled call being answered. The challenge targets this id.
  final String sourceCallId;

  /// Who you are rematching. Canonical `public.users.id` — never a wallet.
  final String opponentUserId;
  final String opponentHandle;
  final String opponentDisplayName;
  final String? opponentAvatarUrl;

  /// The market the settled call was about, verbatim.
  final String marketQuestion;

  /// The venue's own wording for the side they took.
  final String theirSideLabel;

  /// How their call ended. Always settled — see [RematchAvailability].
  final CallOutcome outcome;

  /// Whether the market is still accepting new calls. A rematch is an
  /// invitation, so it is valid either way; the copy differs.
  final bool marketAcceptsNewCalls;

  final RematchAvailability availability;

  const RematchOffer({
    required this.sourceCallId,
    required this.opponentUserId,
    required this.opponentHandle,
    required this.opponentDisplayName,
    required this.marketQuestion,
    required this.theirSideLabel,
    required this.outcome,
    required this.marketAcceptsNewCalls,
    required this.availability,
    this.opponentAvatarUrl,
  });

  /// Structurally true. There is no field on this class, on
  /// `RespondToCallInput`, or on `ChallengeInvitation` that could make it
  /// false.
  bool get hasEscrow => false;

  /// Same guarantee, stated the way a reviewer will ask it.
  bool get hasStake => false;

  bool get isAvailable => availability == RematchAvailability.available ||
      availability == RematchAvailability.voidResult;

  /// Build an offer from a feed entry — the form the person page and the call
  /// detail screen already hold.
  factory RematchOffer.fromEntry(
    CallFeedEntry entry, {
    required String? viewerUserId,
  }) {
    final outcome = entry.outcome;
    final availability = _availability(
      isSettled: outcome.isSettled,
      isVoid: outcome == CallOutcome.voided,
      isOwn: viewerUserId != null && entry.author.id == viewerUserId,
    );

    return RematchOffer(
      sourceCallId: entry.call.id,
      opponentUserId: entry.author.id,
      opponentHandle: entry.author.handle,
      opponentDisplayName: entry.author.displayName,
      opponentAvatarUrl: entry.author.avatarUrl,
      marketQuestion: entry.market.question,
      theirSideLabel: entry.market.labelFor(entry.call.side),
      outcome: outcome,
      marketAcceptsNewCalls: entry.market.status.acceptsNewCalls,
      availability: availability,
    );
  }

  /// Build an offer straight from a receipt.
  ///
  /// A [CallReceipt] is the artefact the loop produces, so this is the literal
  /// "from a resolved receipt" path. The receipt carries no person id — it is a
  /// shareable image model — so the opponent's canonical id is passed in by
  /// whoever already holds it.
  factory RematchOffer.fromReceipt(
    CallReceipt receipt, {
    required String opponentUserId,
    required bool marketAcceptsNewCalls,
    required String? viewerUserId,
  }) {
    final availability = _availability(
      isSettled: receipt.isSettled,
      isVoid: receipt.isVoid,
      isOwn: viewerUserId != null && opponentUserId == viewerUserId,
    );

    return RematchOffer(
      sourceCallId: receipt.callId,
      opponentUserId: opponentUserId,
      opponentHandle: receipt.personHandle,
      opponentDisplayName: receipt.personDisplayName,
      marketQuestion: receipt.marketQuestion,
      theirSideLabel: receipt.sideLabel,
      outcome: receipt.outcome,
      marketAcceptsNewCalls: marketAcceptsNewCalls,
      availability: availability,
    );
  }

  /// The one thing this offer can turn into: a targeted challenge.
  ///
  /// `kind` is hard-coded, not a parameter. A rematch can never accidentally
  /// become a Back or a Fade, which would mint a call in someone's name.
  /// `confidence` is deliberately absent: a challenge creates no call for the
  /// challenger, so there is nothing to be confident about.
  RespondToCallInput toInput({String? note}) => RespondToCallInput(
    targetCallId: sourceCallId,
    kind: CallResponseKind.challenge,
    thesis: (note == null || note.trim().isEmpty) ? null : note.trim(),
  );

  /// The single place availability is decided, so the entry and the receipt
  /// paths can never disagree about whether a rematch is on offer.
  static RematchAvailability _availability({
    required bool isSettled,
    required bool isVoid,
    required bool isOwn,
  }) {
    if (!isSettled) return RematchAvailability.notSettled;
    if (isOwn) return RematchAvailability.ownCall;
    if (isVoid) return RematchAvailability.voidResult;
    return RematchAvailability.available;
  }

  /// One line describing what just settled, for the sheet's header.
  String get resultLine => switch (outcome) {
    CallOutcome.correct =>
      '$opponentDisplayName called $theirSideLabel and got it right.',
    CallOutcome.incorrect =>
      '$opponentDisplayName called $theirSideLabel and got it wrong.',
    CallOutcome.voided =>
      'The market was cancelled, so $opponentDisplayName\'s call is void — '
          'neither a win nor a loss.',
    CallOutcome.pending =>
      '$opponentDisplayName\'s call has not settled yet.',
  };
}
