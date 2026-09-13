/// The typed constructors — the only way to build an [AnalyticsEvent].
///
/// One function per name in [AnalyticsEventName], and sixteen names is the
/// whole surface. A call site cannot pass a string here, so `call_backd` is a
/// compile error rather than a seventeenth event that quietly splits the
/// experiment's counts in half.
///
/// ## On `String` parameters
///
/// `lib/core/**` must not import a feature, so the FROZEN contract enums
/// (`Side`, `CallOutcome`, `MarketStatus`, …) cannot appear in these
/// signatures. Where one is wanted, the parameter takes its **wire token** and
/// the call site passes `side.wire`, `outcome.wire`, `venue.wire`. The privacy
/// guard then rejects anything that is not a short whitespace-free token, so a
/// screen cannot slip prose in through one of these.
///
/// Analytics-local vocabularies ([AnalyticsSurface], [AnalyticsShareChannel],
/// [AnalyticsLinkKind], [ThesisLengthBucket]) are enums, because nothing else
/// owns them.
///
/// ## On `occurredAtMs`
///
/// Optional; defaults to now. It participates in the dedupe key of the events
/// that can genuinely repeat, so **retrying means re-recording the same event
/// value**, not calling the constructor again. `AnalyticsRecorder.record` is
/// idempotent for the same value.
library;

import 'package:chumbucket/core/analytics/analytics_event.dart';

int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

abstract final class AnalyticsEvents {
  // ---------------------------------------------------------------------
  // Feed and reading
  // ---------------------------------------------------------------------

