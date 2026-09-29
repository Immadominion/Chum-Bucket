import 'package:chumbucket/features/authentication/session/existing_wallet_profile_guard.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mwa_storage_fakes.dart';

void main() {
  const address = 'synthetic-wallet-address';

  Future<ExistingWalletProfile> checkWith(
    http.Response Function(http.Request request) reply,
  ) async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://guard-test.invalid',
      'public-synthetic',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = reply(request);
        return http.Response(
          response.body,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    try {
      final result = await ExistingWalletProfileGuard(client).check(address);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/rest/v1/users');
      expect(requests.single.url.queryParameters['select'], 'id');
      expect(
        requests.single.url.queryParameters['wallet_address'],
        'eq.$address',
      );
      return result;
    } finally {
      await client.dispose();
    }
  }

  test(
    'found profile permits the guarded device flow without a write',
    () async {
      expect(
        await checkWith(
          (_) => http.Response(
            '[{"id":"synthetic-canonical-person"}]',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        ExistingWalletProfile.found,
      );
    },
  );

  test('unknown wallet is rejected without a write', () async {
    expect(
      await checkWith((_) => http.Response('', 406)),
      ExistingWalletProfile.unavailable,
    );
  });

  test('null PostgREST row means no existing person', () async {
    expect(
      await checkWith(
        (_) => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      ExistingWalletProfile.missing,
    );
  });

  test('read failure fails closed without a write', () async {
    expect(
      await checkWith(
        (_) => http.Response(
          '{"message":"unavailable"}',
          503,
          headers: {'content-type': 'application/json'},
        ),
      ),
      ExistingWalletProfile.unavailable,
    );
  });

  for (final hasProfile in [true, false]) {
    test(
      'guarded restore ${hasProfile ? 'keeps' : 'rejects'} saved wallet',
      () async {
        final rig = WalletStorageRig(legacyLogin: false);
        await rig.storage.save(walletFixture());
        final methods = <String>[];
        final client = SupabaseClient(
          'https://guard-test.invalid',
          'public-synthetic',
          httpClient: MockClient((request) async {
            methods.add(request.method);
            return http.Response(
              hasProfile ? '[{"id":"synthetic-person"}]' : '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        final provider = MwaAuthProvider(
          sessionStorage: rig.storage,
          supabaseClient: client,
          existingProfileOnly: true,
        );
        addTearDown(() async {
          provider.dispose();
          await client.dispose();
        });
        await provider.initialize();
        expect(provider.isAuthenticated, hasProfile);
        expect(await provider.isLoggedIn(), hasProfile);
        expect(provider.authResult == null, !hasProfile);
        expect(methods, everyElement('GET'));
        expect(methods, isNotEmpty);
        // A rejected restore is recoverable; it never deletes the old token.
        expect(await rig.storage.restore(), isNotNull);
      },
    );
  }
}
