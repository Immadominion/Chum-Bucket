import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';

abstract interface class FriendConnectionService {
  String? get currentWallet;
  Future<String?> resolveDomain(String domain);
  Future<ArenaCreatePendingTargetResult> addHandle(String handle);
  Future<bool> addWallet({
    required String owner,
    required String name,
    required String address,
  });
}

/// Reuses the shipped friend graph and the existing wallet-signed X proof.
class ExistingFriendConnectionService implements FriendConnectionService {
  ExistingFriendConnectionService(this.auth, this.arena);
  final MwaAuthProvider auth;
  final ArenaProvider Function() arena;
  @override
  String? get currentWallet => auth.isAuthenticated ? auth.walletAddress : null;
  @override
  Future<String?> resolveDomain(String domain) =>
      AddressNameResolver.resolveAddress(domain);
  @override
  Future<ArenaCreatePendingTargetResult> addHandle(String handle) =>
      arena().addPendingTargetByHandle(authProvider: auth, xHandle: handle);
  @override
  Future<bool> addWallet({
    required String owner,
    required String name,
    required String address,
  }) => UnifiedDatabaseService.addFriend(
    userPrivyId: owner,
    friendName: name,
    friendWalletAddress: address,
  );
}
