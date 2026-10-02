/// Trust & safety, legal and account calls on the calls BFF.
///
/// Uses the same [CallsBffTransport] (and the same session token) as the call
/// slice, so it throws only the four [CallsException] classes every call
/// screen already renders. No method takes a user id or wallet: the BFF
/// derives who is asking from the session.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';

abstract class TrustRepository {
  Future<ReportReceipt> report({
    required ReportSubject subject,
    required ReportReason reason,
    String? callId,
    String? personRef,
    String? details,
  });

  Future<void> setBlocked(String personRef, {required bool blocked});
  Future<void> setMuted(String personRef, {required bool muted});
  Future<RelationLists> lists();

  Future<LegalStatus> legalStatus();
  Future<void> acceptFundedTrading(String termsVersion);

  /// Deletes the signed-in account. Idempotent on the server.
  Future<AccountDeletion> deleteAccount();

  /// The caller's own data, as the BFF's JSON export.
  Future<Map<String, dynamic>> exportData();

  /// The repository for this context: one provided above it (tests), or the
  /// BFF repository on the current session's token.
  static TrustRepository of(BuildContext context) {
    final provided = context.read<TrustRepository?>();
    if (provided != null) return provided;
    final session = context.read<ChumbucketSession?>();
    return BffTrustRepository(authToken: session?.bffAuthToken);
  }
}

class BffTrustRepository implements TrustRepository {
  BffTrustRepository({
    CallsBffAuthTokenProvider? authToken,
    CallsBffTransport? transport,
  }) : _transport = transport ?? CallsBffTransport(authToken: authToken);

  final CallsBffTransport _transport;

  Map<String, dynamic> _map(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw const CallsFailure('The server sent something we could not read.');
  }

  @override
  Future<ReportReceipt> report({
    required ReportSubject subject,
    required ReportReason reason,
    String? callId,
    String? personRef,
    String? details,
  }) async {
    final trimmed = details?.trim();
    return ReportReceipt.fromJson(
      _map(
        await _transport.mutate('trust.report', {
          'subject': subject.wire,
          'reason': reason.wire,
          if (callId != null) 'callId': callId,
          if (personRef != null) 'personRef': personRef,
          if (trimmed != null && trimmed.isNotEmpty) 'details': trimmed,
        }),
      ),
    );
  }

  @override
  Future<void> setBlocked(String personRef, {required bool blocked}) =>
      _transport.mutate(blocked ? 'trust.block' : 'trust.unblock', {
        'personRef': personRef,
      });

  @override
  Future<void> setMuted(String personRef, {required bool muted}) => _transport
      .mutate(muted ? 'trust.mute' : 'trust.unmute', {'personRef': personRef});

  @override
  Future<RelationLists> lists() async =>
      RelationLists.fromJson(_map(await _transport.query('trust.lists')));

  @override
  Future<LegalStatus> legalStatus() async =>
      LegalStatus.fromJson(_map(await _transport.query('trust.legalStatus')));

  @override
  Future<void> acceptFundedTrading(String termsVersion) =>
      _transport.mutate('trust.acceptFundedTrading', {
        'termsVersion': termsVersion,
        'over18': true,
        'eligibleJurisdiction': true,
        'acceptsVenueTerms': true,
      });

  @override
  Future<AccountDeletion> deleteAccount() async => AccountDeletion.fromJson(
    _map(await _transport.mutate('auth.deleteAccount', {'confirm': 'DELETE'})),
  );

  @override
  Future<Map<String, dynamic>> exportData() async =>
      _map(await _transport.mutate('auth.exportData', const {}));
}
