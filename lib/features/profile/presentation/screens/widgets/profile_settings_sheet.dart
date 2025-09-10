import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_menu_item.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';

/// Settings modal sheet following the app's design conventions
class ProfileSettingsSheet extends StatelessWidget {
  const ProfileSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;
    final minHeight = 400.h;
    final preferredHeight = 500.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(43.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Header with gradient background and wave
              Container(
                height: 220.h.clamp(160.h, maxHeight * 0.35),
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(43.r),
                    topRight: Radius.circular(43.r),
                  ),
                ),
                child: Stack(
                  children: [
                    // Gradient header
                    Container(
                      width: double.infinity,
                      height: 220.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(43.r),
                          topRight: Radius.circular(43.r),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: 8.h),
                          // Drag handle
                          Container(
                            width: 43.w,
                            height: 3.2.h,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2.r),
                            ),
                          ),
                          SizedBox(height: 24.h),
                          // Settings title
                          Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // Main title
                          Text(
                            'Account & Support',
                            style: TextStyle(
                              fontSize: 24.sp,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // White wavy section
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipPath(
                        clipper: DetailedWaveClipper(),
                        child: Container(height: 130.h, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 130.h,
            bottom: 0,
            right: 0,
            left: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 0.h),
              child: Column(
                children: [
                  // Menu items
                  ProfileMenuItem(
                    icon: PhosphorIcons.star(),
                    title: 'Rate Chum Bucket',
                    subtitle: 'Share your experience',
                    iconColor: Colors.amber,
                    onTap: () {},
                  ),

                  ProfileMenuItem(
                    icon: PhosphorIcons.question(),
                    title: 'Talk To Support',
                    subtitle: 'Get help when you need it',
                    iconColor: Colors.blue,
                    onTap: () {},
                    iconSize: 30,
                  ),

                  ProfileMenuItem(
                    icon: PhosphorIcons.trash(),
                    title: 'Delete Your Account',
                    subtitle: 'Permanently remove your account',
                    isDanger: true,
                    onTap: () {},
                  ),

                  const Spacer(),

                  // Sign out button
                  ChallengeButton(
                    createNewChallenge: () async {
                      final authProvider = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      );
                      await authProvider.clearUserData();

                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      }
                    },
                    label: 'Sign Out',
                  ),

                  // SizedBox(height: 4.h),

                  // Cancel button
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 17.sp,
                        color: const Color(0xFFFF5A76),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Function to show the settings sheet with backdrop blur
Future<void> showProfileSettingsSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    elevation: 0,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
        child: const SafeArea(child: ProfileSettingsSheet()),
      );
    },
  );
}
