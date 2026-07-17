import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// MWA (Mobile Wallet Adapter) connect button for Solana wallet authentication
/// Replaces email-based Privy authentication with native wallet connection
class MwaConnectButton extends StatefulWidget {
  const MwaConnectButton({super.key});

  @override
  State<MwaConnectButton> createState() => _MwaConnectButtonState();
}

class _MwaConnectButtonState extends State<MwaConnectButton> {
  bool _isConnecting = false;

  Future<void> _handleWalletConnect(BuildContext context) async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);

    try {
      final authProvider = context.read<MwaAuthProvider>();

      debugPrint('🔌 CONNECT: Starting wallet connection');
      debugPrint(
        '🔌 CONNECT: Current authProvider.walletAddress = ${authProvider.walletAddress}',
      );
      debugPrint(
        '🔌 CONNECT: Current authProvider.state = ${authProvider.state}',
      );

      // Check if wallet app is available
      final walletAvailable = await authProvider.isWalletAvailable();
      if (!walletAvailable) {
        if (context.mounted) {
          SnackBarUtils.showError(
            context,
            title: 'Wallet Not Found',
            subtitle:
                'Please install a Solana wallet app like Phantom, Solflare, or Seeker',
          );
        }
        return;
      }

      // Attempt to connect wallet via MWA
      debugPrint('🔌 CONNECT: Calling authProvider.authorize()');
      final success = await authProvider.authorize();
      debugPrint('🔌 CONNECT: authorize() returned: $success');
      debugPrint(
        '🔌 CONNECT: After authorize - walletAddress = ${authProvider.walletAddress}',
      );

      if (!context.mounted) return;

      if (success) {
        final walletAddress = authProvider.walletAddress;
        debugPrint('🔌 CONNECT: SUCCESS - walletAddress = $walletAddress');

        // Try to resolve any SNS domain (.sol, .skr, etc.) for this wallet
        String? domainName;
        if (walletAddress != null) {
          domainName = await AddressNameResolver.resolveDisplayName(
            walletAddress,
          );
          // If it's just a shortened address, it means no domain was found
          if (domainName.contains('...')) {
            domainName = null;
          }
        }

        // Show welcome message with domain if available
        final welcomeMessage =
            domainName != null
                ? 'Welcome, $domainName!'
                : 'Welcome to Chumbucket!';

        SnackBarUtils.showSuccess(
          context,
          title: 'Wallet Connected',
          subtitle: welcomeMessage,
        );

        // Initialize wallet provider with auth provider
        if (context.mounted) {
          final walletProvider = context.read<MwaWalletProvider>();
          debugPrint(
            '🔌 CONNECT: walletProvider.isInitialized = ${walletProvider.isInitialized}',
          );
          debugPrint(
            '🔌 CONNECT: walletProvider.walletAddress = ${walletProvider.walletAddress}',
          );
          debugPrint('🔌 CONNECT: Calling walletProvider.initializeFromAuth()');
          await walletProvider.initializeFromAuth(authProvider);
          debugPrint(
            '🔌 CONNECT: After initializeFromAuth - walletAddress = ${walletProvider.walletAddress}',
          );
        }

        // Navigate to HomeScreen after successful connection
        if (context.mounted) {
          debugPrint('🔌 CONNECT: Navigating to HomeScreen');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false, // Remove all previous routes
          );
        }
      } else {
        final errorMsg =
            authProvider.errorMessage ?? 'Failed to connect wallet';
        SnackBarUtils.showError(
          context,
          title: 'Connection Failed',
          subtitle: errorMsg,
        );
      }
    } catch (error) {
      debugPrint('🔌 CONNECT: ERROR - $error');
      if (context.mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Connection Error',
          subtitle: error.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MwaAuthProvider>(
      builder: (context, authProvider, _) {
        final isLoading =
            _isConnecting || authProvider.state == MwaAuthState.loading;

        return Column(
          children: [
            // Main connect button
            ChallengeButton(
              createNewChallenge:
                  () => isLoading ? null : _handleWalletConnect(context),
              label: isLoading ? 'Connecting...' : 'Connect Wallet',
              blurRadius: false,
              enabled: !isLoading,
              isLoading: isLoading,
            ),
          ],
        );
      },
    );
  }
}

/// A compact version for use in app bars or smaller spaces
class MwaConnectButtonCompact extends StatelessWidget {
  final VoidCallback? onPressed;

  const MwaConnectButtonCompact({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Consumer<MwaAuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.isAuthenticated) {
          // Show truncated wallet address when connected
          final address = authProvider.walletAddress ?? '';
          final shortAddress =
              address.length > 8
                  ? '${address.substring(0, 4)}...${address.substring(address.length - 4)}'
                  : address;

          return Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: AppColors.solanaGreen.withAlpha(30),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: AppColors.solanaGreen.withAlpha(100)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: AppColors.solanaGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8.w),
                Text(
                  shortAddress,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        }

        // Show connect button when not connected
        return TextButton.icon(
          onPressed: onPressed,
          icon: BasilIcon('wallet-outline', size: 18.sp),
          label: Text('Connect', style: TextStyle(fontSize: 13.sp)),
          style: TextButton.styleFrom(foregroundColor: AppColors.solanaGreen),
        );
      },
    );
  }
}
