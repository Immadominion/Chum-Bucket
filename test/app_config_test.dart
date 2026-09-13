import 'dart:io';

import 'package:chumbucket/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the boundary that the release APK broke: no secret may reach the
/// mobile client, and no `.env` may be bundled as a Flutter asset again.
void main() {
  group('asset bundle', () {
    test('pubspec does not ship .env (or any dotfile) as an asset', () {
      final lines = File('pubspec.yaml').readAsLinesSync();
      final start = lines.indexWhere((l) => l.trimRight() == '  assets:');
      expect(start, isNot(-1), reason: 'no flutter.assets block in pubspec');

      final entries = <String>[];
      for (final line in lines.skip(start + 1)) {
        final match = RegExp(r'^\s{4}-\s*(\S+)\s*$').firstMatch(line);
        if (match == null) break; // end of the assets list
        entries.add(match.group(1)!);
      }
      expect(entries, isNotEmpty);

      expect(
        entries,
        isNot(contains('.env')),
        reason: 'Bundling .env put HELIUS_API_KEY and VSC_MCP_ACCESS_TOKEN '
            'byte-for-byte inside every release APK.',
      );
      for (final entry in entries) {
        expect(
          entry.split('/').last.startsWith('.'),
          isFalse,
          reason: 'Asset "$entry" is a dotfile; dotfiles hold local config.',
        );
      }
    });
  });

  group('public key allowlist', () {
    test('contains no secret-shaped key name', () {
      for (final key in AppConfig.publicKeys) {
        for (final fragment in AppConfig.forbiddenKeyFragments) {
          expect(
            key.toUpperCase().contains(fragment),
            isFalse,
            reason: '$key looks like a secret and cannot ship in the client. '
                'Serve it from the BFF instead.',
          );
        }
      }
    });

    test('does not expose the provider RPC key or the access token', () {
      expect(AppConfig.publicKeys, isNot(contains('HELIUS_API_KEY')));
      expect(AppConfig.publicKeys, isNot(contains('VSC_MCP_ACCESS_TOKEN')));
      expect(AppConfig.publicKeys, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
      expect(AppConfig.publicKeys, isNot(contains('PRIVY_APP_SECRET')));
    });
  });

  group('urlCarriesCredential', () {
    test('detects credentials embedded in an RPC URL', () {
      expect(
        AppConfig.urlCarriesCredential(
          'https://mainnet.helius-rpc.com/?api-key=abc123',
        ),
        isTrue,
      );
      expect(
        AppConfig.urlCarriesCredential('https://rpc.example.com/?apiKey=abc'),
        isTrue,
      );
      expect(
        AppConfig.urlCarriesCredential('https://u:p@rpc.example.com'),
        isTrue,
      );
      expect(
        AppConfig.urlCarriesCredential('https://x.com/?access_token=t'),
        isTrue,
      );
    });

    test('leaves a clean public endpoint alone', () {
      expect(
        AppConfig.urlCarriesCredential('https://api.devnet.solana.com'),
        isFalse,
      );
      expect(
        AppConfig.urlCarriesCredential('https://api.mainnet-beta.solana.com'),
        isFalse,
      );
    });
  });

  group('sanitize', () {
    test('drops a credential-bearing RPC URL instead of shipping it', () {
      final out = AppConfig.sanitize({
        'SOLANA_MAINNET_RPC_URL': 'https://mainnet.helius-rpc.com/?api-key=k',
        'SOLANA_RPC_URL': 'https://api.devnet.solana.com',
      });
      expect(out.containsKey('SOLANA_MAINNET_RPC_URL'), isFalse);
      expect(out['SOLANA_RPC_URL'], 'https://api.devnet.solana.com');
    });

    test('drops any key outside the allowlist', () {
      final out = AppConfig.sanitize({
        'HELIUS_API_KEY': 'k',
        'VSC_MCP_ACCESS_TOKEN': 't',
        'SUPABASE_URL': 'https://project.supabase.co',
      });
      expect(out.keys, ['SUPABASE_URL']);
    });

    test('drops empty values so callers hit their public fallback', () {
      expect(AppConfig.sanitize({'SUPABASE_URL': ''}), isEmpty);
    });
  });
}
