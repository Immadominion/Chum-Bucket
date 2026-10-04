/// "Your wallet", when it is the Chumbucket wallet: compact and icon-led.
/// Set up on first need (made and linked in one step, no phrase to write
/// down), then its address, its real mainnet balance and Add funds.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_widgets.dart'
    show DepositBalanceCard;
import 'package:chumbucket/features/deposits/presentation/mainnet_balance.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_prompt.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import '../chumbucket_wallet_controller.dart';

/// Opens the Chumbucket wallet. With [setUp] it is made and linked right
/// away (a trade needs it); true when it is ready and the person continued.
Future<bool> showChumbucketWalletSheet(
  BuildContext context, {
  bool setUp = false,
}) async {
  final wallet = context.read<ChumbucketWalletController>();
  final continued = await showChumbucketWavySheet<bool>(
    context: context,
    builder:
        (_) => ChangeNotifierProvider<ChumbucketWalletController>.value(
          value: wallet,
          child: ChumbucketWalletSheet(setUp: setUp),
        ),
  );
  return continued == true && wallet.signer != null;
}

String _short(String address) =>
    address.length <= 12
        ? address
        : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

class ChumbucketWalletSheet extends StatefulWidget {
  const ChumbucketWalletSheet({super.key, this.setUp = false});

  /// Opened by a trade: set the wallet up now and offer Continue.
  final bool setUp;

  @override
  State<ChumbucketWalletSheet> createState() => _ChumbucketWalletSheetState();
}

class _ChumbucketWalletSheetState extends State<ChumbucketWalletSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.setUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setUp());
    }
  }

  void _setUp() {
    if (!mounted) return;
    final wallet = context.read<ChumbucketWalletController>();
    if (wallet.signer != null || wallet.isBusy) return;
    // The outcome is the controller's phase and error, drawn below.
    unawaited(wallet.ensure().then((_) {}, onError: (_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<ChumbucketWalletController>();
    final address = wallet.address;
    return ChumbucketWavySheet(
      title: 'Your wallet',
      canDismiss: wallet.phase != ChumbucketWalletPhase.settingUp,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child:
            address == null
                ? _SetUp(wallet: wallet, onSetUp: _setUp)
                : _Ready(address: address, offerContinue: widget.setUp),
      ),
    );
  }
}

class _SetUp extends StatelessWidget {
  const _SetUp({required this.wallet, required this.onSetUp});
  final ChumbucketWalletController wallet;
  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    final busy = wallet.isBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Center(
          child: BasilIcon(
            'wallet-outline',
            size: 44,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'One wallet for your account, on every device.',
          textAlign: TextAlign.center,
          style: AppTextStyles.textTheme.bodyMedium?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        if (wallet.error != null) ...[
          const SizedBox(height: 12),
          Text(
            wallet.error!,
            key: const ValueKey('chumbucket-wallet-error'),
            textAlign: TextAlign.center,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ChumbucketPrimaryButton(
          key: const ValueKey('chumbucket-wallet-set-up'),
          label: 'Set up wallet',
          busy: busy,
          busyLabel: 'Setting up…',
          onPressed: busy || wallet.userId == null ? null : onSetUp,
        ),
      ],
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.address, required this.offerContinue});
  final String address;
  final bool offerContinue;

  @override
  Widget build(BuildContext context) => MainnetWalletBalance(
    wallet: address,
    builder:
        (context, view) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const BasilIcon(
                  'wallet-outline',
                  size: 20,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _short(address),
                    key: const ValueKey('chumbucket-wallet-address'),
                    style: AppTextStyles.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy address',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: address));
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Address copied')),
                    );
                  },
                  icon: const BasilIcon('copy-outline', size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DepositBalanceCard(
              address: null,
              balance: view.balance,
              loading: view.loading,
              error: view.error,
              available: view.available,
              onRefresh: view.refresh,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('chumbucket-add-funds'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
                textStyle: AppTextStyles.textTheme.titleMedium,
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                final added = await showAddFundsSheet(
                  context,
                  fundWallet: address,
                );
                if (added) await view.refresh();
              },
              icon: const BasilIcon(
                'add-outline',
                color: AppColors.textPrimary,
              ),
              label: const Text('Add funds'),
            ),
            SolTopUpPrompt(
              wallet: address,
              alwaysShow: true,
              onToppedUp: view.refresh,
            ),
            if (offerContinue) ...[
              const SizedBox(height: 12),
              ChumbucketPrimaryButton(
                key: const ValueKey('chumbucket-wallet-continue'),
                label: 'Continue',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ],
        ),
  );
}
