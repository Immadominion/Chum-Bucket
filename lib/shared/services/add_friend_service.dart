import 'package:share_plus/share_plus.dart';

import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/person_finder.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

/// What Add a friend needs, and nothing more.
///
/// Adding a friend is following a real Chumbucket person: look them up
/// (`people.find`), show who they are, then follow (`people.follow`). All of
/// it is keyed by the signed-in Chumbucket session, so it works the same for
/// wallet, Google and X accounts — and nothing ever asks a wallet to sign.
/// Someone who is not on Chumbucket yet is invited with a link; nothing is
/// saved for them.
abstract interface class AddFriendService {
  /// Whether a Chumbucket account is signed in.
  bool get isSignedIn;

  /// Who they are: matches, or "not on Chumbucket yet".
  Future<PersonLookup> find(String query);

  /// Follow or unfollow; the server's confirmed state.
  Future<bool> setFollowing(String personId, bool following);

  /// The wallet behind a name such as `you.skr`, or null.
  Future<String?> resolveName(String name);

  /// The link an invitation carries.
  String get inviteLink;

  /// Opens the system share sheet with [text].
  Future<void> share(String text);
}

/// The app's own: the calls session and BFF, the AllDomains resolver and the
/// system share sheet.
class CallsAddFriendService implements AddFriendService {
  CallsAddFriendService(this.calls, {String? inviteLink})
    : inviteLink =
          inviteLink ?? normalizeCallsBffBaseUrl(resolveCallsLinkHost());

  /// Null when this build has no calls slice; every lookup then says so.
  final CallsProvider? calls;

  @override
  final String inviteLink;

  @override
  bool get isSignedIn => calls?.isSignedIn == true;

  @override
  Future<PersonLookup> find(String query) {
    final provider = calls;
    if (provider == null) throw const CallsSignedOutException();
    return provider.findPerson(query);
  }

  @override
  Future<bool> setFollowing(String personId, bool following) {
    final provider = calls;
    if (provider == null) throw const CallsSignedOutException();
    return provider.setFollowingById(personId, following);
  }

  @override
  Future<String?> resolveName(String name) =>
      AddressNameResolver.resolveAddress(name);

  @override
  Future<void> share(String text) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Join me on Chumbucket'),
    );
  }
}
