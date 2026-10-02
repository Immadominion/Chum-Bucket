/// The Terms of Use and Privacy Policy the sign-in consent line links to.
///
/// Same site and paths as fleet/trust's `LegalLinks` (`LEGAL_SITE_URL`,
/// default https://chumbucket.fun, `/terms` and `/privacy`), which publishes
/// those pages. Until they are live the links open the site's 404 — a release
/// blocker the owner clears by deploying them (onboarding spec §14 item 1).
/// Once fleet/trust is merged this file should defer to `LegalLinks`.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String _legalSite = String.fromEnvironment(
  'LEGAL_SITE_URL',
  defaultValue: 'https://chumbucket.fun',
);

abstract final class OnboardingLinks {
  static String get _base {
    var base = _legalSite.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  static Uri get terms => Uri.parse('$_base/terms');
  static Uri get privacy => Uri.parse('$_base/privacy');
}

typedef LinkOpener = Future<bool> Function(Uri uri);

Future<bool> _external(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens [uri] in the browser; if that fails, says where to go instead.
Future<bool> openOnboardingLink(
  BuildContext context,
  Uri uri, {
  LinkOpener? opener,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await (opener ?? _external)(uri);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'Couldn’t open the browser. Visit ${uri.host}${uri.path}',
        ),
      ),
    );
  }
  return opened;
}
