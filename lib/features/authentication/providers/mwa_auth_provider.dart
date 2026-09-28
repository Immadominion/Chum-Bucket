import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/analytics_service.dart';
import 'package:chumbucket/core/config/network_config.dart';

/// Authentication state for MWA-based auth
enum MwaAuthState { initial, loading, authenticated, unauthenticated, error }

/// Result of MWA authorization containing wallet info
class MwaAuthResult {
  final String walletAddress;
  final String authToken;
  final String? accountLabel;
  final Uri? walletUriBase;
  final Uint8List publicKeyBytes;
  final String? snsDomain; // SNS domain (.sol, .skr, etc.) if available

  const MwaAuthResult({
    required this.walletAddress,
    required this.authToken,
    required this.publicKeyBytes,
    this.accountLabel,
    this.walletUriBase,
    this.snsDomain,
  });

  /// Returns true if user has a Seeker wallet domain (.skr)
  bool get hasSeekerDomain =>
      snsDomain?.toLowerCase().endsWith('.skr') ?? false;

  /// Returns true if user has any SNS domain
  bool get hasSnsDomain => snsDomain != null && snsDomain!.isNotEmpty;

  /// Returns display name - domain if available, otherwise shortened address
  String get displayName {
    if (hasSnsDomain) return snsDomain!;
    if (walletAddress.length > 12) {
      return '${walletAddress.substring(0, 6)}...${walletAddress.substring(walletAddress.length - 4)}';
    }
    return walletAddress;
  }

  Map<String, dynamic> toJson() => {
    'walletAddress': walletAddress,
    'authToken': authToken,
    'accountLabel': accountLabel,
    'walletUriBase': walletUriBase?.toString(),
    'publicKeyBytes': base64Encode(publicKeyBytes),
    'snsDomain': snsDomain,
  };

  factory MwaAuthResult.fromJson(Map<String, dynamic> json) {
    return MwaAuthResult(
      walletAddress: json['walletAddress'] as String,
      authToken: json['authToken'] as String,
      accountLabel: json['accountLabel'] as String?,
      walletUriBase:
          json['walletUriBase'] != null
              ? Uri.tryParse(json['walletUriBase'] as String)
              : null,
      publicKeyBytes: base64Decode(json['publicKeyBytes'] as String),
      snsDomain: json['snsDomain'] as String?,
    );
  }

  /// Create a copy with an updated domain
  MwaAuthResult copyWithDomain(String? domain) {
    return MwaAuthResult(
      walletAddress: walletAddress,
      authToken: authToken,
      publicKeyBytes: publicKeyBytes,
      accountLabel: accountLabel,
      walletUriBase: walletUriBase,
      snsDomain: domain,
    );
  }
}

/// MWA-based authentication provider for Solana Mobile compatibility
/// Replaces Privy authentication with native Mobile Wallet Adapter
class MwaAuthProvider extends ChangeNotifier {
  int _authEpoch = 0;
  bool _disposed = false;
  Future<void> _storageWrites = Future.value();
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

  // Persistence keys
  static const String _authResultKey = 'mwa_auth_result';
  static const String _isLoggedInKey = 'mwa_is_logged_in';

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

