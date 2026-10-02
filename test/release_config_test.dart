import 'dart:io';

import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../tool/release_config.dart';

Map<String, String> good() => {
  'CALL_RECEIPT_EXPERIENCE': 'true',
  'CALLS_BACKEND': 'bff',
  'CALLS_BFF_URL': 'https://chumbucket-calls-bff-production.up.railway.app',
  'CALLS_LINK_HOST': 'https://chumbucket.fun',
  'SOLANA_NETWORK': 'mainnet-beta',
  'SUPABASE_URL': 'https://example.supabase.co',
  'SUPABASE_ANON_KEY': 'public-anon',
};

void main() {
  group('the committed env.release.json', () {
    final committed = readDefinesFile('env.release.json');

    test('passes the gate on its own', () {
      expect(releaseConfigProblems(committed, requireLocalKeys: false), isEmpty);
    });

    test('carries no Supabase project values (they come from the builder)', () {
      for (final key in kLocalOnlyKeys) {
        expect(committed.containsKey(key), isFalse, reason: key);
      }
    });

    test('every key is one the app is allowed to carry', () {
      for (final key in committed.keys.where((k) => !k.startsWith('_'))) {
        expect(AppConfig.publicKeys, contains(key), reason: key);
      }
    });

    test('names mainnet, the receipt product, the BFF and the live site', () {
      expect(committed['SOLANA_NETWORK'], 'mainnet-beta');
      expect(committed['CALL_RECEIPT_EXPERIENCE'], 'true');
      expect(committed['CALLS_BACKEND'], 'bff');
      expect(committed['CALLS_LINK_HOST'], kCallsLinkHostDefault);
      expect(committed['CALLS_BFF_URL'], kCallsBffDefaultUrl);
    });
  });

  group('the gate refuses', () {
    test('a complete, correct config passes', () {
      expect(releaseConfigProblems(good()), isEmpty);
    });

    test('the receipt experience switched off', () {
      for (final v in [null, 'false', '0', '']) {
        final c = good()..remove('CALL_RECEIPT_EXPERIENCE');
        if (v != null) c['CALL_RECEIPT_EXPERIENCE'] = v;
        expect(
          releaseConfigProblems(c).join(),
          contains('CALL_RECEIPT_EXPERIENCE'),
        );
      }
    });

    test('any network but mainnet', () {
      for (final v in [null, 'devnet', 'testnet', '']) {
        final c = good()..remove('SOLANA_NETWORK');
        if (v != null) c['SOLANA_NETWORK'] = v;
        expect(releaseConfigProblems(c).join(), contains('SOLANA_NETWORK'));
      }
    });

    test('any backend but bff', () {
      for (final v in [null, 'mock', 'prod', '']) {
        final c = good()..remove('CALLS_BACKEND');
        if (v != null) c['CALLS_BACKEND'] = v;
        expect(releaseConfigProblems(c).join(), contains('CALLS_BACKEND'));
      }
    });

    test('a local or plain-http BFF', () {
      for (final v in ['http://localhost:8787', 'https://localhost', 'http://x.up.railway.app']) {
        final c = good()..['CALLS_BFF_URL'] = v;
        expect(releaseConfigProblems(c).join(), contains('CALLS_BFF_URL'));
      }
    });

    test('the dead chumbucket.app link host', () {
      final c = good()..['CALLS_LINK_HOST'] = 'https://chumbucket.app';
      expect(releaseConfigProblems(c).join(), contains('CALLS_LINK_HOST'));
    });

    test('missing Supabase values when building', () {
      final c = good()
        ..remove('SUPABASE_ANON_KEY')
        ..remove('SUPABASE_URL');
      final problems = releaseConfigProblems(c).join();
      expect(problems, contains('SUPABASE_URL'));
      expect(problems, contains('SUPABASE_ANON_KEY'));
    });

    test('secret-shaped keys and credential URLs', () {
      final c = good()
        ..['HELIUS_API_KEY'] = 'x'
        ..['SOLANA_RPC_URL'] = 'https://mainnet.helius-rpc.com/?api-key=abc';
      final problems = releaseConfigProblems(c).join();
      expect(problems, contains('HELIUS_API_KEY'));
      expect(problems, contains('SOLANA_RPC_URL'));
    });
  });

  group('merge', () {
    test('takes only the Supabase values from the builder, env first', () {
      final merged = mergeReleaseConfig(
        committed: {'SOLANA_NETWORK': 'mainnet-beta'},
        environment: {'SUPABASE_ANON_KEY': 'from-env'},
        localFile: {
          'SUPABASE_URL': 'https://p.supabase.co',
          'SUPABASE_ANON_KEY': 'from-file',
          'SOLANA_NETWORK': 'devnet',
          'CALLS_BACKEND': 'mock',
        },
      );
      expect(merged, {
        'SOLANA_NETWORK': 'mainnet-beta',
        'SUPABASE_URL': 'https://p.supabase.co',
        'SUPABASE_ANON_KEY': 'from-env',
      });
    });
  });

  test('the gate mirrors AppConfig\'s secret rules', () {
    expect(kForbiddenKeyFragments, AppConfig.forbiddenKeyFragments);
    for (final v in [
      'https://x/?api-key=1',
      'https://u:p@host/',
      'https://x/?token=1',
      'https://api.mainnet-beta.solana.com',
    ]) {
      expect(urlCarriesCredential(v), AppConfig.urlCarriesCredential(v), reason: v);
    }
  });

  test('the version is above every build already handed out', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final version = pubspec['version'] as String;
    final name = version.split('+').first;
    final code = int.parse(version.split('+').last);
    // dApp Store version_code 2 is on chain; sideloaded/local builds reached 33.
    expect(code, greaterThanOrEqualTo(34));

    final publishing =
        loadYaml(File('publishing/config.yaml').readAsStringSync()) as YamlMap;
    final submitted =
        (publishing['lastSubmittedVersionOnChain'] as YamlMap)['version_code']
            as int;
    expect(code, greaterThan(submitted));

    // The listing being prepared describes this exact build.
    final details =
        (publishing['release'] as YamlMap)['android_details'] as YamlMap;
    expect(details['version_code'], code);
    expect(details['version'], name);
    expect(
      details['cert_fingerprint'],
      '315b22c7fe1c285eae7a9915629037fc8ec3239fed347a734957dc250850e1c7',
    );
  });
}
