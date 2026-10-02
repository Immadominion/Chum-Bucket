/// Where Chumbucket's Terms, Privacy Policy and web deletion page live, and
/// how the app opens them (and the store listing for "Rate Chumbucket").
///
/// The site is configurable per build with `--dart-define=LEGAL_SITE_URL=…`
/// and defaults to the public website. The BFF reports the same URLs in
/// `trust.legalStatus`; these are the ones the app can open before sign-in.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String kLegalSiteUrl = String.fromEnvironment(
  'LEGAL_SITE_URL',
  defaultValue: 'https://chumbucket.fun',
);

/// Android application id (android/app/build.gradle.kts).
const String kAndroidPackageId = 'dev.cleva.chumbucket';

/// Overrides the store listing, e.g. a Google Play or App Store URL once the
/// app is published there.
const String kStoreListingUrl = String.fromEnvironment('STORE_LISTING_URL');

class LegalLinks {
  LegalLinks._();

  static String get _base {
    var base = kLegalSiteUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  static Uri get terms => Uri.parse('$_base/terms');
  static Uri get privacy => Uri.parse('$_base/privacy');
  static Uri get deletion => Uri.parse('$_base/delete-account');
}

/// Signature of `url_launcher`'s launch, injectable for tests.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens [uri] in the browser. If that fails, says so with the address, so
/// the person can still get there.
Future<bool> openExternalLink(
  BuildContext context,
  Uri uri, {
  UrlOpener? opener,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await (opener ?? _launchExternal)(uri);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't open the browser. Visit ${uri.host}${uri.path}",
        ),
      ),
    );
  }
  return opened;
}

/// The store pages to try, in order, for "Rate Chumbucket".
@visibleForTesting
List<Uri> storeListingCandidates({
  String override = kStoreListingUrl,
  bool? isAndroid,
}) {
  if (override.trim().isNotEmpty) return [Uri.parse(override.trim())];
  final android = isAndroid ?? (!kIsWeb && Platform.isAndroid);
  if (!android) return const [];
  // Chumbucket is published on the Solana dApp Store (publishing/config.yaml),
  // not Google Play: the Play listing for this id does not exist (404), so it
  // is not offered. This is the dApp Store's documented listing deep link
  // (docs.solanamobile.com/dapp-store/link-to-dapp-listing-page). Where the
  // dApp Store is not installed, the person is told the store can't open.
  return [Uri.parse('solanadappstore://details?id=$kAndroidPackageId')];
}

/// Opens Chumbucket's store listing so the person can rate it.
Future<void> openStoreListing(BuildContext context, {UrlOpener? opener}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  for (final uri in storeListingCandidates()) {
    try {
      if (await (opener ?? _launchExternal)(uri)) return;
    } catch (_) {
      // try the next one
    }
  }
  messenger?.showSnackBar(
    const SnackBar(content: Text("Couldn't open the store on this device.")),
  );
}
