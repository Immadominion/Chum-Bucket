/// The step before a person's first funded trade: confirm 18+, eligibility
/// where they live, and Panta's terms. The confirmation is recorded on the
/// server (`trust.acceptFundedTrading`, session-keyed) and the server checks
/// it again on every trade prepare, so this sheet is the explanation, not the
/// enforcement.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

/// True when funded trading may proceed: the attestation was already on
/// record for the current terms, or the person just made it. False when they
/// backed out or it could not be checked (the server would refuse anyway).
Future<bool> ensureFundedTradingAttestation(
  BuildContext context, {
  TrustRepository? repository,
}) async {
  final repo = repository ?? TrustRepository.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  LegalStatus status;
  try {
    status = await repo.legalStatus();
  } on CallsException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  if (status.fundedTradingAccepted) return true;
  if (!context.mounted) return false;
  final accepted = await showChumbucketWavySheet<bool>(
    context: context,
    builder:
        (_) => FundedTradingAttestationSheet(status: status, repository: repo),
  );
  return accepted == true;
}

class FundedTradingAttestationSheet extends StatefulWidget {
  const FundedTradingAttestationSheet({
    super.key,
    required this.status,
    required this.repository,
    this.opener,
  });

  final LegalStatus status;
  final TrustRepository repository;
  final UrlOpener? opener;

  @override
  State<FundedTradingAttestationSheet> createState() =>
      _FundedTradingAttestationSheetState();
}

class _FundedTradingAttestationSheetState
    extends State<FundedTradingAttestationSheet> {
  bool _adult = false;
  bool _eligible = false;
  bool _venue = false;
  bool _busy = false;
  String? _error;

  bool get _all => _adult && _eligible && _venue;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.acceptFundedTrading(widget.status.termsVersion);
      if (mounted) Navigator.of(context).pop(true);
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Uri _uri(String fromServer, Uri fallback) =>
      Uri.tryParse(fromServer)?.hasScheme == true
          ? Uri.parse(fromServer)
          : fallback;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final s = widget.status;
    Widget link(String label, Uri uri) => TextButton(
      onPressed: () => openExternalLink(context, uri, opener: widget.opener),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label),
    );
    Widget check(bool value, ValueChanged<bool> onChanged, String text) =>
        CheckboxListTile(
          value: value,
          onChanged: _busy ? null : (v) => onChanged(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primary,
          title: Text(text, style: styles.bodyMedium?.copyWith(height: 1.4)),
        );

    return ChumbucketWavySheet(
      title: 'Before your first funded trade',
      subtitle: 'Real money, on Panta. Free calls stay free.',
      canDismiss: !_busy,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Funded positions are bought with USDC on Panta Market, on the '
              'Solana mainnet. You can lose everything you put in. Nothing here '
              'is financial advice.',
              style: styles.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            check(
              _adult,
              (v) => setState(() => _adult = v),
              'I am 18 or older.',
            ),
            check(
              _eligible,
              (v) => setState(() => _eligible = v),
              'Prediction markets are legal for me where I live, I am not in a '
              'place Panta restricts, and I am not on a sanctions list.',
            ),
            check(
              _venue,
              (v) => setState(() => _venue = v),
              'I accept Chumbucket\'s Terms and Panta\'s terms for funded trades.',
            ),
            Wrap(
              children: [
                link('Terms', _uri(s.termsUrl, LegalLinks.terms)),
                link('Privacy', _uri(s.privacyUrl, LegalLinks.privacy)),
                link(
                  'Panta',
                  _uri(s.venueTermsUrl, Uri.parse('https://panta.market')),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: styles.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ChumbucketPrimaryButton(
              label: 'Confirm and continue',
              busy: _busy,
              busyLabel: 'Saving…',
              onPressed: _all ? _accept : null,
            ),
            const SizedBox(height: 4),
            ChumbucketTextAction(
              label: 'Not now',
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
