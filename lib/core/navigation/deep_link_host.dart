import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/features/calls/deeplink/call_deep_link_router.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The only thing missing from the shared-link loop: something that hands a
/// live `Uri` to the router.
///
/// Parsing, resolution and routing already live in `lib/features/calls/deeplink/`
/// and are unit-tested without any package. This widget is the delivery edge —
/// it listens for the cold-start link and the warm-resume stream, and passes
/// each one to [CallDeepLinkRouter].
///
/// It deliberately does not own navigation policy. `handle` returns false for
/// any link the call slice does not own — `dev.cleva.chumbucket://login-callback`
/// among them — and a link this widget does not own is left alone so the
/// Supabase OAuth handler keeps receiving it exactly as before. Nothing is
/// swallowed.
/// Whether the app was cold-started by a link this app owns (a shared call,
/// person or market). The splash asks so it never puts Welcome in front of a
/// shared link (onboarding spec §3 row 1). Reported once, by [DeepLinkHost].
abstract final class ColdStartLink {
  static Completer<bool> _owned = Completer<bool>();

  /// Completes with true when the launch link is one the call slice opens.
  static Future<bool> get ownedLinkPending => _owned.future;

  static void report(bool owned) {
    if (!_owned.isCompleted) _owned.complete(owned);
  }

  @visibleForTesting
  static void reset() => _owned = Completer<bool>();
}

class DeepLinkHost extends StatefulWidget {
  const DeepLinkHost({
    super.key,
    required this.navigatorKey,
    required this.child,
    @visibleForTesting this.linkStream,
    @visibleForTesting this.initialLink,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Injectable so a test can drive delivery without the platform channel.
  final Stream<Uri>? linkStream;
  final Future<Uri?> Function()? initialLink;

  @override
  State<DeepLinkHost> createState() => _DeepLinkHostState();
}

class _DeepLinkHostState extends State<DeepLinkHost> {
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    // Deferred to the first frame: the router needs a mounted Navigator, and
    // on a cold start from a link there is none yet during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // A tapped call notification opens its call through the same router as a
    // shared link (chumbucket://call/<id>), so it lands on the same screen.
    FcmTokenService.onOpenCall =
        (callId) =>
            _handle(Uri(scheme: 'chumbucket', host: 'call', path: '/$callId'));

    final AppLinks? links =
        (widget.linkStream == null || widget.initialLink == null)
            ? AppLinks()
            : null;

    try {
      final initial =
          widget.initialLink != null
              ? await widget.initialLink!()
              : await links!.getInitialLink();
      ColdStartLink.report(
        initial != null && CallDeepLinkRouter.owns(initial),
      );
      if (initial != null) await _handle(initial);
    } catch (e) {
      ColdStartLink.report(false);
      // A missing platform channel (tests, desktop) must not take the app down.
      if (kDebugMode) debugPrint('DeepLinkHost: no initial link ($e)');
    }

    try {
      _subscription = (widget.linkStream ?? links!.uriLinkStream).listen(
        _handle,
        onError: (Object e) {
          if (kDebugMode) debugPrint('DeepLinkHost: link stream error ($e)');
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('DeepLinkHost: cannot listen for links ($e)');
    }
  }

  Future<void> _handle(Uri uri) async {
    // Cheap, side-effect-free rejection first, so a link we do not own never
    // touches the provider or the repository.
    if (!CallDeepLinkRouter.owns(uri)) return;

    final navigator = widget.navigatorKey.currentState;
    final navContext = widget.navigatorKey.currentContext;
    if (navigator == null || navContext == null) return;

    CallsProvider provider;
    try {
      provider = navContext.read<CallsProvider>();
    } catch (e) {
      // No CallsProvider in the tree (an early splash frame, say). Dropping the
      // link is correct here — it is better than pushing onto a half-built app.
      if (kDebugMode) debugPrint('DeepLinkHost: no CallsProvider yet ($e)');
      return;
    }

    try {
      await CallDeepLinkRouter(provider).handle(uri, navigator);
    } catch (e) {
      if (kDebugMode) debugPrint('DeepLinkHost: failed to open link ($e)');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    FcmTokenService.onOpenCall = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
