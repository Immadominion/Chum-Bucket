// A TrustRepository with no network, for widget tests.
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTrust implements TrustRepository {
  final reports = <Map<String, Object?>>[];
  final blocked = <String>{};
  final muted = <String>{};
  int deletes = 0;
  int accepts = 0;
  bool accepted = false;
  CallsException? deleteError;

  @override
  Future<ReportReceipt> report({
    required ReportSubject subject,
    required ReportReason reason,
    String? callId,
    String? personRef,
    String? details,
  }) async {
    reports.add({
      'subject': subject,
      'reason': reason,
      'callId': callId,
      'personRef': personRef,
      'details': details,
    });
    return ReportReceipt(
      reportId: 'r${reports.length}',
      alreadyReported: false,
    );
  }

  @override
  Future<void> setBlocked(String personRef, {required bool blocked}) async =>
      blocked ? this.blocked.add(personRef) : this.blocked.remove(personRef);

  @override
  Future<void> setMuted(String personRef, {required bool muted}) async =>
      muted ? this.muted.add(personRef) : this.muted.remove(personRef);

  TrustPerson _p(String id) =>
      TrustPerson(userId: id, handle: id, displayName: id.toUpperCase());

  @override
  Future<RelationLists> lists() async => RelationLists(
    blocked: blocked.map(_p).toList(),
    muted: muted.map(_p).toList(),
  );

  @override
  Future<LegalStatus> legalStatus() async => LegalStatus(
    termsVersion: '2026-10-02-draft',
    termsUrl: 'https://chumbucket.fun/terms',
    privacyUrl: 'https://chumbucket.fun/privacy',
    deletionUrl: 'https://chumbucket.fun/delete-account',
    venueTermsUrl: 'https://panta.market',
    fundedTradingAccepted: accepted,
  );

  @override
  Future<void> acceptFundedTrading(String termsVersion) async {
    expect(termsVersion, '2026-10-02-draft');
    accepts++;
    accepted = true;
  }

  @override
  Future<AccountDeletion> deleteAccount() async {
    deletes++;
    final error = deleteError;
    if (error != null) throw error;
    return const AccountDeletion(alreadyDeleted: false);
  }

  @override
  Future<Map<String, dynamic>> exportData() async => {'format': 'test'};
}
