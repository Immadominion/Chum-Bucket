/// The signed-in person's own account, through the calls BFF (`account.*`).
///
/// Every request carries the Supabase session as `Authorization: Bearer`, and
/// the server takes the person from that session — never from a wallet or an
/// id this client names. So editing works the same for a wallet sign-in and a
/// Google/X sign-in, and nobody can edit anybody else's profile.
///
/// Errors are the calls slice's own [CallsException]s: a signed-out session is
/// [CallsSignedOutException], a refusal is [CallsRejectedException] whose
/// message is written for a person to read.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/profile/data/avatar_catalog.dart';

/// The person's own profile, as `account.me` returns it.
@immutable
class AccountProfile {
  const AccountProfile({
    required this.userId,
    this.handle,
    this.displayName,
    this.bio,
    this.avatarId,
    this.walletAddress,
  });

  final String userId;
  final String? handle;
  final String? displayName;
  final String? bio;

  /// One of the five bundled avatars, or null when none is chosen.
  final int? avatarId;

  /// The person's OWN wallet. Only ever returned to its owner.
  final String? walletAddress;

  /// The asset to render, falling back to the default picture.
  String get avatarAsset =>
      avatarAssetFor(avatarId) ?? avatarAssetFor(kDefaultAvatarId)!;

  /// The same shape [fromJson] reads, for the copy kept on this phone.
  Map<String, Object?> toJson() => {
    'userId': userId,
    'handle': handle,
    'displayName': displayName,
    'bio': bio,
    'avatarId': avatarId,
    'walletAddress': walletAddress,
  };

  static AccountProfile fromJson(Object? raw) {
    final outer = raw is Map ? raw : const {};
    final json = outer['profile'] is Map ? outer['profile'] as Map : outer;
    final userId = json['userId'];
    if (userId is! String || userId.isEmpty) {
      throw const CallsFailure('The server sent a profile with no account.');
    }
    final avatar = json['avatarId'];
    return AccountProfile(
      userId: userId,
      handle: json['handle'] as String?,
      displayName: json['displayName'] as String?,
      bio: json['bio'] as String?,
      avatarId: isAvatarId(avatar) ? avatar as int : null,
      walletAddress: json['walletAddress'] as String?,
    );
  }
}

abstract interface class AccountApi {
  Future<AccountProfile> me();

  /// Any subset; at least one. An empty [bio] clears it.
  Future<AccountProfile> updateProfile({
    String? displayName,
    String? bio,
    int? avatarId,
  });

  /// Returns whether the server will actually send pushes (it says so
  /// honestly when it has no Firebase credentials).
  Future<bool> registerPushToken({
    required String token,
    required String platform,
  });

  Future<void> unregisterPushToken(String token);

  /// Whether this server delivers pushes at all (`account.pushStatus`): a
  /// token store, a configured sender and the scheduler that sends them.
  /// The app asks for notification permission only when it does.
  Future<bool> pushStatus();
}

class BffAccountApi implements AccountApi {
  BffAccountApi({
    CallsBffTransport? transport,
    CallsBffAuthTokenProvider? authToken,
  }) : _transport = transport ?? CallsBffTransport(authToken: authToken);

  final CallsBffTransport _transport;

  static const String mePath = 'account.me';
  static const String updateProfilePath = 'account.updateProfile';
  static const String registerPushTokenPath = 'account.registerPushToken';
  static const String unregisterPushTokenPath = 'account.unregisterPushToken';
  static const String pushStatusPath = 'account.pushStatus';

  @override
  Future<AccountProfile> me() async =>
      AccountProfile.fromJson(await _transport.query(mePath));

  @override
  Future<AccountProfile> updateProfile({
    String? displayName,
    String? bio,
    int? avatarId,
  }) async {
    final input = <String, dynamic>{
      if (displayName != null) 'displayName': displayName,
      if (bio != null) 'bio': bio,
      if (avatarId != null) 'avatarId': avatarId,
    };
    if (input.isEmpty) {
      throw const CallsRejectedException("There's nothing to save.");
    }
    return AccountProfile.fromJson(
      await _transport.mutate(updateProfilePath, input),
    );
  }

  @override
  Future<bool> registerPushToken({
    required String token,
    required String platform,
  }) async {
    final raw = await _transport.mutate(registerPushTokenPath, {
      'token': token,
      'platform': platform,
    });
    return raw is Map && raw['pushEnabled'] == true;
  }

  @override
  Future<void> unregisterPushToken(String token) async {
    await _transport.mutate(unregisterPushTokenPath, {'token': token});
  }

  @override
  Future<bool> pushStatus() async {
    final raw = await _transport.query(pushStatusPath);
    return raw is Map && raw['pushEnabled'] == true;
  }
}

/// The account API for this widget tree: an injected one (tests, previews),
/// else one bound to the current Supabase session, else null when nobody is
/// signed in to a Chumbucket account yet.
AccountApi? accountApiOf(BuildContext context) {
  final injected = Provider.of<AccountApi?>(context, listen: false);
  if (injected != null) return injected;
  final session = Provider.of<ChumbucketSession?>(context, listen: false);
  if (session == null || !session.isReady) return null;
  return BffAccountApi(authToken: session.bffAuthToken);
}
