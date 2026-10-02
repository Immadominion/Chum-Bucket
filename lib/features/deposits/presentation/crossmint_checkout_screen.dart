import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart'
    show CallJourneyButton, callJourneyBody, callJourneyHeading;
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../add_funds_controller.dart';
import '../data/deposits_models.dart';
import 'deposit_copy.dart';

/// Pushes Crossmint's checkout for the controller's order, full screen.
Future<void> pushCrossmintCheckout(
  BuildContext context,
  AddFundsController controller,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CrossmintCheckoutScreen(controller: controller),
  ),
);

/// Crossmint's embedded checkout in a WebView, set up the way Crossmint's
/// WebView guide asks (docs.crossmint.com/payments/embedded/guides/webview-integration):
///   - JavaScript and DOM storage on;
///   - a standard mobile browser user agent, or the checkout hides the
///     Apple Pay / Google Pay buttons;
///   - Android: the Payment Request API on (plus the PAY intent queries in
///     AndroidManifest.xml) so Google Pay can open;
///   - iOS: inline media, so identity checks can show the camera inline.
///
/// The page never tells the app anything: the order status shown along the
/// bottom comes from the BFF polling Crossmint with the server key. When the
/// order finishes, or needs a wallet signature, this screen closes itself and
/// the Add funds sheet takes over.
class CrossmintCheckoutScreen extends StatefulWidget {
  const CrossmintCheckoutScreen({super.key, required this.controller});
  final AddFundsController controller;

  @override
  State<CrossmintCheckoutScreen> createState() =>
      _CrossmintCheckoutScreenState();
}

class _CrossmintCheckoutScreenState extends State<CrossmintCheckoutScreen> {
  WebViewController? _web;
  int _progress = 0;
  bool _failed = false;
  bool _closing = false;

  /// Crossmint's full identity check asked for the camera, which this
  /// WebView never grants. The browser can; the banner offers it.
  bool _needsCamera = false;

  AddFundsController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onOrder);
    final uri = c.checkoutUri;
    if (uri != null && isCrossmintCheckoutUri(uri)) {
      _web = _buildWebView(uri);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onOrder);
    super.dispose();
  }

  void _onOrder() {
    if (!mounted) return;
    final stage = c.stage;
    if (!_closing &&
        (stage == AddFundsStage.delivered ||
            stage == AddFundsStage.failed ||
            stage == AddFundsStage.walletProof)) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  WebViewController _buildWebView(Uri uri) {
    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
            ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
            : const PlatformWebViewControllerCreationParams();
    final web = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: _onPermissionRequest,
    );
    unawaited(web.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(web.setBackgroundColor(Colors.white));
    unawaited(
      web.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted && _failed) setState(() => _failed = false);
          },
          onWebResourceError: (error) {
            if ((error.isForMainFrame ?? true) && mounted) {
              setState(() => _failed = true);
            }
          },
          onNavigationRequest:
              (request) => checkoutNavigationDecision(request.url),
        ),
      ),
    );
    unawaited(_configurePlatform(web).whenComplete(() => web.loadRequest(uri)));
    return web;
  }

  /// A web page never gets this phone's camera or microphone from here: the
  /// app holds no camera permission to pass on. Light KYC (up to US$1,000)
  /// needs no photos; the full check's ID photo and selfie continue in the
  /// browser, which asks for the camera itself.
  void _onPermissionRequest(WebViewPermissionRequest request) {
    unawaited(request.deny().catchError((Object _) {}));
    if (checkoutPermissionNeedsBrowser(request.types) &&
        mounted &&
        !_needsCamera) {
      setState(() => _needsCamera = true);
    }
  }

  Future<void> _configurePlatform(WebViewController web) async {
    try {
      final current = await web.getUserAgent();
      await web.setUserAgent(
        browserUserAgent(
          current,
          isIOS: defaultTargetPlatform == TargetPlatform.iOS,
        ),
      );
    } catch (_) {
      /* The default agent still loads the card form. */
    }
    final platform = web.platform;
    if (platform is AndroidWebViewController) {
      try {
        if (await platform.isWebViewFeatureSupported(
          WebViewFeatureType.paymentRequest,
        )) {
          await platform.setPaymentRequestEnabled(true);
        }
      } catch (_) {
        /* Older WebView: card entry still works; Google Pay won't show. */
      }
    }
  }

  Future<void> _openInBrowser() async {
    final uri = c.checkoutUri;
    if (uri == null || !isCrossmintCheckoutUri(uri)) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Couldn\'t open your browser.')),
      );
      return;
    }
    // The sheet keeps checking this same order while the browser is open.
    _closing = true;
    Navigator.of(context).pop();
  }

  Future<void> _back() async {
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back to Add funds',
            onPressed: () => Navigator.of(context).pop(),
            icon: const BasilIcon(
              'arrow-left-outline',
              color: AppColors.textPrimary,
            ),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Secure checkout', style: callJourneyHeading(context, 16)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BasilIcon(
                    'lock-solid',
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Payments by Crossmint · ${c.checkoutUri?.host ?? 'crossmint.com'}',
                      style: callJourneyBody(11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('checkout-open-browser'),
              onPressed: _openInBrowser,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(48, 48),
              ),
              child: const Text('Open in browser'),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child:
                _progress > 0 && _progress < 100 && !_failed
                    ? LinearProgressIndicator(
                      value: _progress / 100,
                      minHeight: 2,
                      color: AppColors.primary,
                      backgroundColor: Colors.transparent,
                    )
                    : const SizedBox(height: 2),
          ),
        ),
        body: Column(
          children: [
            if (_needsCamera && web != null && !_failed)
              _CameraBanner(onBrowser: _openInBrowser),
            Expanded(
              child:
                  web == null
                      ? _LoadProblem(
                        title: 'This checkout link isn\'t valid',
                        message: 'Go back and start the payment again.',
                        onRetry: null,
                        onBrowser: null,
                      )
                      : _failed
                      ? _LoadProblem(
                        title: 'The checkout didn\'t load',
                        message:
                            'Check your connection, or continue in your browser. You haven\'t been charged.',
                        onRetry: () {
                          setState(() => _failed = false);
                          unawaited(web.reload());
                        },
                        onBrowser: _openInBrowser,
                      )
                      : WebViewWidget(controller: web),
            ),
            _StatusStrip(controller: c),
          ],
        ),
      ),
    );
  }
}

