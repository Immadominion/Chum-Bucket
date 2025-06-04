import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:chumbucket/screens/home/home.dart';
import 'package:chumbucket/screens/onboarding/onboarding_screen.dart';
import 'package:chumbucket/providers/onboarding_provider.dart';
import 'package:chumbucket/providers/profile_provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Defer profile loading until after the build phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final profileProvider = Provider.of<ProfileProvider>(
      context,
      listen: false,
    );

    final profile = await profileProvider.fetchUserProfile(
      authProvider.currentUser!.id,
    );

    log('Fetched profile: $profile');

    if (mounted) {
      setState(() {
        if (profile != null) {
          _nameController.text = profile['full_name']?.toString() ?? '';
          _bioController.text = profile['bio']?.toString() ?? '';
        } else {
          _nameController.text = '';
          _bioController.text = '';
        }
      });

      // Show error only if there's an actual issue
      if (profile == null && profileProvider.errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(profileProvider.errorMessage!)));
      }
    }
  }

  void _saveProfile() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );

      final updates = {
        'full_name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
      };

      final success = await profileProvider.updateUserProfile(
        authProvider.currentUser!.id,
        updates,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );

        final onboardingProvider = OnboardingProvider();
        bool hasViewedOnboarding =
            await onboardingProvider.isOnboardingCompleted();

        if (hasViewedOnboarding) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              profileProvider.errorMessage ?? 'Failed to update profile',
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            CupertinoIcons.clear,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () {
            // Allow skipping profile setup, but navigate based on onboarding status
            final onboardingProvider = OnboardingProvider();
            onboardingProvider.isOnboardingCompleted().then((
              hasViewedOnboarding,
            ) {
              if (hasViewedOnboarding) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              } else {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              }
            });
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20.h),
                Text(
                  "Complete Your Profile",
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 40.h),
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
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: "Enter your full name",
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                        ),
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.05),
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
                        if (value == null || value.isEmpty) {
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
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _bioController,
                      decoration: InputDecoration(
                        hintText: "Tell us about yourself",
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                        ),
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.05),
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
                const Spacer(),
                GestureDetector(
                  onTap: _isLoading ? null : _saveProfile,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(18.r),
                    ),
                    child: Center(
                      child:
                          _isLoading
                              ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.buttonText,
                                ),
                              )
                              : Text(
                                "Save",
                                style: TextStyle(
                                  color: AppColors.buttonText,
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                    ),
                  ),
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
