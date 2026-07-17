import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
// MWA Auth Provider for wallet-based authentication
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';

class ProfileScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onOpenChallenges;

  const ProfileScreen({
    super.key,
    this.embedded = false,
    this.onOpenChallenges,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;

  String _username = 'Username';
  String _bio = 'This is a short bio that describes the user.';
  String? _lastLoadedWallet; // Track which wallet we loaded data for

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
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );

      if (authProvider.isAuthenticated) {
        final walletAddress = authProvider.walletAddress!;

        // Skip if we already loaded for this wallet
        if (_lastLoadedWallet == walletAddress && _username != 'Username') {
          debugPrint('🔄 Profile already loaded for wallet: $walletAddress');
          return;
        }

        debugPrint('🔍 Loading profile for wallet: $walletAddress');

        // ALWAYS fetch from database first for correct data (skip local cache)
        // Local cache might be stale from previous user
        var profile = await profileProvider.fetchUserProfileWithPfp(
          walletAddress,
        );
        debugPrint('🗄️ Database profile: $profile');

        if (mounted) {
          setState(() {
            _lastLoadedWallet = walletAddress;
            if (profile != null) {
              _username =
                  profile['full_name'] ??
                  profile['name'] ??
                  // For MWA, show truncated wallet address if no name
                  '${walletAddress.substring(0, 4)}...${walletAddress.substring(walletAddress.length - 4)}';
              _bio =
                  profile['bio'] ??
                  'This is a short bio that describes the user.';
              debugPrint(
                '✅ Profile loaded: $_username (from ${profile.keys.toList()})',
              );
            } else {
              // If no profile, use wallet address as fallback
              _username =
                  '${walletAddress.substring(0, 4)}...${walletAddress.substring(walletAddress.length - 4)}';
              _bio = 'This is a short bio that describes the user.';
              debugPrint('🔄 Using wallet address fallback: $_username');
            }
          });
        }
      }

      if (!mounted) return;
      final walletProvider = Provider.of<MwaWalletProvider>(
        context,
        listen: false,
      );
      walletProvider.refreshWalletBalance();

      final wallet = authProvider.walletAddress;
      if (wallet != null && mounted) {
        final arena = context.read<ArenaProvider>();
        await Future.wait([
          arena.loadMyPots(walletAddress: wallet),
          arena.loadProfile(targetWallet: wallet, viewerWallet: wallet),
        ]);
      }
    } catch (e) {
      debugPrint('❌ Error loading profile: $e');
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
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadProfileData,
          child: ListView(
            key: const PageStorageKey('profile-root'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20.w,
              12.h,
              20.w,
              widget.embedded ? 112.h : 32.h,
            ),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => showProfileSettingsSheet(context),
                    icon: BasilIcon(
                      'settings-outline',
                      size: 28.w,
                      color: AppColors.primary,
                    ),
                  ),
                  if (!widget.embedded)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: BasilIcon(
                        'cancel-outline',
                        size: 30.w,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              ProfileHeader(
                username: _username,
                bio: _bio,
                onEditProfile: _onEditProfile,
              ),
              SizedBox(height: 20.h),
              const ProfileWalletCard(),
              SizedBox(height: 24.h),
              Consumer2<ArenaProvider, MwaAuthProvider>(
                builder: (context, arena, auth, _) {
                  final wallet = auth.walletAddress;
                  final profile =
                      wallet == null ? null : arena.cachedProfile(wallet);
                  return _PredictionSummary(profile: profile);
                },
              ),
              SizedBox(height: 24.h),
              Text(
                'Your activity',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 12.h),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Consumer<ArenaProvider>(
                      builder:
                          (context, arena, _) => _ProfileActionRow(
                            icon: 'hotspot-outline',
                            title: 'Prediction history',
                            detail:
                                '${arena.myPots.length} ${arena.myPots.length == 1 ? 'position' : 'positions'}',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MyPotsScreen(),
                                ),
                              );
                            },
                          ),
                    ),
                    Divider(
                      height: 1,
                      indent: 16.w,
                      endIndent: 16.w,
                      color: AppColors.divider,
                    ),
                    Consumer<ChallengeStateProvider>(
                      builder:
                          (context, challengeState, _) => _ProfileActionRow(
                            icon: 'contacts-outline',
                            title: 'Challenge history',
                            detail:
                                '${challengeState.challenges.length} ${challengeState.challenges.length == 1 ? 'challenge' : 'challenges'}',
                            onTap: widget.onOpenChallenges,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 34.h),
              Center(
                child: Text(
                  'Chum Bucket v0.0.1',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
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

// Plain inline stat row — no card chrome. The wallet balance above and the
// "Your activity" list below are already white cards; a third white box in
// between just reads as more of the same rather than as its own thing.
// Thin dividers give it separation without another rounded rectangle.
class _PredictionSummary extends StatelessWidget {
  final ArenaSocialProfile? profile;

  const _PredictionSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    final stats = profile?.stats;
    final calls = stats?.callsMade ?? 0;
    final winRate = stats?.winRate ?? 0.0;
    final pnl = stats?.pnlBaseUnits ?? BigInt.zero;
    return Row(
      children: [
        _SummaryStat(label: 'Calls', value: '$calls'),
        const _StatDivider(),
        _SummaryStat(label: 'Win rate', value: '${(winRate * 100).round()}%'),
        const _StatDivider(),
        _SummaryStat(
          label: 'PnL',
          value: _formatPnl(pnl),
          color:
              pnl > BigInt.zero
                  ? AppColors.success
                  : pnl < BigInt.zero
                  ? AppColors.error
                  : AppColors.textSecondary,
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32.h, color: AppColors.divider);
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _SummaryStat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.sp),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionRow extends StatelessWidget {
  final String icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  const _ProfileActionRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      leading: Container(
        width: 42.w,
        height: 42.w,
        decoration: const BoxDecoration(
          color: AppColors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: BasilIcon(icon, color: AppColors.primary, size: 20.w),
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        detail,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11.sp),
      ),
      trailing: const BasilIcon(
        'caret-right-outline',
        color: AppColors.textTertiary,
      ),
    );
  }
}

String _formatPnl(BigInt baseUnits) {
  final amount = baseUnits.toDouble() / 1000000;
  final sign = amount > 0 ? '+' : '';
  return '$sign${NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 1).format(amount)}';
}
