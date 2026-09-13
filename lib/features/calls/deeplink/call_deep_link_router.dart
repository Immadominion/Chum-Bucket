/// Navigator wiring for shared links.
///
/// The app has no router and no named routes (contract §2), so this pushes
/// `MaterialPageRoute`s onto whatever navigator it is given. All the decision
/// logic lives in `call_deep_link.dart`, which is pure Dart and unit-tested;
/// this file only turns a resolution into a push.
///
/// There is also no deep-link package in `pubspec.yaml` and adding one is not
/// Packet C's to do — see `docs/contracts/integration-requests/packet-c.md`.
/// [CallDeepLinkRouter.handle] is therefore a plain entry point that any future
/// listener (`app_links`, a platform channel, a paste-a-link field) can call
/// with a [Uri]. The slice works today without any of them.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/deeplink/call_deep_link.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';

class CallDeepLinkRouter {
  final CallsProvider provider;

  CallDeepLinkRouter(this.provider);

  CallDeepLinkResolver get _resolver =>
      CallDeepLinkResolver(provider.repository);

  /// Resolve [uri] and push the matching screen.
  ///
  /// Returns true when this router owned the link. False means "not ours" —
  /// the caller must pass it on to whatever else is listening (the Supabase
  /// OAuth callback, for one), and never swallow it.
  Future<bool> handle(Uri uri, NavigatorState navigator) async {
    if (parseCallDeepLink(uri) == null) return false;

    final resolution = await _resolver.resolve(
      uri,
      viewerUserId: provider.viewerUserId,
    );

    switch (resolution) {
      case ResolvedCallLink(:final detail, :final sharedByHandle):
        navigator.push(
          MaterialPageRoute<void>(
            builder:
                (_) => CallDetailScreen(
                  callId: detail.entry.call.id,
                  sharedByHandle: sharedByHandle,
                ),
          ),
        );
        return true;
      case ResolvedPersonLink(:final detail, :final sharedByHandle):
        navigator.push(
          MaterialPageRoute<void>(
            builder:
                (_) => CallPersonScreen(
                  personRef: detail.person.id,
                  sharedByHandle: sharedByHandle,
                ),
          ),
        );
        return true;
      case ResolvedMarketLink(:final detail):
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => MarketDetailScreen(marketId: detail.market.id),
          ),
        );
        return true;
      case UnresolvedLink(:final reason, :final message):
        if (reason == CallDeepLinkFailure.notOurs) return false;
        _showFailure(navigator, message);
        return true;
    }
  }

  void _showFailure(NavigatorState navigator, String message) {
    final context = navigator.context;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pure helper for callers that want to decide before navigating — e.g. an
  /// app-wide handler deciding whether a link belongs to auth or to calls.
  static bool owns(Uri uri) => parseCallDeepLink(uri) != null;

  /// The repository's own share links, so a "copy link" affordance and the
  /// parser can never drift apart.
  String linkForCall(String callId) => provider.shareLinkForCall(callId);

  String linkForPerson(String handleOrId) =>
      provider.shareLinkForPerson(handleOrId);
}

/// Round-trip guarantee: every link this app hands out must parse back to the
/// thing it points at. Asserted in `test/calls_deep_link_test.dart`.
CallDeepLink? parseSharedLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  return parseCallDeepLink(uri);
}

/// Convenience for `CallsRepository` implementations that want the same
/// parsing rules without going through the provider.
extension CallsRepositoryLinks on CallsRepository {
  CallDeepLink? parseOwnLink(String url) => parseSharedLink(url);
}
