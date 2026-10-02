import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/presentation/embedded_wallet_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_sheet.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// A private entry row. Financial amounts stay inside the wallet sheet.
///
/// A connected wallet app (MWA) is shown as before. A Google or X account with
/// no wallet app gets the wallet that lives on this phone instead: none yet,
/// or its short address, and the sheet to make, fund, back up or export it.
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
          subtitle: Text(
            address == null
                ? signedInWith != null
                    ? '${shortWalletAddress(signedInWith)} · reconnect to trade'
                    : 'None yet · make one on this phone to trade'
                : onPhone.linked
                ? 'On this phone · ${shortWalletAddress(address)}'
                : 'On this phone · not linked yet',
            style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
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
        subtitle: Text(
          connected
              ? 'Connected · visible only to you'
              : 'Not connected · private',
          style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
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

class _PrivateWalletDetails extends StatelessWidget {
  const _PrivateWalletDetails();

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<MwaWalletProvider>();
    final styles = AppTextStyles.textTheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Private · only you can see this balance',
          style: styles.bodySmall,
        ),
        const SizedBox(height: 16),
        if (wallet.isLoading)
          const LinearProgressIndicator()
        else if (wallet.errorMessage != null)
          Text(
            'Balance unavailable. ${wallet.errorMessage}',
            style: styles.bodyMedium,
          )
        else if (wallet.isInitialized && wallet.walletAddress != null)
          Text(
            '${wallet.balance.toStringAsFixed(2)} SOL',
            style: styles.headlineMedium,
          )
        else
          Text('Balance unavailable', style: styles.bodyMedium),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: wallet.refreshWalletBalance,
            icon: const BasilIcon('refresh-outline'),
            label: const Text('Refresh balance'),
          ),
        ),
        if (wallet.walletAddress != null) ...[
          const Divider(),
          SelectableText(wallet.walletAddress!, style: styles.bodyMedium),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: wallet.walletAddress!),
              );
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
        const SizedBox(height: 16),
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
            final added = await showAddFundsSheet(context);
            if (added) await wallet.refreshWalletBalance();
          },
          icon: const BasilIcon('add-outline', color: AppColors.textPrimary),
          label: const Text('Add funds'),
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
