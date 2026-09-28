import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/existing_account_proof.dart';
import 'package:chumbucket/features/authentication/session/mwa_existing_account_wallet.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class IdentityLinkSheet extends StatefulWidget {
  const IdentityLinkSheet({super.key, this.wallet});

  /// Test seam; production captures the currently connected MWA account.
  final ExistingAccountWallet? wallet;

  @override
  State<IdentityLinkSheet> createState() => _IdentityLinkSheetState();
}

class _IdentityLinkSheetState extends State<IdentityLinkSheet> {
  ChumbucketSession? _attemptSession;

  @override
  void dispose() {
    _attemptSession?.cancelExistingAccountLink();
    super.dispose();
  }

  Future<void> _linkIdentity() async {
    final session = context.read<ChumbucketSession>();
    if (session.isLinkingExistingAccount) return;
    _attemptSession = session;
    final wallet =
        widget.wallet ??
        MwaExistingAccountWallet(context.read<MwaAuthProvider>());
    final linked = await session.linkExistingAccount(wallet);
    if (!mounted) return;
    _attemptSession = null;
    if (linked) {
      SnackBarUtils.showSuccess(
        context,
        title: 'Google linked',
        subtitle: 'Same Chumbucket profile, calls and history.',
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChumbucketSession>(
      builder:
          (context, session, _) => PopScope(
            canPop: !session.isLinkingExistingAccount,
            child: ChumbucketWavySheet(
              title: 'Link Google',
              subtitle: 'Keep your Chumbucket profile, calls and history.',
              height: 500.h,
              headerTrailing: IconButton(
                tooltip: 'Close',
                onPressed:
                    session.isLinkingExistingAccount
                        ? null
                        : () => Navigator.of(context).pop(),
                icon: const BasilIcon('cancel-outline', color: Colors.white),
              ),
              body: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
                child: Column(
                  children: [
                    _IdentityProviderOption(
                      label: 'Google',
                      detail: 'Add Google sign-in to this existing account',
                      mark: 'G',
                      selected: true,
                      onTap: null,
                    ),
                    SizedBox(height: 16.h),
                    const Text(
                      'After Google, your connected wallet will confirm ownership with a message. '
                      'No transaction, payment or new profile.',
                    ),
                    if (session.existingLinkError case final error?) ...[
                      SizedBox(height: 12.h),
                      Text(
                        error.message,
                        key: const ValueKey('account-link-error'),
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                    SizedBox(height: 18.h),
                    ChallengeButton(
                      label: 'Continue with Google',
                      isLoading: session.isLinkingExistingAccount,
                      createNewChallenge: _linkIdentity,
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

class _IdentityProviderOption extends StatelessWidget {
  final String label;
  final String detail;
  final String mark;
  final bool selected;
  final VoidCallback? onTap;

  const _IdentityProviderOption({
    required this.label,
    required this.detail,
    required this.mark,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Center(
                  child: Text(
                    mark,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              selected
                  ? BasilIcon('check-solid', color: AppColors.primary)
                  : Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.textTertiary,
                        width: 1.5,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
