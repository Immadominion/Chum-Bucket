import 'package:chumbucket/core/cache/snapshot_store.dart';
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

  /// The backend for a `CALLS_BACKEND` value.
  ///
  /// A **release** build always runs on the BFF. The seeded mock is demo data,
  /// and demo data shown in a store build reads as real to the person holding
  /// the phone, so no value — not `mock`, not a typo — can select it there.
  /// `scripts/build_release.sh` also refuses to build a release whose
  /// configuration does not say `bff`, so this is the second of two locks.
  static CallsBackend fromName(String? raw, {bool releaseMode = kReleaseMode}) {
    if (releaseMode) return CallsBackend.bff;
    switch (raw?.trim().toLowerCase()) {
      case 'mock':
        return CallsBackend.mock;
      case 'bff':
      case '':
      case null:
        // The configured BFF, not a seeded catalog, is the default. Panta is
        // the only intended live provider; completing and deploying that
        // backend migration is a separate gate, not something this flag proves.
        return CallsBackend.bff;
      default:
        // An unrecognised value is a configuration mistake. In a debug or
        // profile build, falling back to the mock is the safe direction for a
        // TYPO specifically: the app runs on visibly-demo data instead of
        // silently pointing somewhere nobody meant to name. An absent value is
        // different — that is the normal case, and it means production.
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
/// Defaults to [CallsBackend.bff]. This chooses a transport, not a venue, and
/// does not certify deployment readiness. The mock remains reachable with
/// `--dart-define=CALLS_BACKEND=mock` for tests and offline work.
CallsBackend resolveCallsBackend({
  Map<String, String>? overrides,
  bool releaseMode = kReleaseMode,
}) {
  final raw =
      overrides?[CallsBackend.configKey] ??
      AppConfig.values[CallsBackend.configKey];
  return CallsBackend.fromName(raw, releaseMode: releaseMode);
}

/// Builds the repository the app should run on.
///
/// [mockLatency] only exists so the loading state is visible when a human is
/// looking at it; tests pass [Duration.zero].
CallsRepository buildCallsRepository({
  CallsBackend? backend,
  Duration mockLatency = const Duration(milliseconds: 350),
  CallsBffAuthTokenProvider? authToken,
  SnapshotStore? snapshots,
}) {
  final resolved = backend ?? resolveCallsBackend();
  switch (resolved) {
    case CallsBackend.mock:
      return MockCallsRepository(latency: mockLatency);
    case CallsBackend.bff:
      // The last good reads stay on the phone so screens open on them.
      return BffCallsRepository(
        authToken: authToken,
        snapshots: snapshots ?? SnapshotStore.device,
      );
  }
}
