import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/presentation/embedded_wallet_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_widgets.dart'
    show DepositBalanceCard;
import 'package:chumbucket/features/deposits/presentation/mainnet_balance.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_prompt.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// "My wallet" on your own Profile: the trading wallet's real **mainnet** USDC
/// and SOL, read by the server (`deposits.balance`, genesis-pinned), for a
/// wallet app and for the wallet on this phone alike. Never the legacy devnet
/// RPC balance.
///
/// A connected wallet app (MWA) opens its private sheet. A Google or X account
/// with no wallet app gets the wallet that lives on this phone instead: none
/// yet, or its short address, and the sheet to make, fund, back up or export
/// it.
class ProfileWalletCard extends StatelessWidget {
  const ProfileWalletCard({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<MwaWalletProvider?>();
    final connected = wallet?.walletAddress != null;
    final styles = AppTextStyles.textTheme;
    final onPhone = context.watch<EmbeddedWalletController?>();
    final account = context.watch<ChumbucketSession?>();
    if (!connected && onPhone != null && account?.isReady == true) {
      final address = onPhone.address;
      // A wallet account back after a reinstall: its wallet app is the one to
      // reconnect, not a reason to make a second wallet.
      final signedInWith = account!.signInWallet;
      return Material(
        color: AppColors.surface,
        child: ListTile(
          key: const ValueKey('profile-embedded-wallet'),
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 12,
          leading: const BasilIcon(
            'wallet-outline',
            color: AppColors.textPrimary,
          ),
          title: Text('My wallet', style: styles.titleSmall),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                address == null
                    ? signedInWith != null
                        ? '${shortWalletAddress(signedInWith)} · reconnect to trade'
                        : 'None yet · make one on this phone to trade'
                    : onPhone.linked
                    ? 'On this phone · ${shortWalletAddress(address)}'
                    : 'On this phone · not linked yet',
                style: styles.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (address != null && onPhone.linked)
                _BalanceLine(wallet: address),
            ],
          ),
          trailing: const BasilIcon(
            'arrow-right-outline',
            color: AppColors.textPrimary,
          ),
          onTap: () => showEmbeddedWalletSheet(context),
        ),
      );
    }
    return Material(
      color: AppColors.surface,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 12,
        leading: const BasilIcon(
          'wallet-outline',
          color: AppColors.textPrimary,
        ),
        title: Text('My wallet', style: styles.titleSmall),
        subtitle:
            connected
                ? _BalanceLine(
                  wallet: wallet!.walletAddress!,
                  lead: 'Connected · only you see this',
                )
                : Text(
                  'Not connected · private',
                  style: styles.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
        trailing: const BasilIcon(
          'arrow-right-outline',
          color: AppColors.textPrimary,
        ),
        onTap: () {
          if (!connected) {
            showProfileSettingsSheet(context);
            return;
          }
          showChumbucketWavySheet<void>(
            context: context,
            builder:
                (_) => ChangeNotifierProvider<MwaWalletProvider>.value(
                  value: wallet!,
                  child: const ChumbucketWavySheet(
                    title: 'My wallet',
                    body: _PrivateWalletDetails(),
                  ),
                ),
          );
        },
      ),
    );
  }
}

/// "12.40 USDC · 0.0085 SOL" on mainnet, as the server read it.
class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.wallet, this.lead});
  final String wallet;
  final String? lead;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    return MainnetWalletBalance(
      wallet: wallet,
      builder: (context, view) {
        final figures =
            view.summary ??
            (view.loading
                ? 'Reading balance…'
                : view.available
                ? 'Balance unavailable'
                : null);
        final text = [
          if (lead != null) lead!,
          if (figures != null) figures,
        ].join('\n');
        return Text(
          text,
          key: const ValueKey('profile-wallet-balance'),
          style: style,
        );
      },
    );
  }
}

class _PrivateWalletDetails extends StatelessWidget {
  const _PrivateWalletDetails();

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<MwaWalletProvider>();
    final address = wallet.walletAddress;
    return MainnetWalletBalance(
      wallet: address,
      builder: (context, view) => _details(context, address, view),
    );
  }

  Widget _details(
    BuildContext context,
    String? address,
    MainnetBalanceView view,
  ) {
    final styles = AppTextStyles.textTheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Private · only you can see this balance',
          style: styles.bodySmall,
        ),
        const SizedBox(height: 12),
        // Solana mainnet, where Panta trades settle — read by the server.
        DepositBalanceCard(
          address: null,
          balance: view.balance,
          loading: view.loading,
          error: view.error,
          available: view.available,
          onRefresh: view.refresh,
        ),
        if (address != null) ...[
          const SizedBox(height: 8),
          SelectableText(address, style: styles.bodyMedium),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: address));
              if (context.mounted) {
                SnackBarUtils.showInfo(
                  context,
                  title: 'Wallet address copied',
                  subtitle: 'The address is on your clipboard.',
                );
              }
            },
            icon: const BasilIcon('copy-outline'),
            label: const Text('Copy address'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('profile-add-funds'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
            textStyle: styles.titleMedium,
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          // Card, Apple Pay or Google Pay → USDC in this account's wallet,
          // with the wallet's real USDC and SOL shown before paying.
          onPressed: () async {
            final added = await showAddFundsSheet(context, fundWallet: address);
            if (added) await view.refresh();
          },
          icon: const BasilIcon('add-outline', color: AppColors.textPrimary),
          label: const Text('Add funds'),
        ),
        if (address != null)
          SolTopUpPrompt(
            wallet: address,
            alwaysShow: true,
            onToppedUp: view.refresh,
          ),
        TextButton.icon(
          key: const ValueKey('profile-receive'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: AppColors.textPrimary,
          ),
          onPressed: () => showWalletModal(context),
          icon: const BasilIcon('arrow-down-outline'),
          label: const Text('Receive from another wallet'),
        ),
        const SizedBox(height: 4),
        Text(
          'Managed by your external wallet app. Free calls do not use this balance.',
          style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
