import 'dart:async';

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fakes.dart';

class SlowRefresh extends FakeSupabaseAuthPort {
  SlowRefresh() : super(restored: expiringSnapshot());
  final started = Completer<void>();
  final result = Completer<SupabaseSessionSnapshot?>();

  @override
  Future<SupabaseSessionSnapshot?> refreshSession() {
    started.complete();
    return result.future;
  }
}

void main() {
  for (final returnsToken in [true, false]) {
    test(
      'refresh after sign-out cannot return the old bearer ($returnsToken)',
      () async {
        final auth = SlowRefresh();
        final session = ChumbucketSession(
          auth: auth,
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: happyBff().client,
          ),
        );
        addTearDown(() async {
          session.dispose();
          await auth.close();
        });
        await session.restore();
        final token = session.bffAuthToken();
        await auth.started.future;
        await session.signOut();
        auth.result.complete(returnsToken ? snapshot() : null);
        expect(await token, isNull);
        expect(session.accessToken, isNull);
      },
    );
  }
}
