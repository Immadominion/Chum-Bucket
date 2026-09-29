// Synthetic device probe. Copy into a SEPARATE disposable Flutter project with
// applicationId dev.cleva.wallet_storage_probe; NEVER run against Chumbucket's
// installed package. See docs/checkpoints/2026-09-29-wallet-secure-storage.md.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chumbucket/features/authentication/session/mwa_auth_result.dart';
import 'package:chumbucket/features/authentication/session/mwa_session_storage.dart';

const _enabled = bool.fromEnvironment('WALLET_STORAGE_PROBE');
const _phaseKey = 'synthetic_probe_phase';
const _sentinelKey = 'synthetic_unrelated_preference';

MwaAuthResult _fixture({bool renewed = false}) => MwaAuthResult(
  walletAddress: '11111111111111111111111111111111',
  authToken: renewed ? 'synthetic-renewed-only' : 'synthetic-original-only',
  publicKeyBytes: Uint8List(32),
  accountLabel: 'Synthetic account',
  walletUriBase: Uri.parse('https://wallet.invalid'),
  snsDomain: 'synthetic.skr',
);

void _require(bool condition) {
  if (!condition) throw StateError('Synthetic probe assertion failed');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var message = 'DISABLED';
  if (_enabled) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storage = MwaSessionStorage.device;
      final phase = prefs.getInt(_phaseKey) ?? 0;
      switch (phase) {
        case 0:
          // Refuse a nonempty installation before seeding anything.
          _require(prefs.getKeys().isEmpty);
          _require(await const DeviceWalletCredentialStore().read() == null);
          _require(await prefs.setString(_sentinelKey, 'preserve-me'));
          _require(
            await prefs.setString(
              mwaLegacyCredentialKey,
              jsonEncode(_fixture().toJson()),
            ),
          );
          _require(await prefs.setBool(mwaLegacyLoginKey, true));
          final restored = await storage.restore();
          _require(
            jsonEncode(restored?.toJson()) == jsonEncode(_fixture().toJson()),
          );
          await prefs.reload();
          _require(!prefs.containsKey(mwaLegacyCredentialKey));
          _require(!prefs.containsKey(mwaLegacyLoginKey));
          _require(await prefs.setInt(_phaseKey, 1));
          message = 'PASS migration';
        case 1:
          final restored = await storage.restore();
          _require(
            jsonEncode(restored?.toJson()) == jsonEncode(_fixture().toJson()),
          );
          await storage.save(_fixture(renewed: true));
          _require(await prefs.setInt(_phaseKey, 2));
          message = 'PASS cold-restart-and-renewal';
        case 2:
          final restored = await storage.restore();
          _require(
            jsonEncode(restored?.toJson()) ==
                jsonEncode(_fixture(renewed: true).toJson()),
          );
          await storage.clear();
          _require(await const DeviceWalletCredentialStore().read() == null);
          await prefs.reload();
          _require(!prefs.containsKey(mwaLegacyCredentialKey));
          _require(!prefs.containsKey(mwaLegacyLoginKey));
          _require(prefs.getString(_sentinelKey) == 'preserve-me');
          _require(await prefs.setInt(_phaseKey, 3));
          message = 'PASS renewed-restart-and-signout';
        case 3:
          _require(await storage.restore() == null);
          _require(await const DeviceWalletCredentialStore().read() == null);
          _require(prefs.getString(_sentinelKey) == 'preserve-me');
          message = 'PASS signed-out-cold-restart';
        default:
          throw StateError('Unknown synthetic probe phase');
      }
    } catch (_) {
      // Even native plugin exceptions never reach the log or screen.
      message = 'FAIL';
    }
  }
  debugPrint('CHUM_STORAGE_PROBE: $message');
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Synthetic storage probe')),
        body: Center(child: Text(message)),
      ),
    ),
  );
}
