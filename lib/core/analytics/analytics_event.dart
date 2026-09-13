/// The analytics vocabulary for the people-first vs market-first experiment.
///
/// The roadmap (§9 "Validation and measurement") names sixteen events and no
/// others. [AnalyticsEventName] is that list, closed. There is no
/// `AnalyticsEvent(name: 'whatever')` constructor anywhere in this package —
/// an event can only be built by a typed constructor in `analytics_events.dart`
/// — so a typo is a compile error rather than a silently-new event that
/// splits the experiment's counts.
///
/// ## What may be in a payload
///
/// Everything here is designed around one rule: **the payload is a set of
/// dimensions, not a copy of the screen**. A call/market/person id is a
/// dimension. A thesis, a wallet, a signature, a balance and a display name are
/// not, and `analytics_privacy_guard.dart` rejects them structurally rather
/// than trusting this doc comment.
///
/// Concretely a property value may only be a `bool`, a finite `num`, or a
/// short whitespace-free token/id. No nested maps, no lists, no nulls, no free
/// text. See [AnalyticsPrivacyGuard].
library;

/// The complete, closed set of event names from the roadmap's §9.
///
/// Adding a name here is a deliberate act that must be matched by a typed
/// constructor and a test; nothing else can mint one.
enum AnalyticsEventName {
  feedCallImpression('feed_call_impression'),
  callOpened('call_opened'),
  callCreated('call_created'),
  callBacked('call_backed'),
  callFaded('call_faded'),
  challengeSent('challenge_sent'),
  followCreated('follow_created'),
  shareStarted('share_started'),
  shareOpened('share_opened'),
  walletLinkStarted('wallet_link_started'),
  walletLinkSucceeded('wallet_link_succeeded'),
  fundQuoteViewed('fund_quote_viewed'),
  fundOrderSigned('fund_order_signed'),
  fundOrderConfirmed('fund_order_confirmed'),
  receiptViewed('receipt_viewed'),
  receiptShared('receipt_shared');

  const AnalyticsEventName(this.wire);

  /// The exact string the roadmap names. Never re-cased, never pluralised.
  final String wire;

  /// Only for reading an event back out of a sink in a test. Throws rather
  /// than returning null so an unknown name cannot be silently tolerated.
  static AnalyticsEventName fromWire(String value) => values.firstWhere(
    (n) => n.wire == value,
    orElse:
        () =>
            throw ArgumentError.value(value, 'value', 'Not an analytics event'),
  );
}

/// Where a call was seen or acted on. A closed vocabulary so the two arms of
/// the experiment can be compared surface by surface.
enum AnalyticsSurface {
  feedGlobal('feed_global'),
  feedFollowing('feed_following'),
  personProfile('person_profile'),
  marketDetail('market_detail'),
  callDetail('call_detail'),
  receiptSheet('receipt_sheet'),
  deepLink('deep_link'),
  notification('notification');

  const AnalyticsSurface(this.wire);
  final String wire;
}

/// What a shared or opened link points at. Never the link itself — a share URL
/// can carry a referrer handle, and a handle is user-authored.
enum AnalyticsLinkKind {
  call('call'),
  person('person'),
  receipt('receipt');

  const AnalyticsLinkKind(this.wire);
  final String wire;
}

/// How a share left the app. No URL, no recipient, no message body.
enum AnalyticsShareChannel {
  image('image'),
  link('link'),
  unknown('unknown');

  const AnalyticsShareChannel(this.wire);
  final String wire;
}

/// The *shape* of a thesis, which is all analytics is ever allowed to know
/// about one.
///
/// The full text is user-authored content and never leaves the device through
/// this package; [AnalyticsPrivacyGuard] rejects any payload that carries it.
/// Buckets are wide on purpose: a length in characters is close enough to a
/// fingerprint of a short post that exact lengths are not worth the risk.
enum ThesisLengthBucket {
  none('none'),
  short('short'),
  medium('medium'),
  long('long');

  const ThesisLengthBucket(this.wire);
  final String wire;

  /// Derives the bucket and discards the text in the same expression, so no
  /// caller ever holds a thesis and a payload at the same time.
  ///
  /// 280 is the contract's `kThesisMaxLength`; anything longer still buckets
  /// as [long] rather than throwing — analytics never blocks a flow.
  static ThesisLengthBucket of(String? thesis) {
    final text = thesis?.trim() ?? '';
    if (text.isEmpty) return ThesisLengthBucket.none;
    if (text.length <= 80) return ThesisLengthBucket.short;
    if (text.length <= 180) return ThesisLengthBucket.medium;
    return ThesisLengthBucket.long;
  }
}

