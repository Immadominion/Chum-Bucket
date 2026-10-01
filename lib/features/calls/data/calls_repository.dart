/// The seam between the mobile call slice and whatever serves it.
///
/// Packet C ships against [MockCallsRepository]. When Packet B's BFF routes
/// land, a `BffCallsRepository` implements this same interface on top of the
/// existing `_postMutation(procedurePath, input)` transport
/// (`arena_backend_service.dart:458`) and nothing above this file changes.
///
/// Everything crossing this seam is either a FROZEN contract type from
/// `call_models.dart` or a view model declared here. No screen constructs a
/// venue payload and no screen knows a provider's wire shape (contract §4).
library;

import 'package:chumbucket/features/calls/data/call_models.dart';

// ---------------------------------------------------------------------------
// Failures — one per reachable UI state
// ---------------------------------------------------------------------------

/// Base class so a screen can branch on kind without string-matching.
sealed class CallsException implements Exception {
  final String message;
  const CallsException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

/// The device (or the BFF) is unreachable. Distinct from [CallsFailure] so the
/// UI can offer "you're offline" rather than "something went wrong".
class CallsOfflineException extends CallsException {
  const CallsOfflineException([
    super.message = 'No connection. Showing what we already had.',
  ]);
}

/// The action requires a signed-in canonical user. Reading never throws this;
/// only writing does. Wallet is **not** what is being asked for.
class CallsSignedOutException extends CallsException {
  const CallsSignedOutException([super.message = 'Sign in to make this call.']);
}

/// The request was understood and refused (closed market, thesis too long,
/// responding to your own call, …).
class CallsRejectedException extends CallsException {
  const CallsRejectedException(super.message);
}

/// Anything else.
class CallsFailure extends CallsException {
  const CallsFailure([super.message = 'Something went wrong.']);
}

// ---------------------------------------------------------------------------
// View models
// ---------------------------------------------------------------------------

/// Feed selector. Mirrors `ArenaFeedMode` (`arena_provider.dart:17`) — one enum
/// plus one branch is the entire feed-mode machinery.
enum CallFeedMode {
  global('Global'),
  following('Following');

  const CallFeedMode(this.label);
  final String label;
}

/// A person, keyed by the canonical `public.users.id`.
///
/// [walletAddress] is a **linked credential**, not the identity, and is null
/// for a wallet-less account — the default in this slice.
class Person {
  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final String? walletAddress;

  /// Settled calls only. `VOID` calls are excluded from both numerator and
  /// denominator — a void is never a win and never a loss.
  final int settledCalls;
  final int correctCalls;

  const Person({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarUrl,
    this.walletAddress,
    this.settledCalls = 0,
    this.correctCalls = 0,
  });

  /// Null when there is nothing settled yet — never render "0%" for "no data".
  double? get accuracy =>
      settledCalls == 0 ? null : correctCalls / settledCalls;

  String get initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}';
    return parts.first.substring(0, 1);
  }
}

/// One row of the feed: the immutable [call], who made it, the market it is
/// about, and the derived result once the venue has published one.
class CallFeedEntry {
  final Call call;
  final Person author;
  final VenueMarket market;
  final CallResult? result;

  /// Social counts on this specific call. These are engagement counts, not a
  /// crowd forecast — see [CrowdSplit] for the gated aggregate.
  final int backCount;
  final int fadeCount;

  /// True when the viewer already has their own call on [market].
  final bool viewerHasCalled;

  const CallFeedEntry({
    required this.call,
    required this.author,
    required this.market,
    this.result,
    this.backCount = 0,
    this.fadeCount = 0,
    this.viewerHasCalled = false,
  });

  CallOutcome get outcome =>
      result?.outcome ??
      deriveCallOutcome(side: call.side, resolution: result?.resolution);

  /// A receipt is only shareable once the venue has actually settled it.
  bool get isShareableReceipt => outcome.isSettled;