/// Shown when the identity check wants a photo. Plain about why, one tap out.
class _CameraBanner extends StatelessWidget {
  const _CameraBanner({required this.onBrowser});
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    container: true,
    child: Container(
      key: const ValueKey('checkout-camera-banner'),
      width: double.infinity,
      color: AppColors.warningContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const BasilIcon(
            'camera-outline',
            size: 18,
            color: AppColors.onWarningContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This step needs your camera. Your browser can use it, and this '
              'payment carries on there.',
              style: callJourneyBody(
                12,
              ).copyWith(color: AppColors.onWarningContainer),
            ),
          ),
          TextButton(
            key: const ValueKey('checkout-camera-browser'),
            onPressed: onBrowser,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onWarningContainer,
              minimumSize: const Size(48, 44),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

/// Camera or microphone: only the browser can grant those.
bool checkoutPermissionNeedsBrowser(Set<WebViewPermissionResourceType> types) =>
    types.contains(WebViewPermissionResourceType.camera) ||
    types.contains(WebViewPermissionResourceType.microphone);

class _LoadProblem extends StatelessWidget {
  const _LoadProblem({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onBrowser,
  });
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onBrowser;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChumbucketStateArt.compact(ChumbucketStateArtwork.offline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: callJourneyHeading(context, 18),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: callJourneyBody()),
          const SizedBox(height: 20),
          if (onRetry != null)
            CallJourneyButton(
              label: 'Try again',
              primary: true,
              onPressed: onRetry,
            ),
          if (onBrowser != null) ...[
            const SizedBox(height: 10),
            CallJourneyButton(
              label: 'Open in browser',
              icon: 'globe-outline',
              onPressed: onBrowser,
            ),
          ],
        ],
      ),
    ),
  );
}

/// The order's live state, from the server — never from the page.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.controller});
  final AddFundsController controller;

  @override
  Widget build(BuildContext context) {
    final order = controller.order;
    if (order == null) return const SizedBox.shrink();
    final working =
        order.state == DepositOrderState.paymentProcessing ||
        order.state == DepositOrderState.delivering;
    final text = switch (order.state) {
      DepositOrderState.awaitingPayment =>
        'Pay above. This updates on its own.',
      DepositOrderState.paymentFailed =>
        'That payment didn\'t go through. Try again above.',
      _ => depositStateCopy(order).title,
    };
    final test = controller.status?.isTestMode ?? false;
    return Material(
      color: const Color(0xFFF6F7F9),
      child: SafeArea(
        top: false,
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (working)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    else
                      BasilIcon(
                        depositStateCopy(order).icon,
                        size: 16,
                        color: AppColors.textPrimary,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        key: const ValueKey('checkout-status'),
                        style: callJourneyBody(
                          13,
                        ).copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                if (test) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Test mode · card 4242 4242 4242 4242, any future date, any CVC',
                    style: callJourneyBody(11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Crossmint's guide says to keep in-WebView navigation unrestricted across
/// its payment and identity partners. Every web page may load; anything that
/// would leave the web (custom schemes, file:, javascript:) is refused.
NavigationDecision checkoutNavigationDecision(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return NavigationDecision.prevent;
  return switch (uri.scheme) {
    'https' || 'about' || 'data' || 'blob' => NavigationDecision.navigate,
    _ => NavigationDecision.prevent,
  };
}

const _androidBrowserAgent =
    'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Mobile Safari/537.36';
const _iosBrowserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

/// The WebView's own user agent, made to read as the platform's browser.
///
/// Android WebView marks itself with `; wv` and `Version/4.0`; WKWebView
/// omits `Version/…` and `Safari/…`. Crossmint hides Apple Pay and Google Pay
/// for agents it takes for an embedded view, so those markers go. The real
/// OS and engine versions are kept.
String browserUserAgent(String? webViewAgent, {required bool isIOS}) {
  final agent = webViewAgent?.trim();
  if (agent == null || agent.isEmpty || !agent.startsWith('Mozilla/5.0')) {
    return isIOS ? _iosBrowserAgent : _androidBrowserAgent;
  }
  if (isIOS) {
    if (agent.contains('Safari/')) return agent;
    final os = RegExp(r'OS (\d+)_(\d+)').firstMatch(agent);
    final version = os == null ? '17.0' : '${os.group(1)}.${os.group(2)}';
    final withVersion =
        agent.contains('Mobile/')
            ? agent.replaceFirst('Mobile/', 'Version/$version Mobile/')
            : '$agent Version/$version Mobile/15E148';
    return '$withVersion Safari/604.1';
  }
  return agent
      .replaceAll('; wv)', ')')
      .replaceAll(RegExp(r' Version/\d+(\.\d+)*'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}
