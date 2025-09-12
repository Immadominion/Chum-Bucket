import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;

  String _username = 'Username';
  String _bio = 'This is a short bio that describes the user.';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Start animation
    _fadeController.forward();

    // Load profile data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadProfileData();
    });
  }

  Future<void> _loadProfileData() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );

      if (authProvider.currentUser != null) {
        final profile = await profileProvider.getUserProfileFromLocal();

        if (mounted) {
          setState(() {
            _username = profile?['full_name'] ?? 'Username';
            _bio =
                profile?['bio'] ??
                'This is a short bio that describes the user.';
            // Profile image is now handled by ProfileHeader widget
          });
        }
      }

      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      walletProvider.refreshBalance();
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onEditProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const EditProfileScreen(showCancelIcon: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            SizedBox(height: 16.h),

                            // Top navigation bar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Settings button
                                IconButton(
                                  onPressed:
                                      () => showProfileSettingsSheet(context),
                                  icon: Icon(
                                    PhosphorIcons.gearSix(),
                                    size: 30.w,
                                    color: const Color(0xFFFF5A76),
                                  ),
                                ),

                                // Close button
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: PhosphorIcon(
                                    PhosphorIcons.xCircle(),
                                    size: 33.w,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),

                            // Profile Header
                            ProfileHeader(
                              username: _username,
                              bio: _bio,
                              onEditProfile: _onEditProfile,
                            ),

                            SizedBox(height: 20.h),

                            // Wallet Balance Card
                            ProfileWalletCard(),
                          ],
                        ),

                        Spacer(),

                        // Footer
                        Center(
                          child: Text.rich(
                            TextSpan(
                              text: 'Chum Bucket v0.0.1 • ',
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    height: 1.5,
                                    color: const Color(0xFFFF5A76),
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
