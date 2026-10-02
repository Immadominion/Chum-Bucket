/// Panta's own public page for a market — the place a person can check the
/// result, claim, or sell. The authenticated API URL is never shown: it
/// answers 401 to anyone without the server key.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../data/panta_lifecycle_models.dart';

/// Opens a URL outside the app. Replaceable in tests.
typedef PantaUrlOpener = Future<bool> Function(Uri uri);

Future<bool> defaultPantaUrlOpener(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens Panta's page for [venueMarketId]; tells the person if it could not.
Future<void> openPantaMarket(
  BuildContext context,
  String venueMarketId, {
  PantaUrlOpener opener = defaultPantaUrlOpener,
}) async {
  final uri = pantaMarketUri(venueMarketId);
  final opened = await opener(uri);
  if (!opened && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Could not open ${uri.host}${uri.path}.')),
    );
  }
}

/// "Resolved by Panta" with a tappable `panta.market/market/…` link.
class PantaMarketLink extends StatelessWidget {
  const PantaMarketLink({
    super.key,
    required this.venueMarketId,
    this.label = 'Panta',
    this.opener = defaultPantaUrlOpener,
    this.style,
  });

  final String venueMarketId;
  final String label;
  final PantaUrlOpener opener;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final uri = pantaMarketUri(venueMarketId);
    final base =
        style ??
        Theme.of(context).textTheme.bodySmall ??
        const TextStyle(fontSize: 12);
    return Semantics(
      link: true,
      label: '$label, open ${uri.host}${uri.path}',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => openPantaMarket(context, venueMarketId, opener: opener),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: base.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const BasilIcon(
                'share-box-outline',
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
