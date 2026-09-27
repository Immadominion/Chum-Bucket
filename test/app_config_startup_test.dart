import 'package:chumbucket/core/config/app_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cold startup initializes public config without loading an asset', () {
    // Separate isolate: nothing may prime dotenv before production startup.
    expect(dotenv.isInitialized, isFalse);
    expect(AppConfig.initialize, returnsNormally);
    expect(dotenv.isInitialized, isTrue);
    expect(dotenv.env, AppConfig.values);
    expect(AppConfig.initialize, returnsNormally);
    expect(dotenv.env, AppConfig.values);
  });
}