/// How an event repeats.
enum AnalyticsDedupePolicy {
  /// At most once per session for its [AnalyticsEvent.dedupeKey]. Used where
  /// the event is tied to a durable artefact (an impression of a given card, a
  /// created call, a follow) and a second delivery would be double counting.
  oncePerSession,

  /// A view or action that genuinely can happen again. The dedupe key pins the
  /// occurrence, so re-emitting *the same event value* is idempotent while a
  /// later genuine occurrence still counts.
  perOccurrence,
}

/// One immutable, already-sanitised analytics event.
///
/// Constructed only from `analytics_events.dart`. [props] is unmodifiable and
/// flat; [dedupeKey] is computed at construction so two equal events dedupe
/// identically no matter where they were built.
class AnalyticsEvent {
  final AnalyticsEventName name;

  /// Flat dimensions. Never contains a secret, a wallet, a signature, a
  /// balance or free text — enforced, not assumed.
  final Map<String, Object> props;

  /// Stable identity for deduplication and retry-idempotency.
  final String dedupeKey;

  final AnalyticsDedupePolicy dedupePolicy;

  /// Unix milliseconds, UTC — the same convention as every other timestamp in
  /// this codebase (contract §3).
  final int occurredAtMs;

  AnalyticsEvent._({
    required this.name,
    required Map<String, Object> props,
    required this.dedupeKey,
    required this.dedupePolicy,
    required this.occurredAtMs,
  }) : props = Map.unmodifiable(props);

  /// The single internal factory every typed constructor funnels through.
  ///
  /// It drops nulls (an absent dimension is absent, never `null`) and turns
  /// enum-ish inputs into their wire tokens before the guard ever sees them.
  factory AnalyticsEvent.internal({
    required AnalyticsEventName name,
    required Map<String, Object?> props,
    required List<Object?> dedupeParts,
    required AnalyticsDedupePolicy dedupePolicy,
    required int occurredAtMs,
  }) {
    final cleaned = <String, Object>{};
    for (final entry in props.entries) {
      final value = entry.value;
      if (value == null) continue;
      cleaned[entry.key] = value;
    }
    final key = <String>[
      name.wire,
      ...dedupeParts.map((p) => p == null ? '-' : '$p'),
    ].join(':');
    return AnalyticsEvent._(
      name: name,
      props: cleaned,
      dedupeKey: key,
      dedupePolicy: dedupePolicy,
      occurredAtMs: occurredAtMs,
    );
  }

  /// Returns a copy carrying the experiment dimensions. Used by
  /// `AnalyticsRecorder` so every event can be split by arm without every call
  /// site remembering to pass the treatment.
  AnalyticsEvent withProps(Map<String, Object> extra) {
    if (extra.isEmpty) return this;
    return AnalyticsEvent._(
      name: name,
      props: {...props, ...extra},
      dedupeKey: dedupeKey,
      dedupePolicy: dedupePolicy,
      occurredAtMs: occurredAtMs,
    );
  }

  Object? operator [](String key) => props[key];

  @override
  String toString() => 'AnalyticsEvent(${name.wire}, $props)';
}

/// Property keys, so a call site cannot invent `market_id` beside `marketId`
/// and split a dimension in two.
abstract final class AnalyticsProps {
  static const String callId = 'callId';
  static const String marketId = 'marketId';
  static const String personId = 'personId';
  static const String authorId = 'authorId';
  static const String parentCallId = 'parentCallId';
  static const String responseId = 'responseId';
  static const String orderId = 'orderId';

  static const String surface = 'surface';
  static const String position = 'position';
  static const String side = 'side';
  static const String outcome = 'outcome';
  static const String resolution = 'resolution';
  static const String marketStatus = 'marketStatus';
  static const String venue = 'venue';
  static const String venueIsDemo = 'venueIsDemo';
  static const String visibility = 'visibility';
  static const String fundingState = 'fundingState';

  static const String thesisPresent = 'thesisPresent';
  static const String thesisLengthBucket = 'thesisLengthBucket';
  static const String confidencePresent = 'confidencePresent';
  static const String entryProbability = 'entryProbability';

  static const String fromResponse = 'fromResponse';
  static const String responseKind = 'responseKind';
  static const String targetCallId = 'targetCallId';
  static const String settled = 'settled';
  static const String channel = 'channel';
  static const String linkKind = 'linkKind';
  static const String hasReferrer = 'hasReferrer';
  static const String succeeded = 'succeeded';
  static const String viewerIsSignedIn = 'viewerIsSignedIn';

  static const String experiment = 'experiment';
  static const String treatment = 'treatment';
}