  CallFeedEntry copyWith({
    CallResult? result,
    int? backCount,
    int? fadeCount,
    bool? viewerHasCalled,
  }) => CallFeedEntry(
    call: call,
    author: author,
    market: market,
    result: result ?? this.result,
    backCount: backCount ?? this.backCount,
    fadeCount: fadeCount ?? this.fadeCount,
    viewerHasCalled: viewerHasCalled ?? this.viewerHasCalled,
  );
}

/// A page of feed rows plus the freshness metadata every state depends on.
class CallFeedPage {
  final List<CallFeedEntry> entries;
  final String? nextCursor;

  /// Unix ms the server produced this page. Drives the "stale" state.
  final int servedAt;

  /// True when this came from a local cache because the network was not
  /// reachable. The UI must say so rather than present it as live.
  final bool fromCache;

  const CallFeedPage({
    required this.entries,
    required this.servedAt,
    this.nextCursor,
    this.fromCache = false,
  });

  static const CallFeedPage empty = CallFeedPage(entries: [], servedAt: 0);
}

/// How the community called a market. **Only ever non-null once the viewer has
/// locked their own call** — the repository is what enforces that, so no screen
/// can leak it early.
class CrowdSplit {
  final String marketId;
  final int yesCalls;
  final int noCalls;

  const CrowdSplit({
    required this.marketId,
    required this.yesCalls,
    required this.noCalls,
  });

  int get total => yesCalls + noCalls;
  double? get yesShare => total == 0 ? null : yesCalls / total;
}

/// Everything the market detail screen renders.
class MarketDetail {
  final SharePriceSnapshot? sharePrice;
  final VenueMarket market;

  /// The venue's latest published price. Null when never synced.
  final MarketSnapshot? snapshot;

  /// The viewer's own call on this market, if any.
  final CallFeedEntry? viewerCall;

  /// Null until the viewer has locked a call. See [CrowdSplit].
  final CrowdSplit? crowdSplit;

  /// Unix ms this detail was served.
  final int servedAt;
  final bool fromCache;

  const MarketDetail({
    this.sharePrice,
    required this.market,
    required this.snapshot,
    required this.servedAt,
    this.viewerCall,
    this.crowdSplit,
    this.fromCache = false,
  });

  bool get viewerHasCalled => viewerCall != null;
}

/// A targeted rematch invitation created by a `challenge` response.
///
/// **Not a frozen contract type.** §3 freezes `CallResponse.kind = 'challenge'`
/// but declares no invitation shape, so this is Packet-C local and deliberately
/// carries no amount, no escrow and no transaction — a challenge is a dare to
/// go on record, not a wager.
class ChallengeInvitation {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String marketId;
  final String sourceCallId;
  final String responseId;
  final String? note;
  final int createdAt;

  const ChallengeInvitation({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.marketId,
    required this.sourceCallId,
    required this.responseId,
    required this.createdAt,
    this.note,
  });

  /// Structurally true. There is no field that could make it false.
  bool get hasEscrow => false;
}

/// The full picture behind one call — used by the detail screen and by deep
/// link resolution.
class CallDetail {
  final CallFeedEntry entry;

  /// The call this one came from, when [Call.parentCallId] is set.
  final CallFeedEntry? parent;

  /// Responses made to this call.
  final List<CallResponse> responses;

  const CallDetail({
    required this.entry,
    this.parent,
    this.responses = const [],
  });
}

/// A person's page: who they are plus their calls.
class PersonDetail {
  final Person person;
  final List<CallFeedEntry> calls;
  final bool viewerIsFollowing;
  final int servedAt;

  const PersonDetail({
    required this.person,
    required this.calls,
    this.viewerIsFollowing = false,
    required this.servedAt,
  });
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// Composer output. Note what is *absent*: no amount, no wallet, no signature.
class CreateCallInput {
  final String marketId;
  final Side side;

  /// `[0,1]`, optional and self-reported.
  final double? confidence;

  /// `<= 280` chars, optional.
  final String? thesis;
  final CallVisibility visibility;

