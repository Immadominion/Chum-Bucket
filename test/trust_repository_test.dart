// The trust, legal and account calls against the BFF's wire format
// (src/api/trust.ts): POST bodies carry no user id or wallet — the session
// does — and every error lands on one of the four CallsException classes.
import 'dart:convert';

import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String ok(Object? data) => jsonEncode({
  'result': {
    'data': {'json': data},
  },
});

String trpcError(String code, int status, String message) => jsonEncode({
  'error': {
    'json': {
      'message': message,
      'data': {'code': code, 'httpStatus': status},
    },
  },
});

void main() {
  late List<http.Request> requests;

  BffTrustRepository repo(http.Response Function(http.Request) handler) {
    requests = [];
    return BffTrustRepository(
      transport: CallsBffTransport(
        baseUrl: 'https://bff.test',
        authToken: () => 'session-token',
        verbose: false,
        httpClient: MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
      ),
    );
  }

  Map<String, dynamic> inputOf(http.Request r) =>
      (jsonDecode(r.method == 'GET' ? r.url.queryParameters['input']! : r.body)
              as Map<String, dynamic>)['json']
          as Map<String, dynamic>;

  test('report names the subject and reason, never the reporter', () async {
    final r = repo(
      (_) =>
          http.Response(ok({'reportId': 'rep-1', 'status': 'received'}), 200),
    );
    final receipt = await r.report(
      subject: ReportSubject.thesis,
      reason: ReportReason.selfHarm,
      callId: 'call-1',
      details: '  context  ',
    );
    expect(receipt.reportId, 'rep-1');
    expect(receipt.alreadyReported, isFalse);
    final req = requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/trust.report');
    expect(req.headers['authorization'], 'Bearer session-token');
    expect(inputOf(req), {
      'subject': 'thesis',
      'reason': 'self_harm',
      'callId': 'call-1',
      'details': 'context',
    });
  });

  test('a repeat report reads as already reported', () async {
    final r = repo(
      (_) => http.Response(
        ok({'reportId': 'rep-1', 'status': 'already_reported'}),
        200,
      ),
    );
    final receipt = await r.report(
      subject: ReportSubject.person,
      reason: ReportReason.spam,
      personRef: 'u-bob',
    );
    expect(receipt.alreadyReported, isTrue);
    expect(inputOf(requests.single), {
      'subject': 'person',
      'reason': 'spam',
      'personRef': 'u-bob',
    });
  });

  test('block, unblock, mute and unmute hit their own paths', () async {
    final r = repo((_) => http.Response(ok({'personId': 'u-bob'}), 200));
    await r.setBlocked('u-bob', blocked: true);
    await r.setBlocked('u-bob', blocked: false);
    await r.setMuted('u-bob', muted: true);
    await r.setMuted('u-bob', muted: false);
    expect(requests.map((q) => q.url.path), [
      '/trust.block',
      '/trust.unblock',
      '/trust.mute',
      '/trust.unmute',
    ]);
    for (final q in requests) {
      expect(inputOf(q), {'personRef': 'u-bob'});
    }
  });

  test('lists and legal status decode', () async {
    final r = repo((req) {
      if (req.url.path == '/trust.lists') {
        return http.Response(
          ok({
            'blocked': [
              {
                'userId': 'u-bob',
                'handle': 'bob',
                'displayName': 'Bob',
                'avatarUrl': null,
              },
            ],
            'muted': <Object>[],
          }),
          200,
        );
      }
      return http.Response(
        ok({
          'termsVersion': '2026-10-02-draft',
          'termsUrl': 'https://chumbucket.fun/terms',
          'privacyUrl': 'https://chumbucket.fun/privacy',
          'deletionUrl': 'https://chumbucket.fun/delete-account',
          'venueTermsUrl': 'https://panta.market',
          'fundedTrading': {'accepted': false, 'acceptedAt': null},
        }),
        200,
      );
    });
    final lists = await r.lists();
    expect(lists.blocked.single.handle, 'bob');
    expect(lists.muted, isEmpty);
    final legal = await r.legalStatus();
    expect(legal.termsVersion, '2026-10-02-draft');
    expect(legal.fundedTradingAccepted, isFalse);
    expect(requests.map((q) => q.method), ['GET', 'GET']);
  });

  test('the attestation sends three literal yeses and the version', () async {
    final r = repo((_) => http.Response(ok({'accepted': true}), 200));
    await r.acceptFundedTrading('2026-10-02-draft');
    expect(requests.single.url.path, '/trust.acceptFundedTrading');
    expect(inputOf(requests.single), {
      'termsVersion': '2026-10-02-draft',
      'over18': true,
      'eligibleJurisdiction': true,
      'acceptsVenueTerms': true,
    });
  });

  test('deleteAccount confirms with DELETE and maps refusals', () async {
    final r = repo(
      (_) => http.Response(
        ok({'status': 'deleted', 'userId': 'u-ann', 'alreadyDeleted': false}),
        200,
      ),
    );
    final done = await r.deleteAccount();
    expect(done.alreadyDeleted, isFalse);
    expect(requests.single.url.path, '/auth.deleteAccount');
    expect(inputOf(requests.single), {'confirm': 'DELETE'});

    final signedOut = repo(
      (_) => http.Response(
        trpcError('UNAUTHORIZED', 401, 'Sign in to delete your account.'),
        401,
      ),
    );
    await expectLater(
      signedOut.deleteAccount(),
      throwsA(isA<CallsSignedOutException>()),
    );

    final retry = repo(
      (_) => http.Response(
        trpcError(
          'SERVICE_UNAVAILABLE',
          503,
          "Your profile has been removed, but we couldn't finish removing your sign-in. Try again in a moment. It's safe to retry.",
        ),
        503,
      ),
    );
    await expectLater(
      retry.deleteAccount(),
      throwsA(
        isA<CallsFailure>().having(
          (e) => e.message,
          'message',
          contains("It's safe to retry"),
        ),
      ),
    );
  });

  test('exportData returns the JSON object as-is', () async {
    final r = repo(
      (_) => http.Response(
        ok({'format': 'chumbucket-account-export/v1', 'calls': <Object>[]}),
        200,
      ),
    );
    final data = await r.exportData();
    expect(data['format'], 'chumbucket-account-export/v1');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/auth.exportData');
  });
}
