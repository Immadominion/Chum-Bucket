import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

class IdentityLinkSheet extends StatefulWidget {
  const IdentityLinkSheet({super.key});

  @override
  State<IdentityLinkSheet> createState() => _IdentityLinkSheetState();
}

class _IdentityLinkSheetState extends State<IdentityLinkSheet> {
  OAuthProvider _provider = OAuthProvider.google;

  Future<void> _linkIdentity() async {
    final label = _provider == OAuthProvider.google ? 'Google' : 'X';
    try {
      await context.read<ArenaProvider>().linkOAuthIdentity(
        authProvider: context.read<MwaAuthProvider>(),
        provider: _provider,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      SnackBarUtils.showSuccess(
        context,
        title: '$label linked',
        subtitle: 'Your Chumbucket identity is now connected to this wallet.',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not link $label',
        subtitle: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArenaProvider>(
      builder:
          (context, arena, _) => ChumbucketWavySheet(
            title: 'Link your identity',
            subtitle:
                'Use Google or X publicly. Your wallet still signs every call.',
            height: 500.h,
            headerTrailing: IconButton(
              tooltip: 'Close',
              onPressed:
                  arena.isLinkingIdentity
                      ? null
                      : () => Navigator.of(context).pop(),
              icon: const PhosphorIcon(
                PhosphorIconsRegular.xCircle,
                color: Colors.white,
              ),
            ),
            body: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 24.h),
              child: Column(
                children: [
                  _IdentityProviderOption(
                    label: 'Google',
                    detail: 'Use your Google profile name and image',
                    mark: 'G',
                    selected: _provider == OAuthProvider.google,
                    onTap:
                        arena.isLinkingIdentity
                            ? null
                            : () => setState(
                              () => _provider = OAuthProvider.google,
                            ),
                  ),
                  SizedBox(height: 10.h),
                  _IdentityProviderOption(
                    label: 'X',
                    detail: 'Use your X handle in the Calls feed',
                    mark: 'X',
                    selected: _provider == OAuthProvider.twitter,
                    onTap:
                        arena.isLinkingIdentity
                            ? null
                            : () => setState(
                              () => _provider = OAuthProvider.twitter,
                            ),
                  ),
                  SizedBox(height: 18.h),
                  ChallengeButton(
                    label:
                        'Continue with ${_provider == OAuthProvider.google ? 'Google' : 'X'}',
                    isLoading: arena.isLinkingIdentity,
                    createNewChallenge: _linkIdentity,
                  ),
                ],
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
              PhosphorIcon(
                selected
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsRegular.circle,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
