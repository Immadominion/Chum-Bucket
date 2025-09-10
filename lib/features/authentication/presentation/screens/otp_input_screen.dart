import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:flutter_otp_text_field/flutter_otp_text_field.dart';
import 'package:flutter/cupertino.dart';

class OtpInputScreen extends StatefulWidget {
  final String email;

  const OtpInputScreen({super.key, required this.email});

  @override
  State<OtpInputScreen> createState() => _OtpInputScreenState();
}

class _OtpInputScreenState extends State<OtpInputScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _errorText;
  String _enteredOtp = '';

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submitOtp() async {
    if (_enteredOtp.length != 6) {
      setState(() {
        _errorText = 'Please enter all 6 digits';
      });
      return;
    }

    setState(() {
      _errorText = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.verifyEmailCode(
      widget.email,
      _enteredOtp,
    );

    if (success && mounted) {
      // Save login state
      await authProvider.saveLoginState();

      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );
      final profile = await profileProvider.fetchUserProfile(
        authProvider.currentUser!.id,
      );

      if (profile != null) {
        // Save profile locally
        await profileProvider.saveUserProfileLocally(profile);
      }

      // Navigate after a short delay
      Future.delayed(const Duration(milliseconds: 1500), () async {
        if (mounted) {
          // Set onboarding as completed for users who login
          // This ensures users who have logged in won't see onboarding
          final onboardingProvider = Provider.of<OnboardingProvider>(
            context,
            listen: false,
          );
          await onboardingProvider.completeOnboarding();

          if (profile != null &&
              profile['full_name']?.toString().trim().isNotEmpty == true) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder:
                    (context) => const EditProfileScreen(showCancelIcon: false),
              ),
            );
          }
        }
      });
    } else if (mounted) {
      setState(() {
        _errorText = authProvider.errorMessage ?? 'Invalid verification code';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            CupertinoIcons.arrow_left,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24.w,
              right: 24.w,
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 20.h),
                  Text(
                    "Enter code",
                    style: TextStyle(
                      fontSize: 26.sp, // Reduced from 28.sp
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    "Enter the 6-digit code we sent you  (${widget.email})",
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16.sp, // Reduced from 18.sp
                      fontWeight: FontWeight.w700,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  SizedBox(height: 32.h), // Reduced from 40.h
                  OtpTextField(
                    numberOfFields: 6,
                    borderColor:
                        _errorText != null
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                    focusedBorderColor: Theme.of(context).colorScheme.primary,
                    cursorColor: Theme.of(context).colorScheme.primary,
                    showFieldAsBox: true,
                    fieldWidth: 40.w,
                    borderRadius: BorderRadius.circular(12.r),
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.05),
                    filled: true,
                    textStyle: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onCodeChanged: (code) {
                      if (_errorText != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          setState(() {
                            _errorText = null;
                          });
                        });
                      }
                    },
                    onSubmit: (String code) async {
                      _enteredOtp = code;
                      await Future.microtask(() => _submitOtp());
                    },
                  ),
                  SizedBox(height: 8.h),
                  if (_errorText != null)
                    Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: Text(
                        _errorText!,
                        style: TextStyle(color: Colors.red, fontSize: 14.sp),
                      ),
                    ),
                  SizedBox(height: 30.h),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) {
                      return GestureDetector(
                        onTap: authProvider.isLoading ? null : _submitOtp,
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                          child: Center(
                            child:
                                authProvider.isLoading
                                    ? SizedBox(
                                      height: 24.h,
                                      width: 24.h,
                                      child: CircularProgressIndicator(
                                        color: AppColors.buttonText,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                    : Text(
                                      "Continue",
                                      style: TextStyle(
                                        color: AppColors.buttonText,
                                        fontSize: 20.sp,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 20.h),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) {
                      return TextButton(
                        onPressed:
                            authProvider.isLoading
                                ? null
                                : () async {
                                  await authProvider.sendEmailCode(
                                    widget.email,
                                  );

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          authProvider.errorMessage != null
                                              ? authProvider.errorMessage!
                                              : 'New code sent to ${widget.email}',
                                        ),
                                        backgroundColor:
                                            authProvider.errorMessage != null
                                                ? Colors.red
                                                : null,
                                      ),
                                    );
                                  }
                                },
                        child: Text(
                          "Resend Code",
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16.sp,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 20.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
