/// The receipt view model.
///
/// A receipt is the artefact the whole free loop exists to produce: proof that
/// a named person said a specific thing, at a specific moment, before the
/// answer was known.
///
/// It therefore carries exactly five things and no more:
///
/// 1. the original timestamp ([lockedAt]),
/// 2. the exact side ([side] / [sideLabel]),
/// 3. the entry probability ([entryProbability]),
/// 4. the result ([outcome] / [resolution]),
/// 5. the source market ([marketQuestion], [venueLabel], [marketResolutionId]).
///
/// **There is no stake field, and there must never be one.** The class is the
/// enforcement: a widget cannot render an amount it was never handed, and
/// [CallReceipt.fromEntry] reads nothing money-shaped off the call.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';

class CallReceipt {
  final SharePriceSnapshot? entryPrice;
  final String callId;
  final String personDisplayName;
  final String personHandle;

  /// When the call was locked — the instant it stopped being editable.
  final DateTime lockedAt;

  final Side side;

  /// The venue's own wording for that side.
  final String sideLabel;

  /// The probability the call was stamped with. Null when the venue had
  /// published no price; renders as an em dash, never as 0%.
  final double? entryProbability;

  final CallOutcome outcome;
  final Resolution? resolution;
  final DateTime? resolvedAt;

  /// Source market, verbatim.
  final String marketQuestion;
  final String venueLabel;
  final bool venueIsDemo;
  final String? resolutionSource;

  /// The venue evidence the result was derived from.
  final String? marketResolutionId;

  /// The venue's own market address, for a public "Resolved by" link.
  final String? venueMarketId;

  /// True when the author backed this call with a confirmed Panta fill.
  /// A yes/no fact only: the receipt never carries an amount.
  final bool fundedOnPanta;

  /// A free call (`NONE`, no confirmed fill): the receipt is stamped Free.
  /// A call part-way to funding is neither free nor funded.
  final bool free;

  final String shareUrl;

  const CallReceipt({
    this.entryPrice,
    required this.callId,
    required this.personDisplayName,
    required this.personHandle,
    required this.lockedAt,
    required this.side,
    required this.sideLabel,
    required this.entryProbability,
    required this.outcome,
    required this.resolution,
    required this.resolvedAt,
    required this.marketQuestion,
    required this.venueLabel,
    required this.venueIsDemo,
    required this.resolutionSource,
    required this.marketResolutionId,
    required this.shareUrl,
    this.venueMarketId,
    this.fundedOnPanta = false,
    this.free = true,
  });

  /// Panta's public market page, never the authenticated API URL.
  bool get resolvedByPanta => venueLabel == 'Panta' && venueMarketId != null;

  /// A receipt is only honest once the venue has actually settled the call.
  /// A pending call gets a "pending" card, not a receipt.
  bool get isSettled => outcome.isSettled;

  /// VOID is neither a win nor a loss and the receipt says so in those words.
  bool get isVoid => outcome == CallOutcome.voided;

  factory CallReceipt.fromEntry(
    CallFeedEntry entry, {
    required String shareUrl,
  }) {
    final call = entry.call;
    final market = entry.market;
    return CallReceipt(
      callId: call.id,
      personDisplayName: entry.author.displayName,
      personHandle: entry.author.handle,
      lockedAt: call.lockedAtUtc,
      side: call.side,
      sideLabel: market.labelFor(call.side),
      entryProbability: call.entryProbability,
      entryPrice: call.entryPrice,
      outcome: entry.outcome,
      resolution: entry.result?.resolution,
      resolvedAt: entry.result?.resolvedAtUtc,
      marketQuestion: market.question,
      venueLabel: market.venue.label,
      venueIsDemo: market.venue.isDemo,
      resolutionSource: market.resolutionSource,
      marketResolutionId: entry.result?.marketResolutionId,
      shareUrl: shareUrl,
      venueMarketId: market.venueMarketId.isEmpty ? null : market.venueMarketId,
      fundedOnPanta: entry.isFunded,
      free: !entry.isFunded && call.fundingState.isFree,
    );
  }

  /// The line that goes in the share sheet's text field. Never mentions money.
  String get shareCaption {
    final verdict = switch (outcome) {
      CallOutcome.correct => 'Called it.',
      CallOutcome.incorrect => 'Got this one wrong.',
      CallOutcome.voided => 'Market was cancelled — void, not a loss.',
      CallOutcome.pending => 'On record, still pending.',
    };
    // A demo receipt says so, in the text that actually leaves the app.
    //
    // Every other demo affordance — the badge, the notice, the receipt card's
    // own block — lives on a screen. The caption is the one thing that travels
    // to WhatsApp or X, where none of that chrome follows it. Without this a
    // fixture receipt about a real-world event would post as a real result
    // under the product's name, which is the exact thing the venue labelling
    // exists to prevent.
    final demo = venueIsDemo ? ' [DEMO DATA — not a real market result]' : '';
    final stamp = free ? ' · Free call' : '';
    return '$verdict $marketQuestion — I said $sideLabel$stamp.$demo $shareUrl';
  }
}
