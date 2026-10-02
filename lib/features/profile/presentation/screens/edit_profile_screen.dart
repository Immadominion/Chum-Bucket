import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/trust/data/content_policy.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';

/// Edit your own name and bio.
///
/// Reads and writes go through the BFF (`account.me`, `account.updateProfile`)
/// with the signed-in Supabase session, so this works for a wallet sign-in and
/// a Google/X sign-in alike, and can only ever change the caller's own
/// profile. With no Chumbucket account yet, it says so and offers sign-in
/// instead of failing on save.
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
  bool _needsSignIn = false;
  String? _profileLoadError;

  /// The account the loaded values belong to. A save is refused if the
  /// session has moved to another account since.
  String? _loadedFor;
  ChumbucketSession? _session;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    // Defer profile loading until after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session = context.read<ChumbucketSession?>();
      _session?.addListener(_onSessionChanged);
      _loadUserProfile();
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// The account this screen acts for: the session's canonical id. A tree
  /// with no session at all (a preview) acts for whatever API it was given.
  String? _currentAccount() {
    final session = context.read<ChumbucketSession?>();
    if (session == null) return accountApiOf(context) == null ? null : 'local';
    return session.isReady ? session.userId : null;
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final account = _currentAccount();
    if (_needsSignIn && account != null) {
      _loadUserProfile();
    } else if (_loadedFor != null && account != _loadedFor) {
      setState(() {});
    }
  }

  Future<void> _loadUserProfile() async {
    final request = ++_request;
    final api = accountApiOf(context);
    final account = _currentAccount();
    setState(() {
      _profileLoading = api != null && account != null;
      _profileLoadError = null;
      _needsSignIn = api == null || account == null;
      _loadedFor = null;
    });
    if (api == null || account == null) return;

    try {
      final profile = await api.me();
      if (!mounted || request != _request) return;
      if (_currentAccount() != account) {
        setState(
          () =>
              _profileLoadError =
                  'Your account changed. Retry to load the current profile.',
        );
        return;
      }
      setState(() {
        _loadedFor = account;
        _nameController.text = profile.displayName ?? '';
        _bioController.text = profile.bio ?? '';
      });
    } on CallsSignedOutException {
      if (mounted && request == _request) setState(() => _needsSignIn = true);
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () =>
              _profileLoadError =
                  'Your profile could not be loaded. Retry before making changes.',
        );
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _profileLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_isLoading ||
        _profileLoading ||
        _loadedFor == null ||
        _profileLoadError != null ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final account = _loadedFor!;
    final api = accountApiOf(context);
    if (api == null || _currentAccount() != account) {
      SnackBarUtils.showError(
        context,
        title: 'Account changed',
        subtitle: 'Reload your profile before saving changes.',
      );
      return;
    }
    // Names and bios are public: no links, slurs or strong profanity. This
    // is the app's copy of the server rule, for an instant answer; the BFF
    // (account.updateProfile) enforces the same policy and its refusal shows
    // below as the save error.
    final problem =
        contentPolicyProblem(_nameController.text, ContentField.name) ??
        contentPolicyProblem(_bioController.text, ContentField.bio);
    if (problem != null) {
      SnackBarUtils.showError(
        context,
        title: 'Can\'t save that',
        subtitle: problem,
      );
      return;
    }
    final calls = context.read<CallsProvider?>();
    final onboarding = context.read<OnboardingProvider?>();
    setState(() => _isLoading = true);

    try {
      final saved = await api.updateProfile(
        displayName: _nameController.text.trim(),
        bio: _bioController.text.trim(),
      );
      if (!mounted || _currentAccount() != account) return;
      // The feed and people pages show the new name without a restart.
      calls?.loadPerson(saved.userId, force: true);
      SnackBarUtils.showSuccess(
        context,
        title: 'Saved',
        subtitle: 'Your profile is updated.',
      );

      if (widget.isRequired) {
        await onboarding?.completeOnboarding();
        if (!mounted || _currentAccount() != account) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        // Return to the same Profile tab. Editing is not onboarding and
        // must not construct a second Home shell or change its selected tab.
        Navigator.of(context).pop(true);
      }
    } on CallsSignedOutException {
      if (mounted) setState(() => _needsSignIn = true);
    } on CallsException catch (e) {
      if (mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Unable to save',
          subtitle:
              e is CallsOfflineException
                  ? 'You\'re offline. Your changes are still here.'
                  : e.message,
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
                if (_needsSignIn) ...[
                  Text(
                    'Sign in to edit your profile. Your name, bio and picture '
                    'belong to your Chumbucket account, whether you use a '
                    'wallet, Google or X.',
                    style: TextStyle(
                      fontSize: 15.sp,
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => requestCallSignIn(context),
                    child: const Text('Sign in'),
                  ),
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
                      inputFormatters: [LengthLimitingTextInputFormatter(60)],
                      enabled:
                          !_profileLoading &&
                          !_needsSignIn &&
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
                      inputFormatters: [LengthLimitingTextInputFormatter(280)],
                      enabled:
                          !_profileLoading &&
                          !_needsSignIn &&
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
                      !_needsSignIn &&
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
