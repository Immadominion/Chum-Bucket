import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
// MWA Auth Provider for wallet-based authentication
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';

class EditProfileScreen extends StatefulWidget {
  /// Whether to show the cancel/skip button
  /// Should be false for first-time users who MUST set up their profile
  final bool showCancelIcon;

  /// Whether this is mandatory profile setup (e.g., first login)
  /// When true, user cannot skip without entering a name
  final bool isRequired;

  const EditProfileScreen({
    super.key,
    this.showCancelIcon = true,
    this.isRequired = false,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isLoading = false;
  bool _profileLoading = true;
  String? _profileLoadError;
  String? _loadedWallet;

  @override
  void initState() {
    super.initState();
    // Defer profile loading until after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadUserProfile();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _profileLoading = true;
      _profileLoadError = null;
      _loadedWallet = null;
    });
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final profileProvider = Provider.of<ProfileProvider>(
      context,
      listen: false,
    );

    final wallet = authProvider.walletAddress;
    if (!authProvider.isAuthenticated || wallet == null) {
      setState(() {
        _profileLoading = false;
        _profileLoadError = 'Connect your wallet to load your profile.';
      });
      return;
    }

    try {
      final profile = await profileProvider.fetchUserProfile(wallet);
      if (!mounted) return;
      if (!authProvider.isAuthenticated ||
          authProvider.walletAddress != wallet) {
        setState(
          () =>
              _profileLoadError =
                  'Your account changed. Retry to load the current profile.',
        );
        return;
      }
      setState(() {
        if (profile == null) {
          _profileLoadError =
              'Your profile could not be loaded. Retry before making changes.';
          return;
        }
        _loadedWallet = wallet;
        _nameController.text = profile['full_name']?.toString() ?? '';
        _bioController.text = profile['bio']?.toString() ?? '';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _profileLoadError =
                  'Your profile could not be loaded. Retry before making changes.',
        );
      }
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_isLoading ||
        _profileLoading ||
        _loadedWallet == null ||
        _profileLoadError != null ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final authProvider = context.read<MwaAuthProvider>();
    final wallet = _loadedWallet!;
    if (!authProvider.isAuthenticated || authProvider.walletAddress != wallet) {
      SnackBarUtils.showError(
        context,
        title: 'Account changed',
        subtitle: 'Reload your profile before saving changes.',
      );
      return;
    }
    final profileProvider = context.read<ProfileProvider>();
    final updates = {
      'full_name': _nameController.text.trim(),
      'bio': _bioController.text.trim(),
    };
    setState(() => _isLoading = true);

    try {
      final success = await profileProvider.updateUserProfile(wallet, updates);
      if (!mounted) return;
      if (!authProvider.isAuthenticated ||
          authProvider.walletAddress != wallet) {
        return;
      }
      if (success) {
        SnackBarUtils.showSuccess(
          context,
          title: 'Success',
          subtitle: 'Profile updated successfully',
        );

        if (widget.isRequired) {
          await context.read<OnboardingProvider>().completeOnboarding();
          if (!mounted) return;
          if (!authProvider.isAuthenticated ||
              authProvider.walletAddress != wallet) {
            return;
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          // Return to the same Profile tab. Editing is not onboarding and
          // must not construct a second Home shell or change its selected tab.
          Navigator.of(context).pop(true);
        }
      } else {
        SnackBarUtils.showError(
          context,
          title: 'Error',
          subtitle: profileProvider.errorMessage ?? 'Failed to update profile',
        );
      }
    } catch (_) {
      if (mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Unable to save',
          subtitle: 'Your changes are still here. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading:
            widget.showCancelIcon
                ? IconButton(
                  tooltip: 'Cancel editing',
                  icon: BasilIcon(
                    'cancel-outline',
                    color: Theme.of(context).colorScheme.primary,
                    size: 33.w,
                  ),
                  onPressed:
                      _isLoading
                          ? null
                          : () {
                            // If profile is required, show a message
                            if (widget.isRequired) {
                              SnackBarUtils.showError(
                                context,
                                title: 'Name Required',
                                subtitle: 'Please enter your name to continue',
                              );
                              return;
                            }

                            Navigator.of(context).pop();
                          },
                )
                : null,
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24.w,
            right: 24.w,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24.h,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20.h),
                Text(
                  widget.isRequired ? 'Complete Your Profile' : 'Edit Profile',
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 40.h),
                if (_profileLoading) ...[
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading your profile',
                  ),
                  const SizedBox(height: 12),
                  const Text('Loading your profile…'),
                  const SizedBox(height: 20),
                ],
                if (_profileLoadError != null) ...[
                  Text(_profileLoadError!),
                  TextButton(
                    onPressed: _loadUserProfile,
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: 20),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Full Name",
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _nameController,
                      enabled:
                          !_profileLoading &&
                          _profileLoadError == null &&
                          !_isLoading,
                      decoration: InputDecoration(
                        hintText: "Enter your name",
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                        ),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                      ),
                      style: TextStyle(
                        fontSize: 20.sp,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your full name';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                SizedBox(height: 20.h),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Bio (Optional)",
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _bioController,
                      enabled:
                          !_profileLoading &&
                          _profileLoadError == null &&
                          !_isLoading,
                      decoration: InputDecoration(
                        hintText: "Tell us about yourself",
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                        ),
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                      ),
                      style: TextStyle(
                        fontSize: 20.sp,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
                SizedBox(height: 40.h),
                ChallengeButton(
                  enabled:
                      !_profileLoading &&
                      _profileLoadError == null &&
                      !_isLoading,
                  isLoading: _isLoading,
                  createNewChallenge: _saveProfile,
                  label: _isLoading ? 'Saving...' : 'Save Changes',
                ),
                SizedBox(height: 30.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
