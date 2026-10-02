// What the APK bundles (audit M17). The release APK used to carry 126 MB of
// assets, 72 MB of it three design-reference PNGs nothing referenced. These
// checks keep that from creeping back.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

List<String> _assetEntries() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final flutter = pubspec['flutter'] as YamlMap;
  return (flutter['assets'] as YamlList).cast<String>().toList();
}

/// Files Flutter bundles for one pubspec entry: a directory entry takes its
/// direct children only (not subdirectories); a file entry is itself.
List<File> _filesFor(String entry) {
  if (entry.endsWith('/')) {
    return Directory(entry)
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.split('/').last.startsWith('.'))
        .toList();
  }
  return [File(entry)];
}

void main() {
  final entries = _assetEntries();
  final bundled = {for (final e in entries) ..._filesFor(e).map((f) => f.path)};

  test('every asset entry exists', () {
    for (final e in entries) {
      final exists =
          e.endsWith('/') ? Directory(e).existsSync() : File(e).existsSync();
      expect(exists, isTrue, reason: e);
    }
  });

  test('the unreferenced design references are not bundled', () {
    expect(
      bundled.where((p) => p.contains('figma_community')),
      isEmpty,
    );
    expect(bundled.where((p) => p.contains('/irfan/')), isEmpty);
  });

  test('avatars are 256px-class files, state art 512px-class', () {
    for (final p in bundled.where((p) => p.contains('profile_images/'))) {
      expect(File(p).lengthSync(), lessThan(200 * 1024), reason: p);
    }
    for (final p in bundled.where((p) => p.contains('images/states/'))) {
      expect(File(p).lengthSync(), lessThan(400 * 1024), reason: p);
    }
  });

  test('no single bundled file over 3 MB, except the onboarding animations', () {
    // The onboarding GIFs (~25 MB) belong to the onboarding rewrite (B6),
    // which replaces them with lightweight art; they are allowed here until
    // then and nothing else is.
    const pendingOnboarding = 'assets/animations/whisk_ai_generate/';
    for (final p in bundled) {
      if (p.startsWith(pendingOnboarding)) continue;
      expect(File(p).lengthSync(), lessThan(3 * 1024 * 1024), reason: p);
    }
  });

  test('total bundled assets stay under 45 MB', () {
    final total = bundled.fold<int>(0, (s, p) => s + File(p).lengthSync());
    expect(total, lessThan(45 * 1024 * 1024));
  });
}
