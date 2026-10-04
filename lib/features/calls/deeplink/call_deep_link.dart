/// Deep link parsing and resolution for the call slice.
///
/// There is no router, no named routes and no deep-link package in this app
/// (contract §2) — the only intent filter is the Supabase OAuth callback. So
/// this is new work, and it is deliberately split in two:
///
/// * this file is **pure Dart**: parsing a [Uri] into an intent, and resolving
///   that intent against a [CallsRepository]. It imports no Flutter widget
///   library and is unit-tested directly.
/// * `call_deep_link_router.dart` is the thin Navigator wiring.
///
/// The parser returns null for anything it does not own — critically including
/// `dev.cleva.chumbucket://login-callback`, which must keep reaching the auth
/// handler untouched.
library;

import 'package:chumbucket/features/calls/data/calls_repository.dart';

/// Custom schemes the app is registered for.
///
/// `dev.cleva.chumbucket` is the existing scheme (already in the manifest for
/// the OAuth callback). `chumbucket` is the shorter one requested in
/// `docs/contracts/integration-requests/packet-c.md`; until that intent filter
/// lands, only the existing scheme and https links actually arrive — parsing
/// both means nothing has to change here when it does.
const Set<String> kCallDeepLinkSchemes = {'chumbucket', 'dev.cleva.chumbucket'};

/// Hosts whose https links belong to this app.
///
/// Only domains the product actually serves. `chumbucket.fun` is the live site
/// that hosts the landing pages and `/.well-known/assetlinks.json`; the Android
/// manifest claims the same hosts with `android:autoVerify`.
///
/// `chumbucket.app` is deliberately absent: it was never registered (NXDOMAIN),
/// so no working link was ever built on it, and a domain this product does not
/// own must not be treated as its own.
const Set<String> kCallDeepLinkHosts = {'chumbucket.fun', 'www.chumbucket.fun'};

/// What a shared link points at.
sealed class CallDeepLink {
  /// The `?ref=` handle of whoever shared the link, when present. Attribution
  /// only — it grants nothing.
  final String? sharedByHandle;

  const CallDeepLink({this.sharedByHandle});
}

/// `…/c/<callId>` or `…/call/<callId>`.
class CallLinkTarget extends CallDeepLink {
  final String callId;
  const CallLinkTarget(this.callId, {super.sharedByHandle});

  @override
  String toString() => 'CallLinkTarget($callId)';
}

/// `…/u/<handle|userId>` or `…/person/<…>`.
class PersonLinkTarget extends CallDeepLink {
  final String personRef;
  const PersonLinkTarget(this.personRef, {super.sharedByHandle});

  @override
  String toString() => 'PersonLinkTarget($personRef)';
}

/// `…/m/<marketId>` or `…/market/<marketId>`.
class MarketLinkTarget extends CallDeepLink {
  final String marketId;
  const MarketLinkTarget(this.marketId, {super.sharedByHandle});

  @override
  String toString() => 'MarketLinkTarget($marketId)';
}

/// Parse a shared link. Returns null when the URI is not a call-slice link —
/// including every OAuth callback — so other handlers still see it.
CallDeepLink? parseCallDeepLink(
  Uri uri, {
  Set<String> schemes = kCallDeepLinkSchemes,
  Set<String> hosts = kCallDeepLinkHosts,
}) {
  final scheme = uri.scheme.toLowerCase();
  final List<String> segments;

  if (schemes.contains(scheme)) {
    // chumbucket://call/abc  ->  host 'call', path ['abc']
    segments = [
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
    ].where((s) => s.isNotEmpty).toList(growable: false);
  } else if (scheme == 'https' || scheme == 'http') {
    if (!hosts.contains(uri.host.toLowerCase())) return null;
    segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  } else {
    return null;
  }

  if (segments.length < 2) return null;

  final kind = segments[0].toLowerCase();
  final raw = Uri.decodeComponent(segments[1]).trim();
  if (raw.isEmpty) return null;

  final sharedBy = _normalizeHandle(uri.queryParameters['ref']);

  switch (kind) {
    case 'c':
    case 'call':
      return CallLinkTarget(raw, sharedByHandle: sharedBy);
    case 'u':
    case 'user':
    case 'person':
      return PersonLinkTarget(
        _normalizeHandle(raw) ?? raw,
        sharedByHandle: sharedBy,
      );
    case 'm':
    case 'market':
      return MarketLinkTarget(raw, sharedByHandle: sharedBy);
    default:
      return null;
  }
}

