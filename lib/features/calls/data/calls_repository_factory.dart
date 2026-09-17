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
      case 'mock':
        return CallsBackend.mock;
      case 'bff':
      case '':
      case null:
        // Real by default. The BFF is deployed and serving live Polymarket
        // markets, so a build with no --dart-define should talk to it rather
        // than to a seeded catalog — the mock is for tests and offline work,
        // and shipping it by accident is how invented data reaches a person.
        return CallsBackend.bff;
      default:
        // An unrecognised value is a configuration mistake. Falling back to the
        // mock is still the safe direction for a TYPO specifically: the app runs
        // on visibly-demo data instead of silently pointing somewhere nobody
        // meant to name. An absent value is different — that is the normal case,
        // and it means production.
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
/// Defaults to [CallsBackend.bff] — the deployed backend serving real
/// Polymarket markets. The mock remains reachable with
/// `--dart-define=CALLS_BACKEND=mock` for tests and offline work.
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
