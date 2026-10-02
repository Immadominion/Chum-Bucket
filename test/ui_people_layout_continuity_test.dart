import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'ui_people_layout_profile_test.dart' show mountPeople, PeopleRepository;

const walletFixture = '11111111111111111111111111111111';

class ConnectedWallet extends ChangeNotifier implements MwaWalletProvider {
  @override
  LoadingState get loadingState => LoadingState.idle;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int refreshes = 0;
  @override
  String? get walletAddress => walletFixture;
  @override
  bool get isInitialized => true;
  @override
  double get balance => 2.5;
  @override
  Future<void> refreshWalletBalance() async {
    refreshes++;
  }
}

class ConnectedAuth extends MwaAuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String? get walletAddress => walletFixture;
}

class ExistingProfile extends ChangeNotifier implements ProfileProvider {
  final lookups = <String>[];
  final data = <String, dynamic>{
    'id': 'user_ada',
    'full_name': 'Ada Okafor',
    'bio': 'My existing bio.',
    'pfp_path': 'assets/images/ai_gen/profile_images/1.png',
  };
  @override
  Future<Map<String, dynamic>?> fetchUserProfileWithPfp(String id) async {
    lookups.add(id);
    return data;
  }

  @override
  Future<Map<String, dynamic>?> fetchUserProfile(String id) async {
    lookups.add(id);
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'connected private wallet preserves balance refresh and existing receive modal',
    (tester) async {
      final wallet = ConnectedWallet();
      addTearDown(wallet.dispose);
      await mountPeople(
        tester,
        Scaffold(
          body: ProfileHeader(
            username: 'Existing Chum',
            bio: '',
            onEditProfile: () {},
            footer: const ProfileWalletCard(),
          ),
        ),
        width: 390,
        scale: 1,
        wrap:
            (child) => ChangeNotifierProvider<MwaWalletProvider>.value(
              value: wallet,
              child: child,
            ),
      );
      expect(find.text('2.50 SOL'), findsNothing);
      await tester.tap(find.text('My wallet'));
      await tester.pumpAndSettle();
      expect(
        find.text('Private · only you can see this balance'),
        findsOneWidget,
      );
      expect(find.text('2.50 SOL'), findsOneWidget);
      await tester.tap(find.text('Refresh balance'));
      await tester.pumpAndSettle();
      expect(wallet.refreshes, 1);
      // Add funds (Crossmint) leads; the QR receive modal stays one tap away.
      expect(find.text('Add funds'), findsOneWidget);
      await tester.tap(find.text('Receive from another wallet'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletModal), findsOneWidget);
      final modalContext = tester.element(find.byType(WalletModal));
      expect(modalContext.read<MwaWalletProvider>(), same(wallet));
      expect(wallet.refreshes, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing identity keeps settings and the original edit-profile route',
    (tester) async {
      final profile = ExistingProfile();
      final auth = ConnectedAuth();
      final wallet = ConnectedWallet();
      final calls = CallsProvider(repository: PeopleRepository([]))
        ..setViewer('user_ada');
      final account = _OwnAccount();
      addTearDown(profile.dispose);
      addTearDown(auth.dispose);
      addTearDown(wallet.dispose);
      addTearDown(calls.dispose);
      await mountPeople(
        tester,
        const ProfileScreen(embedded: true),
        width: 390,
        scale: 1,
        wrap:
            (child) => MultiProvider(
              providers: [
                ChangeNotifierProvider<ProfileProvider>.value(value: profile),
                ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
                ChangeNotifierProvider<MwaWalletProvider>.value(value: wallet),
                ChangeNotifierProvider<CallsProvider>.value(value: calls),
                // The editor reads and writes the account through the BFF.
                Provider<AccountApi>.value(value: account),
              ],
              child: child,
            ),
      );
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(find.text('My existing bio.'), findsOneWidget);
      expect(profile.lookups, [walletFixture]);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(ProfileSettingsSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Ada Okafor'), findsOneWidget);
      // The editor loaded the account (account.me), not the wallet's row.
      expect(account.lookups, greaterThanOrEqualTo(1));
      expect(find.text('Create my profile'), findsNothing);
      expect(find.text('Complete Your Profile'), findsNothing);
      expect(find.text('Edit Profile'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel editing'));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

/// The signed-in person's own account, as `account.me` returns it.
class _OwnAccount implements AccountApi {
  int lookups = 0;
  @override
  Future<AccountProfile> me() async {
    lookups++;
    return const AccountProfile(
      userId: 'user_ada',
      displayName: 'Ada Okafor',
      bio: 'My existing bio.',
      avatarId: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
