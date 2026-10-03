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

  test('no single bundled file over 3 MB', () {
    for (final p in bundled) {
      expect(File(p).lengthSync(), lessThan(3 * 1024 * 1024), reason: p);
    }
  });

  test('the old onboarding GIFs, fallback stills and music are gone (B6)', () {
    // The onboarding rewrite replaced them with brand art and Lottie that
    // were already in the app; nothing references them any more.
    for (final gone in const [
      'assets/animations/whisk_ai_generate/',
      'assets/images/ai_gen/whisk_animation_fallback/',
      'assets/audio/',
    ]) {
      expect(entries, isNot(contains(gone)), reason: gone);
      expect(Directory(gone).existsSync(), isFalse, reason: gone);
    }
    expect(bundled.where((p) => p.endsWith('.gif')), isEmpty);
    expect(bundled.where((p) => p.endsWith('.mp3')), isEmpty);
  });

  test('total bundled assets stay under 15 MB', () {
    // About 10 MB once the onboarding GIFs went (was 37 MB with them).
    final total = bundled.fold<int>(0, (s, p) => s + File(p).lengthSync());
    expect(total, lessThan(15 * 1024 * 1024));
  });
}
