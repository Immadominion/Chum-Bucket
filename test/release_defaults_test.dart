import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/features/calls/data/calls_repository_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('network (B10)', () {
    test('a release build with no network named is on mainnet', () {
      expect(
        NetworkConfig.resolve(null, releaseMode: true),
        NetworkConfig.mainnetBeta,
      );
      expect(
        NetworkConfig.resolve('', releaseMode: true),
        NetworkConfig.mainnetBeta,
      );
      expect(
        NetworkConfig.resolve('garbage', releaseMode: true),
        NetworkConfig.mainnetBeta,
      );
    });

    test('a debug build with no network named stays on devnet', () {
      expect(
        NetworkConfig.resolve(null, releaseMode: false),
        NetworkConfig.devnet,
      );
    });

    test('an explicit value always wins', () {
      for (final release in [true, false]) {
        expect(
          NetworkConfig.resolve('mainnet', releaseMode: release),
          NetworkConfig.mainnetBeta,
        );
        expect(
          NetworkConfig.resolve(' Mainnet-Beta ', releaseMode: release),
          NetworkConfig.mainnetBeta,
        );
        expect(
          NetworkConfig.resolve('devnet', releaseMode: release),
          NetworkConfig.devnet,
        );
      }
    });
  });

  group('calls backend (m2)', () {
    test('a release build always runs on the BFF, whatever is configured', () {
      for (final raw in [null, '', 'bff', 'mock', 'MOCK', 'prod', 'fake']) {
        expect(
          CallsBackend.fromName(raw, releaseMode: true),
          CallsBackend.bff,
          reason: 'CALLS_BACKEND=$raw',
        );
        expect(
          resolveCallsBackend(
            overrides: {if (raw != null) 'CALLS_BACKEND': raw},
            releaseMode: true,
          ),
          CallsBackend.bff,
        );
      }
    });

    test('debug builds keep the explicit mock for offline work', () {
      expect(
        CallsBackend.fromName('mock', releaseMode: false),
        CallsBackend.mock,
      );
      expect(CallsBackend.fromName(null, releaseMode: false), CallsBackend.bff);
    });
  });

  group('release logging (m3)', () {
    late DebugPrintCallback saved;
    setUp(() => saved = debugPrint);
    tearDown(() => debugPrint = saved);

    test('release drops debugPrint output', () {
      final printed = <String?>[];
      debugPrint = (m, {wrapWidth}) => printed.add(m);
      AppLogger.installReleaseLogPolicy(releaseMode: true);
      debugPrint('wallet 479yvcq7yibHaVKAGLEWu89G7G3KnmWSaDZHNXphd1Mu');
      expect(printed, isEmpty);
    });

    test('debug keeps debugPrint as it was', () {
      final printed = <String?>[];
      debugPrint = (m, {wrapWidth}) => printed.add(m);
      AppLogger.installReleaseLogPolicy(releaseMode: false);
      debugPrint('hello');
      expect(printed, ['hello']);
    });
  });
}
