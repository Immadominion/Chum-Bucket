import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/claim_handle_sheet.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/data/avatar_catalog.dart';
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
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_positions_tab.dart';

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
  /// The signed-in account's own profile (`account.me`): name, bio and
  /// avatar for wallet AND Google/X sign-ins.
  AccountProfile? _ownProfile;
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
    final api = userId == null ? null : accountApiOf(context);
    final ownRead = api?.me().then<AccountProfile?>((p) => p).catchError(
      (Object _) => null,
    );
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
      final own = await ownRead;
      if (mounted && request == _request) {
        setState(() {
          _ownProfile = own != null && own.userId == userId ? own : null;
          _loadingProfile = false;
        });
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
    final wallet = auth?.walletAddress;
    // This wallet's own escrows: the provider is loaded per wallet.
    final openEscrow =
        context.watch<ChallengeStateProvider?>()?.openChallenges ?? const [];
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
    final own = _ownProfile?.userId == userId ? _ownProfile : null;
    // Do not merge data from unrelated linked credentials. The account's own
    // wallet comes from account.me: no social payload carries anybody's
    // wallet any more (lockdown M2), the viewer's own included.
    final existing =
        _profileWallet == wallet &&
                (person == null ||
                    _existingProfile?['id'] == person.id ||
                    (wallet != null && own?.walletAddress == wallet))
            ? _existingProfile
            : null;
    final name =
        own?.displayName ??
        person?.displayName ??
        existing?['full_name']?.toString() ??
        existing?['name']?.toString() ??
        'Your profile';
    final image =
        (own?.avatarId != null ? own!.avatarAsset : null) ??
        person?.avatarUrl ??
        existing?['pfp_path']?.toString();
    // The account's own stored @username wins over the calls directory's
    // copy, which shows a `user-xxxxxxxx` placeholder for an account without
    // one. No username yet: no handle line, and a row below to claim one.
    final needsHandle = session?.needsHandleClaim == true;
    final handle = session?.handle ?? (needsHandle ? null : person?.handle);
    final styles = AppTextStyles.textTheme;
    // Your own Chumbucket account — wallet, Google or X — is what you edit
    // (account.updateProfile), not a wallet's legacy row. A wallet that has
    // not signed in to an account yet still gets the button: the editor then
    // offers sign-in rather than a save that would go nowhere.
    final canEdit =
        (session?.isReady == true && userId != null) ||
        auth?.isAuthenticated == true;
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
                    onPressed:
                        () => showProfileSettingsSheet(
                          context,
                          onOpenChallenges: widget.onOpenChallenges,
                        ),
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
                        handle: handle,
                        bio: own?.bio ?? existing?['bio']?.toString() ?? '',
                        profileImagePath: image,
                        canEdit: canEdit,
                        onEditProfile: _onEditProfile,
                        onEditAvatar:
                            canEdit
                                ? () => _onEditAvatar(
                                  image ?? avatarAssetFor(kDefaultAvatarId)!,
                                )
                                : null,
                        footer: const ProfileWalletCard(),
                      ),
                      ProfileStatsCard(entries: detail?.calls),
                    ],
                  ),
                ),
              ),
              // What the record counts, once there is a record to read.
              if (detail != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Public free calls shown here, including incorrect calls. '
                  'Separate from trading performance.',
                  style: styles.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
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
              if (needsHandle) ...[
                const SizedBox(height: 16),
                _ProfileActionRow(
                  key: const ValueKey('profile-claim-handle'),
                  icon: 'user-plus-outline',
                  title: 'Claim your @username',
                  detail:
                      'Your calls show a placeholder name until you pick one.',
                  onTap: () => showClaimHandleSheet(context),
                ),
              ],
              if (openEscrow.isNotEmpty) ...[
                const SizedBox(height: 16),
                // Earlier SOL escrow challenges still holding SOL stay one tap
                // away until they are settled. Only the witness can settle
                // one, so say who has to act.
                _ProfileActionRow(
                  key: const ValueKey('profile-open-escrow'),
                  icon: 'clock-outline',
                  title:
                      openEscrow.length == 1
                          ? 'An escrow challenge is still open'
                          : '${openEscrow.length} escrow challenges are still open',
                  detail:
                      openEscrow.any(
                            (c) => wallet != null && c.witnessAddress == wallet,
                          )
                          ? 'You’re the witness, so only you can settle it '
                              'and release the SOL.'
                          : 'Your SOL stays in escrow until the witness '
                              'settles it.',
                  onTap: widget.onOpenChallenges,
                ),
              ],
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ChumbucketTabs(
                  labels: const ['Calls', 'Positions'],
                  selectedIndex: _selectedTab,
                  onSelected: (index) => setState(() => _selectedTab = index),
                ),
              ),
              const SizedBox(height: 16),
              // Only the call record needs the linked account, so its tab is
              // where the account is connected — once, not above and inside.
              // Only the call record needs a signed-in account, so its tab
              // is where signing in is offered.
              if (_selectedTab == 0 && userId == null && !pending)
                _ProfileActionRow(
                  icon: 'user-outline',
                  title: 'Sign in',
                  detail:
                      session?.error?.message ??
                      'Use your wallet, Google or X. Your call record '
                          'appears here.',
                  onTap:
                      session == null ? null : () => requestCallSignIn(context),
                )
              else if (_selectedTab == 0 && userId != null)
                ..._callRecord(calls, detail, userId, styles),
              // Real funded Panta positions, private to this account.
              if (_selectedTab == 1) const ProfilePositionsTab(),
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
          detail: error ?? 'Your call record is not available yet.',
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
    super.key,
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
