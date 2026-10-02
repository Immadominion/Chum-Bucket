/// "Your wallet": the on-phone wallet for people without a wallet app — make
/// one, see where it lives, fund it, back it up, take it elsewhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/mwa_connect_button.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../embedded_wallet_controller.dart';

/// Connects a wallet app to the signed-in account; true when one connected.
typedef ConnectWalletApp = Future<bool> Function(BuildContext context);

/// [connectWalletApp] defaults to [reconnectWalletApp]; tests pass their own.
Future<void> showEmbeddedWalletSheet(
  BuildContext context, {
  ConnectWalletApp? connectWalletApp,
}) {
  final controller = context.read<EmbeddedWalletController>();
  return showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => ChangeNotifierProvider<EmbeddedWalletController>.value(
          value: controller,
          child: EmbeddedWalletSheet(connectWalletApp: connectWalletApp),
        ),
  );
}

/// A shortened address for one-line places. The full one is shown in the sheet.
String shortWalletAddress(String address) =>
    address.length <= 12
        ? address
        : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

class EmbeddedWalletSheet extends StatelessWidget {
  const EmbeddedWalletSheet({super.key, this.connectWalletApp});

  /// Offered as the other way to trade: a wallet app over Mobile Wallet
  /// Adapter. Null uses [reconnectWalletApp]. Hidden without MWA in the tree.
  final ConnectWalletApp? connectWalletApp;

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<EmbeddedWalletController>();
    return ChumbucketWavySheet(
      title: 'Your wallet',
      subtitle: wallet.hasWallet ? 'Lives on this phone' : null,
      canDismiss: !wallet.isBusy,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child:
            wallet.hasWallet
                ? const _WalletDetails()
                : _NoWallet(
                  connectWalletApp: connectWalletApp ?? reconnectWalletApp,
                ),
      ),
    );
  }
}

TextStyle? _body(BuildContext context) => AppTextStyles.textTheme.bodyMedium
    ?.copyWith(color: AppColors.textPrimary, height: 1.45);

TextStyle? _meta(BuildContext context) => AppTextStyles.textTheme.bodySmall
    ?.copyWith(color: AppColors.textSecondary, fontSize: 13, height: 1.45);

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BasilIcon(icon, size: 20, color: AppColors.textPrimary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: _body(context))),
      ],
    ),
  );
}

class _NoWallet extends StatefulWidget {
  const _NoWallet({required this.connectWalletApp});
  final ConnectWalletApp connectWalletApp;
  @override
  State<_NoWallet> createState() => _NoWalletState();
}

class _NoWalletState extends State<_NoWallet> {
  bool _importing = false;
  bool _makeHereInstead = false;
  bool _connecting = false;
  final _phrase = TextEditingController();

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _connectApp() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final connected = await widget.connectWalletApp(context);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (connected) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<EmbeddedWalletController>();
    final busy = wallet.isBusy || _connecting;
    final walletApps = context.watch<MwaAuthProvider?>() != null;
    // A wallet account whose wallet app is not connected here (a reinstall
    // brings the session back, not the app's authorization): reconnecting
    // that wallet is the way to trade, not making a second one.
    final signedInWith = context.watch<ChumbucketSession?>()?.signInWallet;
    if (walletApps && signedInWith != null && !_makeHereInstead) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'You signed in with the wallet ${shortWalletAddress(signedInWith)}. '
            'Reconnect it to trade — every trade is approved in your wallet '
            'app.',
            key: const ValueKey('embedded-wallet-reconnect-copy'),
            style: _body(context),
          ),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Reconnect my wallet',
            busy: _connecting,
            busyLabel: 'Opening your wallet…',
            onPressed: busy ? null : _connectApp,
          ),
          ChumbucketTextAction(
            label: 'Make a wallet on this phone instead',
            color: AppColors.textSecondary,
            onPressed:
                busy ? null : () => setState(() => _makeHereInstead = true),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Trades on Panta are real USDC on Solana, so they need a wallet. '
          'Calls never do — they stay free.',
          style: _body(context),
        ),
        const SizedBox(height: 16),
        const _Point(
          'mobile-phone-outline',
          'Chumbucket can make a wallet that lives on this phone. Its key is '
              'made and kept here — Chumbucket’s servers never see it.',
        ),
        const _Point(
          'key-outline',
          'You get a 12-word recovery phrase. It opens the same wallet in '
              'Phantom or Solflare, so it is yours to take anywhere.',
        ),
        const _Point(
          'shield-outline',
          'Only you can move its money. Lose the phone and the phrase, and '
              'nobody — including us — can get it back.',
        ),
        if (wallet.error != null) ...[
          const SizedBox(height: 4),
          Text(
            wallet.error!,
            key: const ValueKey('embedded-wallet-error'),
            style: _body(context)?.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 16),
        if (_importing) ...[
          TextField(
            key: const ValueKey('embedded-wallet-phrase'),
            controller: _phrase,
            minLines: 3,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: const InputDecoration(
              labelText: '12-word recovery phrase',
              helperText: 'Words separated by spaces. Stays on this phone.',
            ),
          ),
          const SizedBox(height: 16),
          ChumbucketPrimaryButton(
            label: 'Use this wallet',
            busy: wallet.isBusy,
            busyLabel: 'Setting up…',
            onPressed:
                _connecting
                    ? null
                    : () => wallet.importRecoveryPhrase(_phrase.text),
          ),
          ChumbucketTextAction(
            label: 'Make a new wallet instead',
            color: AppColors.textSecondary,
            onPressed: busy ? null : () => setState(() => _importing = false),
          ),
        ] else ...[
          ChumbucketPrimaryButton(
            label: 'Create my wallet',
            busy: wallet.isBusy,
            busyLabel:
                wallet.phase == EmbeddedWalletPhase.loading
                    ? 'Checking this phone…'
                    : 'Creating…',
            onPressed:
                wallet.userId == null || _connecting ? null : wallet.create,
          ),
          ChumbucketTextAction(
            label: 'I have a recovery phrase',
            color: AppColors.textSecondary,
            onPressed: busy ? null : () => setState(() => _importing = true),
          ),
          if (walletApps)
            ChumbucketTextAction(
              label: 'Use a wallet app instead',
              color: AppColors.textSecondary,
              onPressed: busy ? null : _connectApp,
            ),
        ],
      ],
    );
  }
}