  /// The snapshot the user saw when they locked. Pins [Call.entryProbability].
  final String? snapshotId;

  /// Set by Back/Fade so the new call records where it came from.
  final String? parentCallId;

  const CreateCallInput({
    required this.marketId,
    required this.side,
    this.confidence,
    this.thesis,
    this.visibility = CallVisibility.public,
    this.snapshotId,
    this.parentCallId,
  });

  /// Client-side mirror of the server rule. Returns null when valid.
  String? validate() {
    if (thesis != null && thesis!.length > kThesisMaxLength) {
      return 'Keep your thesis to $kThesisMaxLength characters.';
    }
    if (confidence != null && (confidence! < 0 || confidence! > 1)) {
      return 'Confidence must be between 0 and 100%.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'marketId': marketId,
    'side': side.wire,
    'confidence': confidence,
    'thesis': thesis,
    'visibility': visibility.wire,
    'snapshotId': snapshotId,
    'parentCallId': parentCallId,
  };
}

/// Back / Fade / Challenge.
class RespondToCallInput {
  final String targetCallId;
  final CallResponseKind kind;

  /// Carried into the responder's own call for back/fade. Ignored for a
  /// challenge, which creates no call for the actor.
  final double? confidence;
  final String? thesis;
  final CallVisibility visibility;

  const RespondToCallInput({
    required this.targetCallId,
    required this.kind,
    this.confidence,
    this.thesis,
    this.visibility = CallVisibility.public,
  });

  Map<String, dynamic> toJson() => {
    'targetCallId': targetCallId,
    'kind': kind.wire,
    'confidence': confidence,
    'thesis': thesis,
    'visibility': visibility.wire,
  };
}

/// What a response produced.
///
/// * `back`  → [resultingCall] is the actor's OWN call on the same side.
/// * `fade`  → [resultingCall] is the actor's OWN call on the opposite side.
/// * `challenge` → [resultingCall] is null and [invitation] is set.
class CallResponseResult {
  final CallResponse response;
  final CallFeedEntry? resultingCall;
  final ChallengeInvitation? invitation;

  const CallResponseResult({
    required this.response,
    this.resultingCall,
    this.invitation,
  });
}

// ---------------------------------------------------------------------------
// The interface
// ---------------------------------------------------------------------------

/// Reads never require a signed-in user. Writes always do — and "signed in"
/// means a canonical `public.users.id`, never a wallet.
/// Optional discovery capability, deliberately separate from callable markets.
abstract interface class CallsCatalogRepository {
  Future<List<VenueMarket>> fetchMarketCatalog();
}

abstract class CallsRepository {
  /// Feed of public calls. [viewerUserId] is optional; when null the
  /// [CallFeedMode.following] mode is unavailable and rows come back with
  /// `viewerHasCalled == false`.
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  });

  /// Markets a call can be made on right now.
  Future<List<VenueMarket>> fetchOpenMarkets({String? category});

  /// One market, its latest venue snapshot, and — only if the viewer has
  /// already locked a call on it — the crowd split.
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  });

  /// One call plus its lineage and responses. Used by deep links.
  Future<CallDetail> fetchCall({required String callId, String? viewerUserId});

  /// One person plus their calls. Used by deep links.
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  });

  /// Follow/unfollow a canonical person. The server derives the actor from a
  /// verified session; [viewerUserId] is only a local signed-in guard.
  Future<bool> setFollowing({
    required String personId,
    required bool following,
    required String? viewerUserId,
  });

  /// Lock a new, free, immutable call. Throws [CallsSignedOutException] when
  /// [viewerUserId] is null and [CallsRejectedException] when the market is
  /// not accepting calls.
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  });

  /// Back, Fade or Challenge. Back and Fade create the actor's own call.
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  });

  /// Invitations addressed to [viewerUserId]. No escrow, ever.
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  });

  /// A shareable link for a call or a person. Kept on the repository because
  /// the host is server configuration, not a client constant.
  String shareLinkForCall(String callId);
  String shareLinkForPerson(String handleOrId);
}
