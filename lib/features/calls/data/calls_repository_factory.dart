import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:flutter/foundation.dart';

/// Which implementation of [CallsRepository] the app runs on.
///
/// The swap is deliberately a build flag rather than an edit to main.dart:
/// pointing a release at the live BFF should not require a code change, and
/// pointing a demo back at the seeded catalog should not require reverting one.
///
///   flutter run --dart-define=CALLS_BACKEND=bff --dart-define=CALLS_BFF_URL=https://…
enum CallsBackend {
  /// Seeded, deterministic, offline. Every lifecycle state is reachable.
  mock,

  /// The live Bun/tRPC BFF.
  bff;

  static const String configKey = 'CALLS_BACKEND';

  static CallsBackend fromName(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'bff':
        return CallsBackend.bff;
      case 'mock':
      case '':
      case null:
        return CallsBackend.mock;
      default:
        // An unrecognised value is a configuration mistake. Falling back to the
        // mock is the safe direction: the app still runs, visibly on demo data,
        // instead of pointing at a host nobody meant to name.
        assert(() {
          debugPrint(
            'CallsBackend: unrecognised $configKey="$raw" — using the mock. '
            'Valid values are "mock" and "bff".',
          );
          return true;
        }());
        return CallsBackend.mock;
    }
  }
}

/// Resolves the configured backend.
///
/// Defaults to [CallsBackend.mock]. That default is the honest one: the BFF is
/// not deployed yet, and a build that silently pointed at `localhost:8787`
/// would fail every request on a real device with nothing on screen to explain
/// why.
CallsBackend resolveCallsBackend({Map<String, String>? overrides}) {
  final raw =
      overrides?[CallsBackend.configKey] ??
      AppConfig.values[CallsBackend.configKey];
  return CallsBackend.fromName(raw);
}

/// Builds the repository the app should run on.
///
/// [mockLatency] only exists so the loading state is visible when a human is
/// looking at it; tests pass [Duration.zero].
CallsRepository buildCallsRepository({
  CallsBackend? backend,
  Duration mockLatency = const Duration(milliseconds: 350),
  CallsBffAuthTokenProvider? authToken,
}) {
  final resolved = backend ?? resolveCallsBackend();
  switch (resolved) {
    case CallsBackend.mock:
      return MockCallsRepository(latency: mockLatency);
    case CallsBackend.bff:
      return BffCallsRepository(authToken: authToken);
  }
}
