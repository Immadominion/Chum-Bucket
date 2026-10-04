import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/cache/snapshot_store.dart';
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
  int _selectedTab = 0;
  int _request = 0;

  /// Bumped by pull-to-refresh so Positions reads again too.
  int _refreshTick = 0;

  Future<void> _pullToRefresh() async {
    setState(() => _refreshTick++);
    await _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    if (!mounted) return;
    final calls = context.read<CallsProvider?>();
    final wallet = context.read<MwaAuthProvider?>()?.walletAddress;
    final userId = calls?.viewerUserId;
    final profileProvider = context.read<ProfileProvider?>();
    final request = ++_request;
    // A sign-out while this reads wipes the store: the account is then not
    // written back.
    final generation = SnapshotStore.device.generation;
    setState(() => _loadingProfile = true);
    // Your account as last seen draws at once; the live read replaces it.
    if (userId != null && _ownProfile?.userId != userId) {
      unawaited(_paintSavedOwnProfile(userId, request));
    }
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
      });
    } catch (_) {
      // A failed refresh keeps what is on screen; nothing is narrated.
    } finally {
      await personRead;
      final own = await ownRead;
      if (mounted && request == _request) {
        setState(() {
          if (own != null && own.userId == userId) {
            _ownProfile = own;
          } else if (_ownProfile?.userId != userId) {
            _ownProfile = null;
          }
          _loadingProfile = false;
        });
        if (own != null &&
            own.userId == userId &&
            context.read<CallsProvider?>()?.viewerUserId == userId) {
          unawaited(
            SnapshotStore.device.write(
              snapshotKey('account', viewer: userId),
              own.toJson(),
              generation: generation,
            ),
          );
        }
      }
    }
  }

  Future<void> _paintSavedOwnProfile(String userId, int request) async {
    final saved = await SnapshotStore.device.read(
      snapshotKey('account', viewer: userId),
    );
    if (saved == null || !mounted || request != _request) return;
    if (_ownProfile?.userId == userId) return;
    try {
      final profile = AccountProfile.fromJson(saved);
      if (profile.userId != userId) return;
      setState(() => _ownProfile = profile);
    } catch (_) {
      // An unreadable snapshot is ignored.
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
          onRefresh: _pullToRefresh,
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
                      // Signed out there is no record to show: the Calls
                      // tab below offers sign-in instead of empty tiles.
                      if (userId != null)
                        ProfileStatsCard(entries: detail?.calls),
                    ],
                  ),
                ),
              ),
              if (needsHandle) ...[
                const SizedBox(height: 16),
                _ProfileActionRow(
                  key: const ValueKey('profile-claim-handle'),
                  icon: 'at-sign-outline',
                  title: 'Claim your @username',
                  onTap: () => showClaimHandleSheet(context),
                ),
              ],
              if (openEscrow.isNotEmpty) ...[
                const SizedBox(height: 12),
                // Earlier SOL escrow challenges still holding SOL stay one tap
                // away until they are settled: a slim row, shown only while
                // one is really open. Who has to act is said in its label for
                // screen readers and on the History screen it opens.
                _ProfileActionRow(
                  key: const ValueKey('profile-open-escrow'),
                  icon: 'lock-time-outline',
                  title:
                      openEscrow.length == 1
                          ? 'Escrow still open'
                          : '${openEscrow.length} escrows still open',
                  semanticsHint:
                      openEscrow.any(
                            (c) => wallet != null && c.witnessAddress == wallet,
                          )
                          ? 'You’re the witness: only you can settle it.'
                          : 'Your SOL stays in escrow until the witness settles it.',
                  tone: AppColors.warningContainer,
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
                ChumbucketStateView(
                  artwork: ChumbucketStateArtwork.record,
                  message: 'Sign in to keep your record',
                  semanticsHint: session?.error?.message,
                  actionLabel: session == null ? null : 'Sign in',
                  actionIcon: 'login-outline',
                  onAction:
                      session == null ? null : () => requestCallSignIn(context),
                )
              else if (_selectedTab == 0 && userId != null)
                ..._callRecord(calls, detail, userId, styles),
              // Real funded Panta positions, private to this account.
              if (_selectedTab == 1)
                ProfilePositionsTab(refreshTick: _refreshTick),
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
      final loading =
          userId != null && (provider?.isLoadingPerson(userId) ?? false);
      if (error == null || loading) return const [_CallsSkeleton()];
      return [
        ChumbucketStateView(
          artwork: ChumbucketStateArtwork.error,
          message: 'Couldn’t load your calls',
          semanticsHint: CallsErrorView.isHumanReason(error) ? error : null,
          actionLabel: 'Try again',
          onAction: _loadProfileData,
        ),
      ];
    }
    if (detail.calls.isEmpty) {
      return const [
        ChumbucketStateView(
          artwork: ChumbucketStateArtwork.record,
          message: 'No calls on record yet',
          semanticsHint: 'Your calls appear here once you make one.',
        ),
      ];
    }
    return [
      // Saved calls stay on screen; offline is only a small pill.
      if (provider?.isOffline == true)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ChumbucketOfflinePill(),
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

/// Two quiet call-shaped placeholders while the first read of your record
/// runs.
class _CallsSkeleton extends StatelessWidget {
  const _CallsSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your calls',
    child: Column(
      children: [
        for (var i = 0; i < 2; i++)
          Container(
            height: 120,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    ),
  );
}

/// One slim tappable row: icon, a few words, a chevron.
class _ProfileActionRow extends StatelessWidget {
  final String icon;
  final String title;
  final String? semanticsHint;
  final Color tone;
  final VoidCallback? onTap;
  const _ProfileActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.semanticsHint,
    this.tone = AppColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: title,
      hint: semanticsHint,
      excludeSemantics: true,
      child: Material(
        color: tone,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  BasilIcon(icon, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const BasilIcon(
                      'arrow-right-outline',
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