  /// A call card was actually on screen. Deduplicated for the whole session by
  /// `(surface, callId)`, so a rebuild, a `setState`, a keep-alive restore or a
  /// scroll back up cannot inflate it. See `CallImpressionTracker`.
  static AnalyticsEvent feedCallImpression({
    required String callId,
    required String marketId,
    required String authorId,
    required AnalyticsSurface surface,
    required int position,
    String? side,
    String? outcome,
    String? venue,
    bool? venueIsDemo,
    bool? thesisPresent,
    ThesisLengthBucket? thesisLengthBucket,
    bool? viewerIsSignedIn,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.feedCallImpression,
    props: {
      AnalyticsProps.callId: callId,
      AnalyticsProps.marketId: marketId,
      AnalyticsProps.authorId: authorId,
      AnalyticsProps.surface: surface.wire,
      AnalyticsProps.position: position,
      AnalyticsProps.side: side,
      AnalyticsProps.outcome: outcome,
      AnalyticsProps.venue: venue,
      AnalyticsProps.venueIsDemo: venueIsDemo,
      AnalyticsProps.thesisPresent: thesisPresent,
      AnalyticsProps.thesisLengthBucket: thesisLengthBucket?.wire,
      AnalyticsProps.viewerIsSignedIn: viewerIsSignedIn,
    },
    dedupeParts: [surface.wire, callId],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  /// Somebody opened one specific call. Repeatable — opening the same call
  /// tomorrow is a second, real open.
  static AnalyticsEvent callOpened({
    required String callId,
    required AnalyticsSurface surface,
    String? marketId,
    String? authorId,
    String? side,
    String? outcome,
    bool? viewerIsSignedIn,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.callOpened,
      props: {
        AnalyticsProps.callId: callId,
        AnalyticsProps.surface: surface.wire,
        AnalyticsProps.marketId: marketId,
        AnalyticsProps.authorId: authorId,
        AnalyticsProps.side: side,
        AnalyticsProps.outcome: outcome,
        AnalyticsProps.viewerIsSignedIn: viewerIsSignedIn,
      },
      dedupeParts: [callId, surface.wire, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  // ---------------------------------------------------------------------
  // Calling
  // ---------------------------------------------------------------------

  /// A free call was locked. [fromResponse] and [responseKind] are the whole
  /// point of the §9 go signal *"at least 30% of new calls originate from
  /// another person's Back/Fade card"* — they are what makes that measurable.
  static AnalyticsEvent callCreated({
    required String callId,
    required String marketId,
    required String side,
    required String visibility,
    required bool fromResponse,
    String? responseKind,
    String? parentCallId,
    bool? confidencePresent,
    bool? thesisPresent,
    ThesisLengthBucket? thesisLengthBucket,
    num? entryProbability,
    AnalyticsSurface? surface,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.callCreated,
    props: {
      AnalyticsProps.callId: callId,
      AnalyticsProps.marketId: marketId,
      AnalyticsProps.side: side,
      AnalyticsProps.visibility: visibility,
      AnalyticsProps.fromResponse: fromResponse,
      AnalyticsProps.responseKind: responseKind,
      AnalyticsProps.parentCallId: parentCallId,
      AnalyticsProps.confidencePresent: confidencePresent,
      AnalyticsProps.thesisPresent: thesisPresent,
      AnalyticsProps.thesisLengthBucket: thesisLengthBucket?.wire,
      AnalyticsProps.entryProbability: entryProbability,
      AnalyticsProps.surface: surface?.wire,
    },
    dedupeParts: [callId],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  /// Backed somebody: the actor's own call agrees with the target's side.
  static AnalyticsEvent callBacked({
    required String responseId,
    required String targetCallId,
    String? resultingCallId,
    String? marketId,
    String? side,
    AnalyticsSurface? surface,
    int? occurredAtMs,
  }) => _response(
    name: AnalyticsEventName.callBacked,
    responseId: responseId,
    targetCallId: targetCallId,
    resultingCallId: resultingCallId,
    marketId: marketId,
    side: side,
    surface: surface,
    occurredAtMs: occurredAtMs,
  );

  /// Faded somebody: the actor's own call takes the opposite side.
  static AnalyticsEvent callFaded({
    required String responseId,
    required String targetCallId,
    String? resultingCallId,
    String? marketId,
    String? side,
    AnalyticsSurface? surface,
    int? occurredAtMs,
  }) => _response(
    name: AnalyticsEventName.callFaded,
    responseId: responseId,
    targetCallId: targetCallId,
    resultingCallId: resultingCallId,
    marketId: marketId,
    side: side,
    surface: surface,
    occurredAtMs: occurredAtMs,
  );

  /// A rematch invitation. There is no escrow and no amount, so there is
  /// nothing money-shaped to record.
  static AnalyticsEvent challengeSent({
    required String responseId,
    required String targetCallId,
    String? marketId,
    String? personId,
    AnalyticsSurface? surface,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.challengeSent,
    props: {
      AnalyticsProps.responseId: responseId,
      AnalyticsProps.targetCallId: targetCallId,
      AnalyticsProps.marketId: marketId,
      AnalyticsProps.personId: personId,
      AnalyticsProps.surface: surface?.wire,
    },
    dedupeParts: [responseId],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  static AnalyticsEvent _response({
    required AnalyticsEventName name,
    required String responseId,
    required String targetCallId,
    String? resultingCallId,
    String? marketId,
    String? side,
    AnalyticsSurface? surface,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: name,
    props: {
      AnalyticsProps.responseId: responseId,
      AnalyticsProps.targetCallId: targetCallId,
      AnalyticsProps.callId: resultingCallId,
      AnalyticsProps.marketId: marketId,
      AnalyticsProps.side: side,
      AnalyticsProps.surface: surface?.wire,
    },
    dedupeParts: [responseId],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  // ---------------------------------------------------------------------
  // Social graph
  // ---------------------------------------------------------------------

  /// §9 go signal: *"at least five users follow somebody because of a
  /// category-specific record"*. [surface] is what makes "because of" legible —
  /// a follow from a person page after reading a record is not a follow from a
  /// feed row.
  static AnalyticsEvent followCreated({
    required String personId,
    required AnalyticsSurface surface,
    String? callId,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.followCreated,
    props: {
      AnalyticsProps.personId: personId,
      AnalyticsProps.surface: surface.wire,
      AnalyticsProps.callId: callId,
    },
    dedupeParts: [personId],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  // ---------------------------------------------------------------------
  // Sharing
  // ---------------------------------------------------------------------

  /// A share sheet was opened. The URL is never recorded — a share link
  /// carries a `?ref=` handle, and a handle is user-authored.
  static AnalyticsEvent shareStarted({
    required AnalyticsLinkKind linkKind,
    required AnalyticsShareChannel channel,
    String? callId,
    String? personId,
    String? outcome,
    AnalyticsSurface? surface,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.shareStarted,
      props: {
        AnalyticsProps.linkKind: linkKind.wire,
        AnalyticsProps.channel: channel.wire,
        AnalyticsProps.callId: callId,
        AnalyticsProps.personId: personId,
        AnalyticsProps.outcome: outcome,
        AnalyticsProps.surface: surface?.wire,
      },
      dedupeParts: [linkKind.wire, channel.wire, callId ?? personId, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  /// Somebody arrived on a shared link. [hasReferrer] records only *that* the
  /// link named a sharer, never who.
  static AnalyticsEvent shareOpened({
    required AnalyticsLinkKind linkKind,
    required bool hasReferrer,
    String? callId,
    String? personId,
    bool? viewerIsSignedIn,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.shareOpened,
      props: {
        AnalyticsProps.linkKind: linkKind.wire,
        AnalyticsProps.hasReferrer: hasReferrer,
        AnalyticsProps.callId: callId,
        AnalyticsProps.personId: personId,
        AnalyticsProps.surface: AnalyticsSurface.deepLink.wire,
        AnalyticsProps.viewerIsSignedIn: viewerIsSignedIn,
      },
      dedupeParts: [linkKind.wire, callId ?? personId, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  // ---------------------------------------------------------------------
  // Wallet link (contract §0.3 — a wallet is a credential, never an identity)
  // ---------------------------------------------------------------------

  /// The person tapped "Connect wallet" or "Fund this call". **No address, no
  /// nonce, no signature** — those are exactly what the guard exists to stop,
  /// and none of them is needed to count funnel steps.
  static AnalyticsEvent walletLinkStarted({
    required AnalyticsSurface surface,
    String? callId,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.walletLinkStarted,
      props: {
        AnalyticsProps.surface: surface.wire,
        AnalyticsProps.callId: callId,
      },
      dedupeParts: [surface.wire, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  /// The SIWS proof verified server-side and a wallet is now linked.
  static AnalyticsEvent walletLinkSucceeded({
    required AnalyticsSurface surface,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.walletLinkSucceeded,
      props: {
        AnalyticsProps.surface: surface.wire,
        AnalyticsProps.succeeded: true,
      },
      dedupeParts: [surface.wire, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  // ---------------------------------------------------------------------
  // Funded slice (feature-flagged off; instrumented so the flag can be
  // evaluated the day it is turned on)
  // ---------------------------------------------------------------------

  /// A fresh executable quote was shown. **No price, no maximum spend, no
  /// fee** — the guard denies every money-shaped key, and the funnel question
  /// is "how many people saw a quote", not "how much".
  static AnalyticsEvent fundQuoteViewed({
    required String callId,
    required String marketId,
    String? side,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.fundQuoteViewed,
      props: {
        AnalyticsProps.callId: callId,
        AnalyticsProps.marketId: marketId,
        AnalyticsProps.side: side,
      },
      dedupeParts: [callId, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  /// The wallet signed and the transaction was submitted. Contract §3:
  /// submitted is **not** funded, and [AnalyticsProps.fundingState] says
  /// `SUBMITTED` so no dashboard can later read this as money in.
  static AnalyticsEvent fundOrderSigned({
    required String orderId,
    required String callId,
    String? marketId,
    String? side,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.fundOrderSigned,
    props: {
      AnalyticsProps.orderId: orderId,
      AnalyticsProps.callId: callId,
      AnalyticsProps.marketId: marketId,
      AnalyticsProps.side: side,
      AnalyticsProps.fundingState: 'SUBMITTED',
    },
    dedupeParts: [orderId],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  /// The venue confirmed the fill — the only event in this file that may mean
  /// "funded". [fundingState] is passed through verbatim so `PARTIAL` and
  /// `FAILED` cannot be rounded up to `FILLED`.
  static AnalyticsEvent fundOrderConfirmed({
    required String orderId,
    required String callId,
    required String fundingState,
    String? marketId,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.fundOrderConfirmed,
    props: {
      AnalyticsProps.orderId: orderId,
      AnalyticsProps.callId: callId,
      AnalyticsProps.fundingState: fundingState,
      AnalyticsProps.marketId: marketId,
    },
    dedupeParts: [orderId, fundingState],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  // ---------------------------------------------------------------------
  // Receipts — the artefact the free loop exists to produce
  // ---------------------------------------------------------------------

  static AnalyticsEvent receiptViewed({
    required String callId,
    required bool settled,
    required AnalyticsSurface surface,
    String? marketId,
    String? outcome,
    String? venue,
    bool? venueIsDemo,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.receiptViewed,
      props: {
        AnalyticsProps.callId: callId,
        AnalyticsProps.settled: settled,
        AnalyticsProps.surface: surface.wire,
        AnalyticsProps.marketId: marketId,
        AnalyticsProps.outcome: outcome,
        AnalyticsProps.venue: venue,
        AnalyticsProps.venueIsDemo: venueIsDemo,
      },
      dedupeParts: [callId, surface.wire, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }

  static AnalyticsEvent receiptShared({
    required String callId,
    required AnalyticsShareChannel channel,
    String? outcome,
    String? marketId,
    int? occurredAtMs,
  }) {
    final at = occurredAtMs ?? _now();
    return AnalyticsEvent.internal(
      name: AnalyticsEventName.receiptShared,
      props: {
        AnalyticsProps.callId: callId,
        AnalyticsProps.channel: channel.wire,
        AnalyticsProps.outcome: outcome,
        AnalyticsProps.marketId: marketId,
      },
      dedupeParts: [callId, channel.wire, at],
      dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
      occurredAtMs: at,
    );
  }
}
