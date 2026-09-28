import 'dart:async';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/existing_account_proof.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

const claimAddress = '11111111111111111111111111111111';

Map<String, dynamic> claimProof({DateTime? now}) {
  final instant = (now ?? DateTime.now()).toUtc();
  // Server serialization uses millisecond precision, never microseconds.
  final issued = DateTime.fromMillisecondsSinceEpoch(
    instant.millisecondsSinceEpoch,
    isUtc: true,
  );
  final expires = issued.add(const Duration(minutes: 5));
  return {
    'domain': accountClaimDomain,
    'uri': accountClaimUri,
    'network': 'devnet',
    'purpose': 'claim_account',
    'proofVersion': 1,
    'issuedAt': issued.toIso8601String(),
    'expiresAt': expires.toIso8601String(),
    'message': [
      '$accountClaimDomain wants you to sign in with your Solana account:',
      claimAddress,
      '',
      accountClaimStatement,
      '',
      'URI: $accountClaimUri',
      'Version: 1',
      'Chain ID: solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1',
      'Nonce: ${'a' * 64}',
      'Issued At: ${issued.toIso8601String()}',
      'Expiration Time: ${expires.toIso8601String()}',
      'Resources:',
      '- chumbucket:purpose:claim_account',
    ].join('\n'),
  };
}

class ClaimWalletFake implements ExistingAccountWallet {
  @override
  String address = claimAddress;
  @override
  String network = 'devnet';
  @override
  bool isCurrent = true;
  String? userId = kCanonicalUserId;
  final signed = <String>[];
  Completer<String>? signature;
  Object? signingError;
  @override
  Future<String?> expectedUserId() async => userId;
  @override
  Future<String> signClaim(String message) async {
    signed.add(message);
    if (signingError case final error?) throw error;
    return signature?.future ?? 'synthetic-signature';
  }
}

class ClaimRig {
  ClaimRig({Duration oauthTimeout = const Duration(seconds: 2)}) {
    auth.deliverOnSignIn = snapshot();
    client = MockClient((request) async {
      redirectPolicies.add(request.followRedirects);
      final recorded = RecordedRequest(
        method: request.method,
        url: request.url,
        headers: request.headers,
        body: request.body,
      );
      requests.add(recorded);
      final path = recorded.procedurePath;
      await holds[path]?.future;
      if (failures[path] case final code?) {
        return errorResponse(
          code: 'PRECONDITION_FAILED',
          httpStatus: 412,
          message: code,
        );
      }
      switch (path) {
        case 'auth.identityStatus':
          return okResponse(capability);
        case 'auth.whoami':
          if (!claimed && beforeUser == null) {
            return errorResponse(
              code: 'FORBIDDEN',
              httpStatus: 403,
              message: 'AUTH_USER_UNLINKED',
            );
          }
          return okResponse({
            'userId': claimed ? confirmedUser : beforeUser,
            'authUserId': confirmedSubject,
          });
        case 'auth.requestExistingAccountProof':
          return okResponse(proof);
        case 'auth.claimExistingAccount':
          claimed = true;
          return okResponse({
            'userId': claimedUser,
            'authUserId': claimedSubject,
            'outcome': outcome,
          });
        default:
          throw StateError('Unexpected procedure (profile creation forbidden)');
      }
    });
    bff = SessionBffClient(baseUrl: kSessionBase, httpClient: client);
    session = ChumbucketSession(
      auth: auth,
      bff: bff,
      oauthTimeout: oauthTimeout,
    );
  }
  final auth = FakeSupabaseAuthPort();
  final wallet = ClaimWalletFake();
  final proof = claimProof();
  final requests = <RecordedRequest>[];
  final redirectPolicies = <bool>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, String>{};
  final capability = <String, Object>{
    'enabled': true,
    'existingAccountClaimsEnabled': true,
    'network': 'devnet',
    'proofVersion': 1,
    'allowedDomains': [accountClaimDomain],
    'allowedUris': [accountClaimUri],
  };
  String? beforeUser;
  String claimedUser = kCanonicalUserId;
  String confirmedUser = kCanonicalUserId;
  String claimedSubject = kAuthUserId;
  String confirmedSubject = kAuthUserId;
  String outcome = 'claimed';
  bool claimed = false;
  late final http.Client client;
  late final SessionBffClient bff;
  late final ChumbucketSession session;
  bool disposed = false;
  Future<bool> link() => session.linkExistingAccount(wallet);
  Future<void> close() async {
    if (!disposed) session.dispose();
    client.close();
    await auth.close();
  }

  Future<void> reach(String path) async {
    for (var i = 0; i < 100; i++) {
      if (requests.any((r) => r.procedurePath == path)) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Expected phase not reached: $path');
  }

  Future<void> reachWallet() async {
    for (var i = 0; i < 100; i++) {
      if (wallet.signed.isNotEmpty) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Expected wallet phase not reached');
  }
}
