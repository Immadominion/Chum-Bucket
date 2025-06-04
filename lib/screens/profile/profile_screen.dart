import 'package:chumbucket/screens/login/login_screen.dart';
import 'package:chumbucket/screens/profile/edit_profile_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/profile_provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/wallet_provider.dart';
import 'package:chumbucket/screens/profile/widgets/wallet_balance_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String _username = 'Username';
  String _bio = 'This is a short bio that describes the user.';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Load user profile
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );
      final profile = await profileProvider.getUserProfileFromLocal();

      if (profile != null) {
        setState(() {
          _username = profile['full_name'] ?? 'Username';
          _bio =
              profile['bio'] ?? 'This is a short bio that describes the user.';
        });
      }

      // Ensure wallet provider is initialized
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );

      if (!walletProvider.isInitialized) {
        // This will trigger wallet initialization if needed
        walletProvider.refreshBalance();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Widget _buildGradientButton({
    required String text,
    required VoidCallback onPressed,
    List<Color>? gradientColors,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          colors:
              gradientColors ??
              [const Color(0xFFFF5A76), const Color(0xFFFF3355)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (gradientColors?.first ?? AppColors.primary).withAlpha(75),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () async {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
          await authProvider.clearUserData();

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        },
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 12.h),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20.sp,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              SizedBox(width: 8.w),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 14.h),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18.sp,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              SizedBox(width: 8.w),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    bool isDanger = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
        leading: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: (iconColor ?? Theme.of(context).colorScheme.primary)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(
            icon,
            size: 20.sp,
            color:
                isDanger
                    ? Colors.red
                    : (iconColor ?? Theme.of(context).colorScheme.primary),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color:
                isDanger ? Colors.red : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle:
            subtitle != null
                ? Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                  ),
                )
                : null,
        trailing: Icon(
          CupertinoIcons.chevron_right,
          size: 16.sp,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 20.h),

                  // Top Row with Settings and Cancel Icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(CupertinoIcons.gear_alt, size: 28.sp),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20.r),
                              ),
                            ),
                            isScrollControlled:
                                true, // Allow the modal to expand fully
                            builder: (context) {
                              return Padding(
                                padding: EdgeInsets.only(
                                  left: 24.w,
                                  right: 24.w,
                                  top: 24.h,
                                  bottom:
                                      MediaQuery.of(context).viewInsets.bottom +
                                      24.h, // Adjust for keyboard
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            CupertinoIcons.xmark,
                                            size: 18.sp,
                                          ),
                                          onPressed:
                                              () => Navigator.of(context).pop(),
                                        ),
                                        SizedBox(width: 24.w),
                                      ],
                                    ),
                                    SizedBox(height: 12.h),
                                    Text(
                                      "Settings & Support",
                                      style: TextStyle(
                                        fontSize: 28.sp,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                      ),
                                    ),
                                    SizedBox(height: 16.h),
                                    Consumer<WalletProvider>(
                                      builder: (context, walletProvider, _) {
                                        String displayAddress =
                                            walletProvider.walletAddress != null
                                                ? '${walletProvider.walletAddress!.substring(0, 4)}...${walletProvider.walletAddress!.substring(walletProvider.walletAddress!.length - 4)}'
                                                : 'Loading...';

                                        return _buildMenuTile(
                                          icon: CupertinoIcons.creditcard,
                                          title: "My Wallet",
                                          subtitle: displayAddress,
                                          onTap: () {},
                                        );
                                      },
                                    ),
                                    _buildMenuTile(
                                      icon: CupertinoIcons.star_fill,
                                      title: "Rate Chum Bucket",
                                      subtitle: "Share your experience",
                                      onTap: () {},
                                      iconColor: Colors.amber,
                                    ),
                                    _buildMenuTile(
                                      icon: CupertinoIcons.question_circle_fill,
                                      title: "Support",
                                      subtitle: "Get help when you need it",
                                      onTap: () {},
                                      iconColor: Colors.blue,
                                    ),
                                    _buildMenuTile(
                                      icon: CupertinoIcons.delete_solid,
                                      title: "Delete Account",
                                      subtitle:
                                          "Permanently remove your account",
                                      onTap: () {},
                                      isDanger: true,
                                    ),
                                    SizedBox(height: 16.h),

                                    // Sign Out Button
                                    _buildGradientButton(
                                      text: "Sign Out",
                                      onPressed: () {},
                                      icon: CupertinoIcons.square_arrow_right,
                                      gradientColors: [
                                        Colors.grey.shade600,
                                        Colors.grey.shade700,
                                      ],
                                    ),

                                    SizedBox(height: 32.h),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(CupertinoIcons.xmark, size: 26.sp),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  SizedBox(height: 12.h),

                  // Profile Header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(24.w),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (context) => const EditProfileScreen(
                                  showCancelIcon: true,
                                ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          FutureBuilder<String>(
                            future:
                                Provider.of<AuthProvider>(
                                          context,
                                          listen: false,
                                        ).currentUser !=
                                        null
                                    ? Provider.of<ProfileProvider>(
                                      context,
                                      listen: false,
                                    ).getUserPfp(
                                      Provider.of<AuthProvider>(
                                        context,
                                        listen: false,
                                      ).currentUser!.id,
                                    )
                                    : Future.value(
                                      'assets/images/ai_gen/profile_images/1.png',
                                    ),
                            builder: (context, snapshot) {
                              return CircleAvatar(
                                radius: 40.w,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.1),
                                backgroundImage:
                                    snapshot.hasData
                                        ? AssetImage(snapshot.data!)
                                        : null,
                                child:
                                    !snapshot.hasData
                                        ? Icon(
                                          CupertinoIcons.person_fill,
                                          size: 40.w,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        )
                                        : null,
                              );
                            },
                          ),
                          SizedBox(width: 6.w),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _username,
                                  style: TextStyle(
                                    fontSize: 24.sp,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                SizedBox(
                                  width: 200.w,
                                  child: Text(
                                    _bio,
                                    textAlign: TextAlign.left,
                                    maxLines: 2,
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withAlpha(120),
                                      fontWeight: FontWeight.w700,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Wallet Balance Card
                  const WalletBalanceCard(),

                  SizedBox(height: 330.h),

                  // Footer
                  Center(
                    child: Text.rich(
                      TextSpan(
                        text: 'Chum Bucket v0.0.1 • ',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(150),
                        ),
                        children: [
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
