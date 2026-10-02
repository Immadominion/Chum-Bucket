// Release-facing guarantees of the Android manifest and network policy.
//
// These files are plain XML that no Dart code reads, so nothing else would
// notice a regression: an App Links filter that drifts away from the hosts the
// app actually parses, a push channel id the app no longer creates, or a
// cleartext exception creeping back into the release network policy.
import 'dart:io';

import 'package:chumbucket/core/services/notification_service.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/deeplink/call_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The `<intent-filter …>…</intent-filter>` blocks of the manifest.
List<String> _intentFilters(String manifest) => RegExp(
  r'<intent-filter[^>]*>[\s\S]*?</intent-filter>',
).allMatches(manifest).map((m) => m.group(0)!).toList();

Set<String> _attr(String block, String name) => RegExp(
  'android:$name="([^"]+)"',
).allMatches(block).map((m) => m.group(1)!).toSet();

void main() {
  final manifest = _read('android/app/src/main/AndroidManifest.xml');

  group('App Links (https://chumbucket.fun)', () {
    final verified =
        _intentFilters(
          manifest,
        ).where((f) => f.contains('android:autoVerify="true"')).toList();

    test('exactly one verified https filter is declared', () {
      expect(verified, hasLength(1));
      expect(_attr(verified.single, 'scheme'), {'https'});
    });

    test('it claims exactly the hosts the app parses as its own', () {
      expect(_attr(verified.single, 'host'), kCallDeepLinkHosts);
    });

    test('it claims only the /c, /u and /m share paths', () {
      expect(_attr(verified.single, 'pathPrefix'), {'/c/', '/u/', '/m/'});
      expect(_attr(verified.single, 'path'), isEmpty);
      expect(_attr(verified.single, 'pathPattern'), isEmpty);
    });

    test('the default link host is one of the verified hosts', () {
      final host = Uri.parse(kCallsLinkHostDefault).host;
      expect(_attr(verified.single, 'host'), contains(host));
    });

    test('the OAuth callback filter is untouched', () {
      expect(
        manifest,
        contains(
          'android:scheme="dev.cleva.chumbucket" android:host="login-callback"',
        ),
      );
    });
  });

  group('manifest hygiene', () {
    test('no unused boot-completed permission', () {
      expect(
        manifest,
        isNot(contains('android.permission.RECEIVE_BOOT_COMPLETED')),
      );
    });

    test('the FCM default channel is one the app creates', () {
      final channel =
          RegExp(
            r'default_notification_channel_id"\s*android:value="([^"]+)"',
          ).firstMatch(manifest)!.group(1);
      expect(channel, NotificationChannels.activity);
      expect(channel, isNot(NotificationChannels.legacyChallenges));
    });

    test('crash reporting is off until the person opts in', () {
      expect(
        RegExp(
          r'firebase_crashlytics_collection_enabled"\s*android:value="false"',
        ).hasMatch(manifest),
        isTrue,
      );
    });
  });

  group('network security', () {
    test('the release policy permits no cleartext traffic at all', () {
      final policy = _read(
        'android/app/src/main/res/xml/network_security_config.xml',
      );
      expect(policy, isNot(contains('cleartextTrafficPermitted="true"')));
    });

    test('the localhost exception exists only in the debug source set', () {
      final debug = _read(
        'android/app/src/debug/res/xml/network_security_config.xml',
      );
      expect(debug, contains('cleartextTrafficPermitted="true"'));
      expect(debug, contains('localhost'));
      expect(
        File(
          'android/app/src/release/res/xml/network_security_config.xml',
        ).existsSync(),
        isFalse,
      );
    });
  });
}
