import 'package:chumbucket/core/providers/enhanced_base_provider.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final enhanced in [false, true]) {
    group(enhanced ? 'EnhancedBaseChangeNotifier' : 'BaseChangeNotifier', () {
      late Future<bool> Function() check;

      setUp(() {
        if (enhanced) {
          final provider = EnhancedBaseChangeNotifier();
          check = provider.hasInternetConnection;
          addTearDown(provider.dispose);
        } else {
          final provider = BaseChangeNotifier();
          check = provider.hasInternetConnection;
          addTearDown(provider.dispose);
        }
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      });

      for (final interfaces in [
        <String>['none'],
        <String>[],
      ]) {
        test('reports offline for interface list $interfaces', () async {
          var checks = 0;
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'check');
            checks++;
            return interfaces;
          });

          // A list must not be compared with ConnectivityResult.none: that
          // comparison is always false and incorrectly falls through to DNS.
          expect(await check(), isFalse);
          expect(checks, 1);
        });
      }

      test('platform failure reports offline instead of throwing', () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });
        expect(await check(), isFalse);
      });
    });
  }
}
