/// Wire shapes for the BFF's `trust.*`, `auth.deleteAccount` and
/// `auth.exportData` procedures (src/api/trust.ts in the API repo).
library;

/// Why someone is reporting. The wire values match the BFF enum exactly.
enum ReportReason {
  spam('spam', 'Spam', 'Repetitive, misleading or promotional'),
  scam('scam', 'Scam or fraud', 'Phishing, fake giveaways, wallet drainers'),
  harassment(
    'harassment',
    'Harassment',
    'Targeting, threatening or bullying someone',
  ),
  hate('hate', 'Hate', 'Attacks people for who they are'),
  sexual('sexual', 'Sexual content', 'Explicit or sexual material'),
  violence('violence', 'Violence', 'Threats or glorifying violence'),
  selfHarm('self_harm', 'Self-harm', 'Encourages self-harm or suicide'),
  impersonation(
    'impersonation',
    'Impersonation',
    'Pretending to be someone else',
  ),
  illegal('illegal', 'Illegal activity', 'Breaks the law'),
  other('other', 'Something else', 'Tell us what is wrong');

  const ReportReason(this.wire, this.label, this.hint);
  final String wire;
  final String label;
  final String hint;
}

/// What is being reported.
enum ReportSubject {
  call('call', 'this call'),
  thesis('thesis', 'this thesis'),
  person('person', 'this person');

  const ReportSubject(this.wire, this.noun);
  final String wire;
  final String noun;
}

/// The outcome of `trust.report`.
class ReportReceipt {
  const ReportReceipt({required this.reportId, required this.alreadyReported});
  final String reportId;
  final bool alreadyReported;

  factory ReportReceipt.fromJson(Map<String, dynamic> json) => ReportReceipt(
    reportId: json['reportId'] as String? ?? '',
    alreadyReported: json['status'] == 'already_reported',
  );
}

/// A person as the block and mute lists name them.
class TrustPerson {
  const TrustPerson({
    required this.userId,
    required this.handle,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String handle;
  final String displayName;
  final String? avatarUrl;

  factory TrustPerson.fromJson(Map<String, dynamic> json) => TrustPerson(
    userId: json['userId'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
  );
}

class RelationLists {
  const RelationLists({required this.blocked, required this.muted});
  final List<TrustPerson> blocked;
  final List<TrustPerson> muted;

  static const empty = RelationLists(blocked: [], muted: []);

  factory RelationLists.fromJson(Map<String, dynamic> json) => RelationLists(
    blocked: _people(json['blocked']),
    muted: _people(json['muted']),
  );

  static List<TrustPerson> _people(Object? raw) =>
      raw is List
          ? raw
              .whereType<Map>()
              .map((e) => TrustPerson.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [];
}

/// Where the legal pages live and whether the funded-trading attestation is
/// on record for the current terms version.
class LegalStatus {
  const LegalStatus({
    required this.termsVersion,
    required this.termsUrl,
    required this.privacyUrl,
    required this.deletionUrl,
    required this.venueTermsUrl,
    required this.fundedTradingAccepted,
  });

  final String termsVersion;
  final String termsUrl;
  final String privacyUrl;
  final String deletionUrl;
  final String venueTermsUrl;
  final bool fundedTradingAccepted;

  factory LegalStatus.fromJson(Map<String, dynamic> json) {
    final funded = json['fundedTrading'];
    return LegalStatus(
      termsVersion: json['termsVersion'] as String? ?? '',
      termsUrl: json['termsUrl'] as String? ?? '',
      privacyUrl: json['privacyUrl'] as String? ?? '',
      deletionUrl: json['deletionUrl'] as String? ?? '',
      venueTermsUrl: json['venueTermsUrl'] as String? ?? '',
      fundedTradingAccepted: funded is Map && funded['accepted'] == true,
    );
  }
}

/// `auth.deleteAccount` answered: the account is gone.
class AccountDeletion {
  const AccountDeletion({required this.alreadyDeleted});
  final bool alreadyDeleted;

  factory AccountDeletion.fromJson(Map<String, dynamic> json) =>
      AccountDeletion(alreadyDeleted: json['alreadyDeleted'] == true);
}