class _WalletDetails extends StatefulWidget {
  const _WalletDetails();
  @override
  State<_WalletDetails> createState() => _WalletDetailsState();
}

enum _Reveal { none, confirmPhrase, phrase, confirmKey, key }

class _WalletDetailsState extends State<_WalletDetails> {
  _Reveal _reveal = _Reveal.none;
  String? _privateKey;

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<EmbeddedWalletController>();
    final address = wallet.address!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Address', style: _meta(context)),
        const SizedBox(height: 6),
        SelectableText(
          address,
          key: const ValueKey('embedded-wallet-address'),
          style: _body(context)?.copyWith(fontWeight: FontWeight.w600),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: () => _copy(address, 'Address'),
            icon: const BasilIcon('copy-outline', size: 18),
            label: const Text('Copy address'),
          ),
        ),
        const SizedBox(height: 4),
        _StatusLine(wallet: wallet),
        const SizedBox(height: 16),
        const _Point(
          'mobile-phone-outline',
          'This wallet lives on this phone. Its key never leaves it, except '
              'in your own encrypted backup.',
        ),
        const _Point(
          'wallet-outline',
          'To trade, send USDC and a little SOL (for network fees) on Solana '
              'to the address above — from an exchange or another wallet.',
        ),
        _BackupLine(wallet: wallet),
        const SizedBox(height: 8),
        if (wallet.error != null) ...[
          Text(
            wallet.error!,
            key: const ValueKey('embedded-wallet-error'),
            style: _body(context)?.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: 8),
        ],
        if (!wallet.linked)
          ChumbucketPrimaryButton(
            label: 'Link to my account',
            busy: wallet.phase == EmbeddedWalletPhase.linking,
            busyLabel: 'Linking…',
            onPressed: wallet.link,
          ),
        const SizedBox(height: 8),
        ..._revealSection(context, wallet),
      ],
    );
  }

  List<Widget> _revealSection(
    BuildContext context,
    EmbeddedWalletController wallet,
  ) {
    switch (_reveal) {
      case _Reveal.none:
        return [
          ChumbucketTextAction(
            label: 'Show recovery phrase',
            onPressed: () => setState(() => _reveal = _Reveal.confirmPhrase),
          ),
          ChumbucketTextAction(
            label: 'Export private key',
            color: AppColors.textSecondary,
            onPressed: () => setState(() => _reveal = _Reveal.confirmKey),
          ),
        ];
      case _Reveal.confirmPhrase:
      case _Reveal.confirmKey:
        final phrase = _reveal == _Reveal.confirmPhrase;
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warningContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              phrase
                  ? 'Anyone with these 12 words can take everything in this '
                      'wallet. Write them down somewhere safe, offline. Never '
                      'type them into a website or share them — Chumbucket '
                      'will never ask.'
                  : 'Anyone with this key can take everything in this wallet. '
                      'Only paste it into a wallet app you trust (Phantom, '
                      'Solflare). Chumbucket will never ask for it.',
              style: _body(
                context,
              )?.copyWith(color: AppColors.onWarningContainer),
            ),
          ),
          const SizedBox(height: 12),
          ChumbucketPrimaryButton(
            label: phrase ? 'Show my 12 words' : 'Show my private key',
            onPressed: () async {
              if (phrase) {
                setState(() => _reveal = _Reveal.phrase);
                return;
              }
              final key = await wallet.exportPrivateKey();
              if (!mounted) return;
              setState(() {
                _privateKey = key;
                _reveal = _Reveal.key;
              });
            },
          ),
          ChumbucketTextAction(
            label: 'Cancel',
            color: AppColors.textSecondary,
            onPressed: () => setState(() => _reveal = _Reveal.none),
          ),
        ];
      case _Reveal.phrase:
        final words = (wallet.revealRecoveryPhrase() ?? '').split(' ');
        return [
          Text('Recovery phrase', style: _meta(context)),
          const SizedBox(height: 8),
          Wrap(
            key: const ValueKey('embedded-wallet-phrase-words'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${i + 1}. ${words[i]}', style: _body(context)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ChumbucketTextAction(
            label: 'Hide',
            onPressed: () => setState(() => _reveal = _Reveal.none),
          ),
        ];
      case _Reveal.key:
        final key = _privateKey ?? '';
        return [
          Text('Private key', style: _meta(context)),
          const SizedBox(height: 8),
          SelectableText(
            key,
            key: const ValueKey('embedded-wallet-private-key'),
            style: _body(context),
          ),
          const SizedBox(height: 8),
          ChumbucketTextAction(
            label: 'Copy private key',
            onPressed: () => _copy(key, 'Private key'),
          ),
          ChumbucketTextAction(
            label: 'Hide',
            color: AppColors.textSecondary,
            onPressed:
                () => setState(() {
                  _privateKey = null;
                  _reveal = _Reveal.none;
                }),
          ),
        ];
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.wallet});
  final EmbeddedWalletController wallet;

  @override
  Widget build(BuildContext context) {
    final linked = wallet.linked;
    return Row(
      children: [
        BasilIcon(
          linked ? 'check-outline' : 'clock-outline',
          size: 18,
          color: linked ? AppColors.success : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            wallet.phase == EmbeddedWalletPhase.linking
                ? 'Linking to your account…'
                : linked
                ? 'Linked to your Chumbucket account'
                : 'Not linked to your account yet',
            key: const ValueKey('embedded-wallet-status'),
            style: _meta(context),
          ),
        ),
      ],
    );
  }
}

