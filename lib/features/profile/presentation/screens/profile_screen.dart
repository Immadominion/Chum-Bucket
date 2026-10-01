import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_stats_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/widgets/profile_picture_selection_modal.dart';

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

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _existingProfile;
  String? _profileWallet;
  String? _requestedIdentity;
  bool _loadingProfile = false;
  String? _profileError;
  int _selectedTab = 0;
  int _request = 0;

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    final calls = context.read<CallsProvider?>();
    final wallet = context.read<MwaAuthProvider?>()?.walletAddress;
    final userId = calls?.viewerUserId;
    final profileProvider = context.read<ProfileProvider?>();
    final request = ++_request;
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });
    // This is the canonical user id supplied by the existing session, never
    // derived from a wallet. The wallet lookup remains the old profile flow.
    final personRead =
        userId == null ? null : calls?.loadPerson(userId, force: true);
    try {
      final profile =
          wallet == null || profileProvider == null
              ? null
              : await profileProvider.fetchUserProfileWithPfp(wallet);
      if (!mounted ||
          request != _request ||
          context.read<MwaAuthProvider?>()?.walletAddress != wallet) {
        return;
      }
      setState(() {
        _profileWallet = wallet;
        _existingProfile = profile;
        _profileError =
            wallet != null && profile == null
                ? 'Your existing profile could not be loaded. Pull down to retry.'
                : null;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () =>
              _profileError =
                  'Your profile is unavailable. Pull down to retry.',
        );
      }
    } finally {
      await personRead;
      if (mounted && request == _request) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  Future<void> _onEditProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EditProfileScreen(showCancelIcon: true),
      ),
    );
    if (mounted) await _loadProfileData();
  }

  Future<void> _onEditAvatar(String image) async {
    await ProfilePictureSelectionModal.show(
      context,
      currentProfilePicture: image,
    );
    if (mounted) await _loadProfileData();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<MwaAuthProvider?>();
    final calls = context.watch<CallsProvider?>();
    final session = context.watch<ChumbucketSession?>();
    final challenges = context.watch<ChallengeStateProvider?>();
    final wallet = auth?.walletAddress;
    final userId = calls?.viewerUserId;
    final identityKey = '$userId|$wallet';
    if (_requestedIdentity != identityKey) {
      _requestedIdentity = identityKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadProfileData();
      });
    }
    final detail = userId == null ? null : calls?.personDetail(userId);
    final person = detail?.person;
    // Do not merge data from unrelated linked credentials.
    final existing =
        _profileWallet == wallet &&
                (person == null ||
                    _existingProfile?['id'] == person.id ||
                    person.walletAddress == wallet)
            ? _existingProfile
            : null;
    final name =
        person?.displayName ??
        existing?['full_name']?.toString() ??
        existing?['name']?.toString() ??
        'Your profile';
    final image = person?.avatarUrl ?? existing?['pfp_path']?.toString();
    final styles = AppTextStyles.textTheme;
    final canEdit = auth?.isAuthenticated == true && existing != null;
    final pending = session?.isBusy == true || _loadingProfile;
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
            padding: EdgeInsets.fromLTRB(16, 8, 16, widget.embedded ? 140 : 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Profile', style: styles.headlineMedium),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => showProfileSettingsSheet(context),
                    icon: const BasilIcon(
                      'settings-outline',
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (!widget.embedded)
                    IconButton(
                      tooltip: 'Close',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const BasilIcon(
                        'cancel-outline',
                        color: AppColors.textPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: AppColors.outlineVariant,
                  child: Column(
                    children: [
                      ProfileHeader(
                        username: name,
                        handle: person?.handle,
                        bio: existing?['bio']?.toString() ?? '',
                        profileImagePath: image,
                        canEdit: canEdit,
                        onEditProfile: _onEditProfile,
                        onEditAvatar:
                            canEdit && image != null
                                ? () => _onEditAvatar(image)
                                : null,
                        footer: const ProfileWalletCard(),
                      ),
                      ProfileStatsCard(entries: detail?.calls),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Public free calls shown here, including incorrect calls. '
                'Separate from trading performance.',
                style: styles.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (pending) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text('Loading your existing profile…', style: styles.bodySmall),
              ],
              if (_profileError != null && person == null) ...[
                const SizedBox(height: 12),
                Text(_profileError!, style: styles.bodyMedium),
              ],
              if (userId == null && !pending) ...[
                const SizedBox(height: 16),
                _ProfileActionRow(
                  icon: 'user-outline',
                  title:
                      wallet != null
                          ? 'Connect your existing account'
                          : 'Sign in to your account',
                  detail:
                      session?.error?.message ??
                      'Recover your profile to see your call record.',
                  onTap:
                      session == null ? null : () => requestCallSignIn(context),
                ),
              ],
              if (challenges != null &&
                  challenges.pendingChallenges.isNotEmpty) ...[
                const SizedBox(height: 16),
                _ProfileActionRow(
                  icon: 'clock-outline',
                  title: 'Active challenges',
                  detail: 'Open your challenges to review outstanding actions.',
                  onTap: widget.onOpenChallenges,
                ),
              ],
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ChumbucketTabs(
                  labels: const ['Calls', 'Positions', 'Challenges'],
                  selectedIndex: _selectedTab,
                  onSelected: (index) => setState(() => _selectedTab = index),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedTab == 0)
                ..._callRecord(calls, detail, userId, styles),
              if (_selectedTab == 1)
                _ProfileActionRow(
                  icon: 'lock-outline',
                  title: 'Private positions',
                  detail:
                      'Your Panta positions are not available here yet. '
                      'Free calls are not positions, and submitted orders are not confirmed fills.',
                  onTap: null,
                ),
              if (_selectedTab == 2) ...[
                _ProfileActionRow(
                  icon: 'contacts-outline',
                  title: 'Challenge history',
                  detail:
                      widget.onOpenChallenges == null
                          ? 'Your challenge history is unavailable from this screen.'
                          : 'Your original challenges, including active actions, claims and refunds.',
                  onTap: widget.onOpenChallenges,
                ),
                const SizedBox(height: 12),
                _ProfileActionRow(
                  icon: 'hotspot-outline',
                  title: 'Prediction history',
                  detail:
                      'Open your existing predictions and their original terms.',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyPotsScreen()),
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _callRecord(
    CallsProvider? provider,
    PersonDetail? detail,
    String? userId,
    TextTheme styles,
  ) {
    if (detail == null) {
      final error = userId == null ? null : provider?.personError(userId);
      return [
        _ProfileActionRow(
          icon: 'comment-outline',
          title: 'Your calls',
          detail:
              error ??
              (userId == null
                  ? 'Connect your existing account to load your calls.'
                  : 'Your call record is not available yet.'),
          onTap: userId == null ? null : _loadProfileData,
        ),
      ];
    }
    if (detail.calls.isEmpty) {
      return [
        const CallsEmptyView(
          artwork: ChumbucketStateArtwork.record,
          title: 'Nothing on record yet',
          message:
              'Your calls will appear here once you make one. Calling is free.',
        ),
      ];
    }
    return [
      if (provider?.isOffline == true || provider?.personError(userId!) != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Showing saved calls. Pull down to retry.',
            style: styles.bodySmall,
          ),
        ),
      for (final entry in detail.calls)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CallCard(
            entry: entry,
            showAuthor: false,
            onOpenCall:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallDetailScreen(callId: entry.call.id),
                  ),
                ),
          ),
        ),
    ];
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
    final styles = AppTextStyles.textTheme;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        leading: BasilIcon(icon, color: AppColors.textPrimary),
        title: Text(title, style: styles.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            detail,
            style: styles.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
        trailing:
            onTap == null
                ? null
                : const BasilIcon(
                  'arrow-right-outline',
                  color: AppColors.textPrimary,
                ),
      ),
    );
  }
}
