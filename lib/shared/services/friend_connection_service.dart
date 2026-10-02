import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

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
///
/// Adding by wallet goes through the BFF (`account.addWalletFriend`), keyed by
/// the signed-in session: the server finds the account at that wallet or
/// creates an EMPTY placeholder, and the name typed here is stored as the
/// adder's own label for the friend — never written onto the friend's profile,
/// which is what let anyone pre-label a stranger's wallet (prod readiness M1).
class ExistingFriendConnectionService implements FriendConnectionService {
  ExistingFriendConnectionService(this.auth, this.arena, {this.account});
  final MwaAuthProvider auth;
  final ArenaProvider Function() arena;

  /// The signed-in account's API, or null when nobody is signed in to one.
  final AccountApi? Function()? account;
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
  }) async {
    final api = account?.call();
    if (api == null) throw const CallsSignedOutException();
    await api.addWalletFriend(walletAddress: address, nickname: name);
    return true;
  }
}