class _BackupLine extends StatelessWidget {
  const _BackupLine({required this.wallet});
  final EmbeddedWalletController wallet;

  @override
  Widget build(BuildContext context) {
    final (icon, text, retry) = switch (wallet.backup) {
      WalletBackupOutcome.backedUp => (
        'cloud-check-outline',
        'Backed up to your Google account, end-to-end encrypted. Reinstalling '
            'the app brings it back.',
        false,
      ),
      WalletBackupOutcome.notEncrypted => (
        'cloud-off-outline',
        'Not backed up: this phone has no screen lock, so a backup could not '
            'be end-to-end encrypted. Add a screen lock, or write down your '
            'recovery phrase — until then it is the only backup.',
        true,
      ),
      WalletBackupOutcome.failed => (
        'cloud-off-outline',
        'The backup didn’t finish. Your recovery phrase is the only backup '
            'until it does.',
        true,
      ),
      WalletBackupOutcome.otherWalletBackedUp => (
        'cloud-off-outline',
        'Not backed up: this phone’s backup already holds a different wallet '
            'for your account, and it is never replaced. Write down this '
            'wallet’s recovery phrase — it is its only backup.',
        false,
      ),
      WalletBackupOutcome.unavailable || null => (
        'key-outline',
        'Your recovery phrase is your backup. Write it down — if this phone '
            'is lost or the app is deleted, it is how you get back in.',
        wallet.backup == null,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Point(icon, text),
        if (retry && wallet.backup != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: wallet.retryBackup,
              child: const Text('Try the backup again'),
            ),
          ),
      ],
    );
  }
}