    // Otherwise check persisted state (in case initialize() hasn't run yet)
    final prefs = await SharedPreferences.getInstance();
    return _isCurrent(epoch) && (prefs.getBool(_isLoggedInKey) ?? false);
  }

  /// Initialize the auth provider
  Future<void> initialize() async {
    final epoch = _authEpoch;
    log('🔐 Initializing MWA Auth Provider', name: 'MwaAuthProvider');

    try {
      _supabase = Supabase.instance.client;

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
      final session = await LocalAssociationScenario.create();

      // Launch wallet app for authorization
      // This triggers the wallet to open for user approval
      session.startActivityForResult(null).ignore();

      // Start the session and get client
      final client = await session.start();

      // Request authorization from the wallet
      final result = await client.authorize(
        identityUri: Uri.parse(_identityUri),
        iconUri: Uri.parse(_iconPath),
        identityName: _appName,
        cluster: _cluster,
      );

      // Close the session
      await session.close();

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
          log('🏷️ Found SNS domain: $snsDomain', name: 'MwaAuthProvider');
        }
      } catch (e) {
        log(
          '⚠️ Domain lookup failed (non-critical): $e',
          name: 'MwaAuthProvider',
        );
      }

      if (!_isCurrent(epoch)) return false;
      _authResult = MwaAuthResult(
        walletAddress: walletAddress,
        authToken: result.authToken,
        publicKeyBytes: result.publicKey,
        accountLabel: result.accountLabel,
        walletUriBase: result.walletUriBase,
        snsDomain: snsDomain,
      );

      log('✅ Authorization successful', name: 'MwaAuthProvider');
      log('👛 Wallet: $walletAddress', name: 'MwaAuthProvider');
      log('🏷️ Account Label: ${result.accountLabel}', name: 'MwaAuthProvider');
      if (snsDomain != null) {
        log('🌐 SNS Domain: $snsDomain', name: 'MwaAuthProvider');
      }

      // Persist auth result
      await _persistAuthSession();
      if (!_isCurrent(epoch)) return false;

      // Sync user with Supabase (include domain if available)
      await _syncUserWithSupabase(walletAddress, snsDomain: snsDomain);
      if (!_isCurrent(epoch)) return false;

      // Register FCM token for push notifications (fire-and-forget)
      FcmTokenService.registerToken(
        walletAddress: walletAddress,
        displayName: snsDomain ?? result.accountLabel,
      ).catchError((e) {
        log('⚠️ Failed to register notifications', name: 'MwaAuthProvider');
      });

      // Assign profile picture
      final profileProvider = ProfileProvider();
      await profileProvider.getUserPfp(walletAddress);
      if (!_isCurrent(epoch)) return false;

      _state = MwaAuthState.authenticated;
      notifyListeners();
      return true;
    } on PlatformException {
      if (!_isCurrent(epoch)) return false;
      log('❌ Platform error during authorization', name: 'MwaAuthProvider');
      _errorMessage = 'Wallet connection failed. Please try again.';
      _state = MwaAuthState.error;
      notifyListeners();
      return false;
    } catch (e) {
      if (!_isCurrent(epoch)) return false;
      log('❌ Error during authorization', name: 'MwaAuthProvider');
      _errorMessage = 'Authorization failed. Please try again.';
      _state = MwaAuthState.error;
      notifyListeners();
      return false;
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
  Future<MwaSigningSession?> createSigningSession() async {
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

      // Reauthorize to ensure session is valid
      final result = await client.reauthorize(
        identityUri: Uri.parse(_identityUri),
        iconUri: Uri.parse(_iconPath),
        identityName: _appName,
        authToken: held!.authToken,
      );

      if (result == null ||
          !_isCurrent(epoch) ||
          base58encode(result.publicKey) != held.walletAddress) {
        log('⚠️ Signing session: reauth failed', name: 'MwaAuthProvider');
        return null;
      }

      // Update stored auth token
      _authResult = MwaAuthResult(
        walletAddress: base58encode(result.publicKey),
        authToken: result.authToken,
        publicKeyBytes: result.publicKey,
        accountLabel: result.accountLabel,
        walletUriBase: result.walletUriBase,
        snsDomain: held.snsDomain,
      );
      await _persistAuthSession();
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
    return _writeStorage(() async {
      final prefs = await SharedPreferences.getInstance();
      final credential = await prefs.remove(_authResultKey);
      final marker = await prefs.remove(_isLoggedInKey);
      if (!credential || !marker) {
        throw StateError('Wallet session removal failed');
      }
    });
  }

  Future<void> _writeStorage(Future<void> Function() operation) {
    final pending = _storageWrites.then((_) => operation());
    _storageWrites = pending.catchError((Object _) {});
    return pending;
  }

  /// Persist auth session to SharedPreferences
  Future<void> _persistAuthSession() async {
    final held = _authResult;
    final epoch = _authEpoch;
    if (held == null || !_isCurrent(epoch)) return;
    await _writeStorage(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrent(epoch)) return;
      if (!await prefs.setString(_authResultKey, jsonEncode(held.toJson())) ||
          !await prefs.setBool(_isLoggedInKey, true)) {
        throw StateError('Wallet session storage failed');
      }
    });
  }

  /// Restore auth session from SharedPreferences
  Future<bool> _restoreAuthSession() async {
    final epoch = _authEpoch;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrent(epoch)) return false;
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;

    if (!isLoggedIn) return false;

    final authJson = prefs.getString(_authResultKey);
    if (authJson == null) return false;

    try {
      final json = jsonDecode(authJson) as Map<String, dynamic>;
      _authResult = MwaAuthResult.fromJson(json);
      return true;
    } catch (e) {
      log('Error restoring auth session', name: 'MwaAuthProvider');
      return false;
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
      log(
        '🔄 Syncing user with Supabase: $walletAddress${snsDomain != null ? ' ($snsDomain)' : ''}',
        name: 'MwaAuthProvider',
      );

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
      ).catchError((e) {
        log('⚠️ Analytics tracking failed: $e', name: 'MwaAuthProvider');
      });

      return true;
    } on PostgrestException catch (e) {
      log('⚠️ Supabase error: ${e.message}', name: 'MwaAuthProvider');
      // User might not exist yet - that's okay for first-time users
      // Try to create them
      return await _createUserInSupabase(walletAddress, snsDomain: snsDomain);
    } catch (e) {
      log('❌ Error syncing user: $e', name: 'MwaAuthProvider');
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

      log(
        '✅ Created new user in Supabase${snsDomain != null ? ' with domain $snsDomain' : ''}',
        name: 'MwaAuthProvider',
      );

      // Track new user signup (fire-and-forget)
      AnalyticsService.trackUserAuth(
        walletAddress: walletAddress,
        displayName: snsDomain,
        isNewUser: true,
      ).catchError((e) {
        log('⚠️ Analytics tracking failed: $e', name: 'MwaAuthProvider');
      });

      return true;
    } catch (e) {
      log('❌ Error creating user: $e', name: 'MwaAuthProvider');
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
    } catch (e) {
      log('Error fetching user profile: $e', name: 'MwaAuthProvider');
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
    } catch (e) {
      log('Error updating user profile: $e', name: 'MwaAuthProvider');
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
