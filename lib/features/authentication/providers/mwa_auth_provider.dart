import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/analytics_service.dart';
import 'package:chumbucket/core/config/network_config.dart';
import '../session/mwa_auth_result.dart';
import '../session/mwa_authorization_failure.dart';
import '../session/existing_wallet_profile_guard.dart';
import '../session/mwa_session_storage.dart';
export '../session/mwa_auth_result.dart';

/// Authentication state for MWA-based auth
enum MwaAuthState { initial, loading, authenticated, unauthenticated, error }

/// MWA-based authentication provider for Solana Mobile compatibility
/// Replaces Privy authentication with native Mobile Wallet Adapter
class MwaAuthProvider extends ChangeNotifier {
  MwaAuthProvider({
    MwaSessionStorage? sessionStorage,
    SupabaseClient? supabaseClient,
    bool? existingProfileOnly,
  }) : _sessionStorage = sessionStorage ?? MwaSessionStorage.device,
       _supabase = supabaseClient,
       _existingProfileOnly =
           existingProfileOnly ??
           const bool.fromEnvironment(
             'CHUMBUCKET_EXISTING_PROFILE_ONLY',
             defaultValue: false,
           );
  final MwaSessionStorage _sessionStorage;
  final bool _existingProfileOnly;
  int _authEpoch = 0;
  bool _disposed = false;
  bool _isCurrent(int epoch) => !_disposed && epoch == _authEpoch;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authEpoch++;
    super.dispose();
  }

  // App identity for MWA authorization
  static const String _appName = 'Chumbucket';
  static const String _identityUri = 'https://chumbucket.fun';
  static const String _iconPath = 'favicon.ico';

  // Cluster configuration - uses centralized NetworkConfig
  static String get _cluster => NetworkConfig.currentNetwork;

  MwaAuthState _state = MwaAuthState.initial;
  MwaAuthResult? _authResult;
  String? _errorMessage;
  SupabaseClient? _supabase;

  // Getters
  MwaAuthState get state => _state;
  MwaAuthResult? get authResult => _authResult;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated =>
      _state == MwaAuthState.authenticated && _authResult != null;
  String? get walletAddress => _authResult?.walletAddress;
  Uint8List? get publicKeyBytes => _authResult?.publicKeyBytes;
  String? get authToken => _authResult?.authToken;

  /// Invalidates account-bound work even after sign-out then reconnecting A -> A.
  int get authRevision => _authEpoch;

  /// Get the user's SNS domain (.sol, .skr) if available
  String? get snsDomain => _authResult?.snsDomain;

  /// Check if user has a Seeker wallet domain (.skr)
  bool get hasSeekerDomain => _authResult?.hasSeekerDomain ?? false;

  /// Get display name (domain if available, otherwise shortened address)
  String get displayName => _authResult?.displayName ?? 'Unknown';

  /// Check if user is logged in (async version with persistence check)
  Future<bool> isLoggedIn() async {
    final epoch = _authEpoch;
    // If already authenticated in memory, return true
    if (isAuthenticated) return true;

    // A boolean preference alone is never evidence of a restorable credential.
    try {
      final saved = await _sessionStorage.restore(
        isCurrent: () => _isCurrent(epoch),
      );
      if (!_isCurrent(epoch) || saved == null) return false;
      if (!_existingProfileOnly) return true;
      final existing = await _existingProfileForWallet(saved.walletAddress);
      return _isCurrent(epoch) && existing == ExistingWalletProfile.found;
    } catch (_) {
      return false;
    }
  }

  /// Initialize the auth provider
  Future<void> initialize() async {
    final epoch = _authEpoch;
    _errorMessage = null;
    log('🔐 Initializing MWA Auth Provider', name: 'MwaAuthProvider');

    try {
      _supabase ??= Supabase.instance.client;

      // Try to restore previous auth session
      final restored = await _restoreAuthSession();
      if (!_isCurrent(epoch)) return;
      if (restored) {
        log('✅ Restored previous auth session', name: 'MwaAuthProvider');
        _state = MwaAuthState.authenticated;
      } else {
        log('📝 No previous session found', name: 'MwaAuthProvider');
        _state = MwaAuthState.unauthenticated;
      }
    } catch (e) {
      if (!_isCurrent(epoch)) return;
      log('⚠️ Error initializing wallet session', name: 'MwaAuthProvider');
      _authResult = null;
      _errorMessage =
          'Could not unlock the saved wallet session. Unlock your device and try again.';
      _state = MwaAuthState.unauthenticated;
    }

    notifyListeners();
  }

  /// Check if MWA-compatible wallet is available on device
  Future<bool> isWalletAvailable() async {
    try {
      return await LocalAssociationScenario.isAvailable();
    } catch (e) {
      log('Error checking wallet availability', name: 'MwaAuthProvider');
      return false;
    }
  }

  /// Authorize with a mobile wallet using MWA protocol
  /// This replaces Privy's email-based auth with wallet-based auth
  Future<bool> authorize() async {
    if (_disposed || _state == MwaAuthState.loading) return false;
    final epoch = ++_authEpoch;
    var step = MwaAuthorizationStep.walletDiscovery;
    LocalAssociationScenario? session;
    log('🚀 Starting MWA authorization', name: 'MwaAuthProvider');

    _state = MwaAuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check if MWA wallet is available
      final available = await isWalletAvailable();
      if (!_isCurrent(epoch)) return false;
      if (!available) {
        _errorMessage =
            'No MWA-compatible wallet found. Please install Phantom, Solflare, or another Solana wallet.';
        _state = MwaAuthState.error;
        notifyListeners();
        return false;
      }

      // Create MWA session
      step = MwaAuthorizationStep.sessionCreation;
      session = await LocalAssociationScenario.create();

      // Launch wallet app for authorization
      // This triggers the wallet to open for user approval
      step = MwaAuthorizationStep.walletLaunch;
      session.startActivityForResult(null).ignore();

      // Start the session and get client
      step = MwaAuthorizationStep.association;
      final client = await session.start();

      // Request authorization from the wallet
      step = MwaAuthorizationStep.walletApproval;
      final result = await client.authorize(
        identityUri: Uri.parse(_identityUri),
        iconUri: Uri.parse(_iconPath),
        identityName: _appName,
        cluster: _cluster,
      );

      // Close the session
      step = MwaAuthorizationStep.sessionClose;
      await session.close();
      session = null;

      if (!_isCurrent(epoch)) return false;

      if (result == null) {
        _errorMessage = 'Authorization was cancelled or failed';
        _state = MwaAuthState.error;
        notifyListeners();
        return false;
      }

      // Convert public key bytes to base58 wallet address
      final walletAddress = base58encode(result.publicKey);

      // Look up any SNS domain (.sol, .skr) for this wallet
      String? snsDomain;
      try {
        log('🔍 Looking up SNS domain for wallet...', name: 'MwaAuthProvider');
        final domainName = await AddressNameResolver.resolveDisplayName(
          walletAddress,
        );
        // If it's not just a shortened address, it's a domain
        if (!domainName.contains('...') && domainName != walletAddress) {
          snsDomain = domainName;
          log('🏷️ Found SNS domain', name: 'MwaAuthProvider');
        }
      } catch (_) {
        log('⚠️ Domain lookup failed (non-critical)', name: 'MwaAuthProvider');
      }

      if (!_isCurrent(epoch)) return false;

      if (_existingProfileOnly) {
        step = MwaAuthorizationStep.existingProfileCheck;
        final existing = await _existingProfileForWallet(walletAddress);
        if (!_isCurrent(epoch)) return false;
        if (existing != ExistingWalletProfile.found) {
          _authResult = null;
          _errorMessage =
              existing == ExistingWalletProfile.missing
                  ? 'No existing Chumbucket profile was found for this wallet. No profile was created.'
                  : 'Could not confirm your existing Chumbucket profile for this wallet. No profile was created. Please try again.';
          _state = MwaAuthState.error;
          notifyListeners();
          return false;
        }
      }

      _authResult = MwaAuthResult(
        walletAddress: walletAddress,
        authToken: result.authToken,
        publicKeyBytes: result.publicKey,
        accountLabel: result.accountLabel,
        walletUriBase: result.walletUriBase,
        snsDomain: snsDomain,
      );

      log('✅ Authorization successful', name: 'MwaAuthProvider');

      // Persist auth result
      step = MwaAuthorizationStep.secureSave;
      await _persistAuthSession();
      if (!_isCurrent(epoch)) return false;

      // Sync user with Supabase (include domain if available)
      step = MwaAuthorizationStep.accountSync;
      if (!_existingProfileOnly) {
        await _syncUserWithSupabase(walletAddress, snsDomain: snsDomain);
      }
      if (!_isCurrent(epoch)) return false;

      // Register FCM token for push notifications (fire-and-forget)
      FcmTokenService.registerToken(
        walletAddress: walletAddress,
        displayName: snsDomain ?? result.accountLabel,
      ).catchError((e) {
        log('⚠️ Failed to register notifications', name: 'MwaAuthProvider');
      });

      // Assign profile picture
      step = MwaAuthorizationStep.profileLoad;
      final profileProvider = ProfileProvider();
      await profileProvider.getUserPfp(walletAddress);
      if (!_isCurrent(epoch)) return false;

      _state = MwaAuthState.authenticated;
      notifyListeners();
      return true;
    } on PlatformException {
      if (!_isCurrent(epoch)) return false;
      log('❌ Platform error at ${step.name}', name: 'MwaAuthProvider');
      _errorMessage = mwaAuthorizationFailureMessage(step);
      _state = MwaAuthState.error;
      notifyListeners();
      return false;
    } catch (e) {
      if (!_isCurrent(epoch)) return false;
      log('❌ Authorization error at ${step.name}', name: 'MwaAuthProvider');
      _errorMessage = mwaAuthorizationFailureMessage(step);
      _state = MwaAuthState.error;
      notifyListeners();
      return false;
    } finally {
      // A rejected or timed-out wallet handoff must not leave a native MWA
      // association alive and poison the next explicit connection attempt.
      try {
        await session?.close();
      } catch (_) {
        log('⚠️ Failed to close MWA session', name: 'MwaAuthProvider');
      }
    }
  }

  /// Reauthorize an existing session (used before signing transactions)
  /// Returns the MWA client for transaction signing
  Future<MobileWalletAdapterClient?> reauthorize() async {
    final epoch = _authEpoch;
    final held = _authResult;
    if (_authResult == null) {
      log(
        '❌ Cannot reauthorize: no existing auth result',
        name: 'MwaAuthProvider',
      );
      return null;
    }

    log('🔄 Reauthorizing MWA session', name: 'MwaAuthProvider');

    try {
      final session = await LocalAssociationScenario.create();
      session.startActivityForResult(null).ignore();
      final client = await session.start();

      final result = await client.reauthorize(
        identityUri: Uri.parse(_identityUri),
        iconUri: Uri.parse(_iconPath),
        identityName: _appName,
        authToken: held!.authToken,
      );

      if (result == null ||
          !_isCurrent(epoch) ||
          base58encode(result.publicKey) != held.walletAddress) {
        log(
          '⚠️ Reauthorization failed, need full authorization',
          name: 'MwaAuthProvider',
        );
        await session.close();
        return null;
      }

      // Update auth result with new token
      final walletAddress = base58encode(result.publicKey);
      _authResult = MwaAuthResult(
        walletAddress: walletAddress,
        authToken: result.authToken,
        publicKeyBytes: result.publicKey,
        accountLabel: result.accountLabel,
        walletUriBase: result.walletUriBase,
        snsDomain: held.snsDomain,
      );

      await _persistAuthSession();
      if (!_isCurrent(epoch)) {
        await session.close();
        return null;
      }

      log('✅ Reauthorization successful', name: 'MwaAuthProvider');

      // Return client for signing - caller must close session when done
      return client;
    } catch (e) {
      log('❌ Error during reauthorization', name: 'MwaAuthProvider');
      return null;
    }
  }

  /// Create a new MWA session for signing transactions
  /// Returns session and client - caller is responsible for closing session
  Future<MwaSigningSession?> createSigningSession({String? cluster}) async {
    final epoch = _authEpoch;
    final held = _authResult;
    if (_authResult == null) {
      log(
        '❌ Cannot create signing session: not authenticated',
        name: 'MwaAuthProvider',
      );
      return null;
    }

    LocalAssociationScenario? session;
    var handedOff = false;
    try {
      session = await LocalAssociationScenario.create();
      session.startActivityForResult(null).ignore();
      final client = await session.start();

      // Native Panta needs mainnet without changing the existing app's network
      // or persisted legacy authorization. A different cluster gets a fresh,
      // explicitly approved grant scoped to this signing session only.
      final crossCluster = cluster != null && cluster != _cluster;
      if (cluster != null &&
          cluster != NetworkConfig.mainnetBeta &&
          cluster != NetworkConfig.devnet) {
        return null;
      }
      final result =
          crossCluster
              ? await client.authorize(
                identityUri: Uri.parse(_identityUri),
                iconUri: Uri.parse(_iconPath),
                identityName: _appName,
                cluster: cluster,
              )
              : await client.reauthorize(
                identityUri: Uri.parse(_identityUri),
                iconUri: Uri.parse(_iconPath),
                identityName: _appName,
                authToken: held!.authToken,
              );

      if (result == null ||
          !_isCurrent(epoch) ||
          base58encode(result.publicKey) != held!.walletAddress) {
        log('⚠️ Signing session: reauth failed', name: 'MwaAuthProvider');
        return null;
      }

      // Never replace a legacy-cluster grant with a one-use mainnet grant.
      if (!crossCluster) {
        _authResult = MwaAuthResult(
          walletAddress: base58encode(result.publicKey),
          authToken: result.authToken,
          publicKeyBytes: result.publicKey,
          accountLabel: result.accountLabel,
          walletUriBase: result.walletUriBase,
          snsDomain: held.snsDomain,
        );
        await _persistAuthSession();
      }
      if (!_isCurrent(epoch)) {
        return null;
      }

      handedOff = true;
      return MwaSigningSession(session: session, client: client);
    } catch (e) {
      log('❌ Error creating signing session', name: 'MwaAuthProvider');
      return null;
    } finally {
      if (!handedOff) {
        try {
          await session?.close();
        } catch (_) {
          /* No wallet error payload. */
        }
      }
    }
  }

  /// Logout / deauthorize from wallet
  Future<void> logout() async {
    log('👋 Logging out', name: 'MwaAuthProvider');
    final held = _authResult;
    await forgetSession();

    try {
      if (held != null) {
        // Deauthorize with wallet
        final session = await LocalAssociationScenario.create();
        session.startActivityForResult(null).ignore();
        final client = await session.start();

        await client.deauthorize(authToken: held.authToken);
        await session.close();
      }
    } catch (e) {
      log('⚠️ Error during deauthorization', name: 'MwaAuthProvider');
      // Continue with logout even if deauth fails
    }
  }

  /// Forget this app's wallet credential without opening the wallet app. This
  /// does not move funds or revoke other apps' wallet authorizations.
  Future<void> forgetSession() {
    _authEpoch++;
    _authResult = null;
    _state = MwaAuthState.unauthenticated;
    _errorMessage = null;
    EfficientSyncService.clearAllCaches();
    notifyListeners();
    return _sessionStorage.clear();
  }

  /// Write and verify the secure record before removing any old plaintext copy.
  Future<void> _persistAuthSession() async {
    final held = _authResult;
    final epoch = _authEpoch;
    if (held == null || !_isCurrent(epoch)) return;
    await _sessionStorage.save(held, isCurrent: () => _isCurrent(epoch));
  }

  /// Restore securely; transparently migrate an intact old login exactly once.
  Future<bool> _restoreAuthSession() async {
    final epoch = _authEpoch;
    final saved = await _sessionStorage.restore(
      isCurrent: () => _isCurrent(epoch),
    );
    if (!_isCurrent(epoch)) return false;
    if (_existingProfileOnly && saved != null) {
      final existing = await _existingProfileForWallet(saved.walletAddress);
      if (!_isCurrent(epoch)) return false;
      if (existing != ExistingWalletProfile.found) {
        _authResult = null;
        return false;
      }
    }
    _authResult = saved;
    return saved != null;
  }

  Future<ExistingWalletProfile> _existingProfileForWallet(
    String walletAddress,
  ) async {
    try {
      _supabase ??= Supabase.instance.client;
      return await ExistingWalletProfileGuard(_supabase!).check(walletAddress);
    } catch (_) {
      return ExistingWalletProfile.unavailable;
    }
  }

  /// Sync user with Supabase database using wallet address as identifier
  Future<bool> _syncUserWithSupabase(
    String walletAddress, {
    String? snsDomain,
  }) async {
    if (_supabase == null) {
      log('⚠️ Supabase not initialized', name: 'MwaAuthProvider');
      return false;
    }

    try {
      log('🔄 Syncing user with Supabase', name: 'MwaAuthProvider');

      // Check if user exists first
      final existingUser =
          await _supabase!
              .from('users')
              .select('wallet_address')
              .eq('wallet_address', walletAddress)
              .maybeSingle();

      final isNewUser = existingUser == null;

      // Call stored procedure to sync user by wallet address
      await _supabase!.rpc(
        'sync_user_by_wallet',
        params: {'p_wallet_address': walletAddress, 'p_sns_domain': snsDomain},
      );

      log('✅ User synced successfully', name: 'MwaAuthProvider');

      // Track analytics (fire-and-forget)
      AnalyticsService.trackUserAuth(
        walletAddress: walletAddress,
        displayName: snsDomain,
        isNewUser: isNewUser,
      ).catchError((_) {
        log('⚠️ Analytics tracking failed', name: 'MwaAuthProvider');
      });

      return true;
    } on PostgrestException {
      log('⚠️ Supabase sync refused', name: 'MwaAuthProvider');
      // User might not exist yet - that's okay for first-time users
      // Try to create them
      return await _createUserInSupabase(walletAddress, snsDomain: snsDomain);
    } catch (_) {
      log('❌ Error syncing user', name: 'MwaAuthProvider');
      return false;
    }
  }

  /// Create a new user in Supabase if sync fails
  Future<bool> _createUserInSupabase(
    String walletAddress, {
    String? snsDomain,
  }) async {
    try {
      final userData = {
        'wallet_address': walletAddress,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add SNS domain if available
      if (snsDomain != null) {
        userData['sns_domain'] = snsDomain;
      }

      await _supabase!
          .from('users')
          .upsert(userData, onConflict: 'wallet_address');

      log('✅ User synced in Supabase', name: 'MwaAuthProvider');

      // Track new user signup (fire-and-forget)
      AnalyticsService.trackUserAuth(
        walletAddress: walletAddress,
        displayName: snsDomain,
        isNewUser: true,
      ).catchError((_) {
        log('⚠️ Analytics tracking failed', name: 'MwaAuthProvider');
      });

      return true;
    } catch (_) {
      log('❌ Error creating user', name: 'MwaAuthProvider');
      return false;
    }
  }

  /// Get user profile from Supabase
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (_authResult == null || _supabase == null) return null;

    try {
      final response =
          await _supabase!
              .from('users')
              .select()
              .eq('wallet_address', _authResult!.walletAddress)
              .single();

      return response;
    } catch (_) {
      log('Error fetching user profile', name: 'MwaAuthProvider');
      return null;
    }
  }

  /// Update user profile in Supabase
  Future<bool> updateUserProfile(Map<String, dynamic> updates) async {
    if (_authResult == null || _supabase == null) return false;

    try {
      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase!
          .from('users')
          .update(updates)
          .eq('wallet_address', _authResult!.walletAddress);

      return true;
    } catch (_) {
      log('Error updating user profile', name: 'MwaAuthProvider');
      return false;
    }
  }

  /// Clear user data (for logout/cleanup)
  Future<void> clearUserData() async {
    await logout();
  }
}

/// Signing session wrapper - holds both session and client
/// Caller is responsible for calling close() when done
class MwaSigningSession {
  final LocalAssociationScenario session;
  final MobileWalletAdapterClient client;

  MwaSigningSession({required this.session, required this.client});

  /// Sign and send transactions through MWA
  Future<SignAndSendTransactionsResult> signAndSendTransactions({
    required List<Uint8List> transactions,
    int? minContextSlot,
  }) async {
    return await client.signAndSendTransactions(
      transactions: transactions,
      minContextSlot: minContextSlot,
    );
  }

  /// Sign transactions without sending
  Future<SignPayloadsResult> signTransactions({
    required List<Uint8List> transactions,
  }) async {
    return await client.signTransactions(transactions: transactions);
  }

  /// Sign messages
  Future<SignMessagesResult> signMessages({
    required List<Uint8List> messages,
    required List<Uint8List> addresses,
  }) async {
    return await client.signMessages(messages: messages, addresses: addresses);
  }

  /// Close the signing session
  Future<void> close() async {
    await session.close();
  }
}
