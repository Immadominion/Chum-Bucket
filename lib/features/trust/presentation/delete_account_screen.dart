/// Settings → Delete account.
///
/// Says plainly what goes and what stays, offers the export first, and asks
/// for DELETE typed out before anything happens. Works for any sign-in the
/// BFF can verify (wallet, Google, X): the server deletes the account behind
/// the session, so there is nothing to pick and nothing to get wrong.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:chumbucket/features/trust/presentation/data_export.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

const String kDeleteConfirmationWord = 'DELETE';

/// The BFF's exact refusal while the account's Chumbucket wallet still holds
/// money (`CASH_OUT_FIRST` in src/trust/TrustService.ts).
const kCashOutFirst = 'Cash out first';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, this.repository, this.onDeleted});

  /// Injected by tests; otherwise [TrustRepository.of].
  final TrustRepository? repository;

  /// What happens after deletion. Defaults to signing out of this device.
  final Future<void> Function(BuildContext context)? onDeleted;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _deleted = false;
  String? _error;

  late final TrustRepository _repository =
      widget.repository ?? TrustRepository.of(context);

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _confirmed => _confirm.text.trim() == kDeleteConfirmationWord;

  Future<void> _delete() async {
    if (!_confirmed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.deleteAccount();
      if (mounted) setState(() => _deleted = true);
    } on CallsSignedOutException {
      if (mounted) {
        setState(
          () =>
              _error =
                  'Your session has ended. Sign in again to delete your account.',
        );
      }
    } on CallsOfflineException {
      if (mounted) {
        setState(
          () =>
              // A timeout lands here too, and the server may have finished,
              // so don't claim nothing happened. A retry is always safe.
              _error =
                  'We couldn\'t reach Chumbucket, so we can\'t confirm your '
                  'account was deleted. Trying again when you\'re connected '
                  'is safe.',
        );
      }
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final done = widget.onDeleted ?? signOutOfChumbucket;
    await done(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession?>();
    final signedIn =
        widget.repository != null || session?.hasSupabaseSession == true;
    return PopScope(
      canPop: !_busy && !_deleted,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _deleted) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          automaticallyImplyLeading: !_deleted,
          title: const Text('Delete account'),
        ),
        body: SafeArea(
          child:
              _deleted
                  ? _DeletedView(onDone: _finish)
                  : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (!signedIn)
                        ..._signInFirst(context)
                      else
                        ..._form(context),
                    ],
                  ),
        ),
      ),
    );
  }

  List<Widget> _signInFirst(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return [
      Text('Sign in to continue', style: styles.titleLarge),
      const SizedBox(height: 8),
      Text(
        'We delete the account you\'re signed in to, so we need to know which '
        'one it is. Sign in with your wallet, Google or X, then come back here.',
        style: styles.bodyMedium?.copyWith(height: 1.5),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => requestCallSignIn(context),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.primary,
        ),
        child: const Text('Sign in'),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => openExternalLink(context, LegalLinks.deletion),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Can\'t sign in? Request deletion on the web'),
      ),
    ];
  }

  List<Widget> _form(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return [
      Text('This permanently deletes your account', style: styles.titleLarge),
      const SizedBox(height: 16),
      const _Consequence(
        icon: 'trash-outline',
        title: 'Removed',
        body:
            'Your name, @username, bio and picture, your sign-ins and linked '
            'wallets, Google or X links, who you follow and who follows you, '
            'blocks, mutes, push notifications and your inbox.',
      ),
      const _Consequence(
        icon: 'document-outline',
        title: 'Kept, without your name',
        body:
            'Your calls stay in the public record as "Deleted account". A call '
            'is a permanent, timestamped statement other people\'s records and '
            'receipts rely on. Records of funded trades are kept for legal '
            'reasons.',
      ),
      const _Consequence(
        icon: 'wallet-outline',
        title: 'Your money',
        body:
            'Funds in your wallet stay in your wallet. Open orders and '
            'positions on Panta are not affected; manage them on panta.market. '
            'On-chain transactions are public and can\'t be deleted by anyone.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed:
            _busy ? null : () => exportMyData(context, repository: _repository),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: const BasilIcon('download-outline', size: 20),
        label: const Text('Export my data first'),
      ),
      const SizedBox(height: 24),
      Text(
        'Type $kDeleteConfirmationWord to confirm',
        style: styles.titleSmall,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _confirm,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          hintText: kDeleteConfirmationWord,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _delete(),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          // The BFF's refusal while the Chumbucket wallet holds money: icon
          // first, three words.
          child:
              _error == kCashOutFirst
                  ? Row(
                    key: const ValueKey('delete-account-cash-out-first'),
                    children: [
                      const BasilIcon(
                        'wallet-outline',
                        size: 22,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _error!,
                        style: styles.bodyMedium?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  )
                  : Text(
                    _error!,
                    style: styles.bodyMedium?.copyWith(color: AppColors.error),
                  ),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _confirmed && !_busy ? _delete : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.error,
          foregroundColor: AppColors.onError,
        ),
        child: Text(_busy ? 'Deleting…' : 'Delete my account'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Keep my account'),
      ),
    ];
  }
}

class _Consequence extends StatelessWidget {
  const _Consequence({
    required this.icon,
    required this.title,
    required this.body,
  });
  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BasilIcon(icon, color: AppColors.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: styles.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: styles.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletedView extends StatelessWidget {
  const _DeletedView({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: BasilIcon(
              'check-outline',
              size: 48,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              'Your account has been deleted',
              textAlign: TextAlign.center,
              style: styles.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thanks for being part of Chumbucket. You\'ll be signed out of this '
            'device now.',
            textAlign: TextAlign.center,
            style: styles.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