String? _normalizeHandle(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// Why a link could not be opened. Each maps to a distinct on-screen state.
enum CallDeepLinkFailure {
  /// Not a link this app owns.
  notOurs,

  /// Parsed fine, but the target does not exist or is not visible to us.
  notFound,

  /// We could not reach anything to check.
  offline,

  /// Something else went wrong.
  failed,
}

/// The outcome of resolving a parsed link against the repository.
sealed class CallDeepLinkResolution {
  const CallDeepLinkResolution();
}

class ResolvedCallLink extends CallDeepLinkResolution {
  final CallDetail detail;
  final String? sharedByHandle;
  const ResolvedCallLink(this.detail, {this.sharedByHandle});
}

class ResolvedPersonLink extends CallDeepLinkResolution {
  final PersonDetail detail;
  final String? sharedByHandle;
  const ResolvedPersonLink(this.detail, {this.sharedByHandle});
}

class ResolvedMarketLink extends CallDeepLinkResolution {
  final MarketDetail detail;
  final String? sharedByHandle;
  const ResolvedMarketLink(this.detail, {this.sharedByHandle});
}

class UnresolvedLink extends CallDeepLinkResolution {
  final CallDeepLinkFailure reason;
  final String message;
  const UnresolvedLink(this.reason, this.message);
}

/// Turns a shared link into something the app can show.
///
/// Resolution never requires a signed-in user: a link opened by a signed-out
/// person still shows the call or the person, with the composer gated. That is
/// the entire point of a shareable receipt.
class CallDeepLinkResolver {
  final CallsRepository repository;

  const CallDeepLinkResolver(this.repository);

  Future<CallDeepLinkResolution> resolve(
    Uri uri, {
    String? viewerUserId,
  }) async {
    final link = parseCallDeepLink(uri);
    if (link == null) {
      return const UnresolvedLink(
        CallDeepLinkFailure.notOurs,
        'That link is not a Chumbucket call link.',
      );
    }
    return resolveTarget(link, viewerUserId: viewerUserId);
  }

  Future<CallDeepLinkResolution> resolveTarget(
    CallDeepLink link, {
    String? viewerUserId,
  }) async {
    try {
      switch (link) {
        case CallLinkTarget(:final callId):
          final detail = await repository.fetchCall(
            callId: callId,
            viewerUserId: viewerUserId,
          );
          return ResolvedCallLink(detail, sharedByHandle: link.sharedByHandle);
        case PersonLinkTarget(:final personRef):
          final detail = await repository.fetchPerson(
            personRef: personRef,
            viewerUserId: viewerUserId,
          );
          return ResolvedPersonLink(
            detail,
            sharedByHandle: link.sharedByHandle,
          );
        case MarketLinkTarget(:final marketId):
          final detail = await repository.fetchMarketDetail(
            marketId: marketId,
            viewerUserId: viewerUserId,
          );
          return ResolvedMarketLink(
            detail,
            sharedByHandle: link.sharedByHandle,
          );
      }
    } on CallsOfflineException catch (e) {
      return UnresolvedLink(CallDeepLinkFailure.offline, e.message);
    } on CallsRejectedException catch (e) {
      return UnresolvedLink(CallDeepLinkFailure.notFound, e.message);
    } on CallsException catch (e) {
      return UnresolvedLink(CallDeepLinkFailure.failed, e.message);
    }
  }
}
