/// The last good read of a screen, kept on this phone, so the app opens on
/// what you saw last time instead of a skeleton — and then refreshes it
/// silently.
///
/// What is kept is the server's own JSON for a read (the first page of the
/// feed, the open catalog, your own profile and record, your inbox), stored
/// verbatim and parsed by the same code that parses a live response. Nothing
/// here is a source of truth: a snapshot is only ever drawn until the live
/// read lands, and it is never sent anywhere.
///
/// Snapshots are keyed by the signed-in account, so a second account on the
/// same phone never sees the first one's rows, and they are wiped on sign-out
/// ([clear]). No credential, token or wallet secret is ever stored: only the
/// public read models a screen already shows.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

abstract class SnapshotStore {
  /// The decoded JSON saved under [key], or null when there is none, it is
  /// older than the store allows, or it cannot be read. Never throws.
  Future<Object?> read(String key);

  /// Saves [json] under [key]. Best effort: a failure is logged, never thrown.
  Future<void> write(String key, Object? json);

  /// Forgets everything (sign-out).
  Future<void> clear();

  /// The store the app uses on a device: JSON files in the app's private
  /// support directory. One instance, so every reader sees every writer.
  static final SnapshotStore device = FileSnapshotStore();
}

/// Builds a key that is safe as a file name and scoped to [viewer].
String snapshotKey(String name, {String? viewer, String? variant}) {
  String clean(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final parts = [
    clean(name),
    if (variant != null) clean(variant),
    viewer == null || viewer.isEmpty ? 'anon' : clean(viewer),
  ];
  return parts.join('.');
}

/// Files in `<app support>/snapshots/v1/`. Writes go to a temp file first and
/// are renamed into place, so a crash mid-write never leaves half a JSON file.
class FileSnapshotStore implements SnapshotStore {
  FileSnapshotStore({
    Future<Directory> Function()? directory,
    this.maxAge = const Duration(days: 14),
    DateTime Function()? clock,
  }) : _directory = directory ?? _defaultDirectory,
       _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  /// Older snapshots are ignored rather than drawn.
  final Duration maxAge;

  Directory? _resolved;

  static const int _offThreadBytes = 64 * 1024;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/snapshots/v1');
  }

  Future<Directory?> _dir() async {
    if (_resolved != null) return _resolved;
    try {
      final dir = await _directory();
      if (!await dir.exists()) await dir.create(recursive: true);
      return _resolved = dir;
    } catch (e) {
      // No platform directory (a test, an unusual device): no snapshots.
      developer.log('SnapshotStore unavailable: $e');
      return null;
    }
  }

  @override
  Future<Object?> read(String key) async {
    try {
      final dir = await _dir();
      if (dir == null) return null;
      final file = File('${dir.path}/$key.json');
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      // A catalog can run to a few hundred KB: parse it off the UI thread.
      final envelope =
          text.length > _offThreadBytes
              ? await Isolate.run(() => jsonDecode(text))
              : jsonDecode(text);
      if (envelope is! Map<String, dynamic>) return null;
      final savedAt = envelope['savedAt'];
      if (savedAt is! int) return null;
      final age = _clock().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAt),
      );
      if (age > maxAge) return null;
      return envelope['data'];
    } catch (e) {
      developer.log('SnapshotStore.read($key) failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? json) async {
    try {
      final dir = await _dir();
      if (dir == null) return;
      final envelope = {
        'savedAt': _clock().millisecondsSinceEpoch,
        'data': json,
      };
      final body =
          json is List && json.length > 50
              ? await Isolate.run(() => jsonEncode(envelope))
              : jsonEncode(envelope);
      final temp = File('${dir.path}/$key.json.tmp');
      await temp.writeAsString(body, flush: true);
      await temp.rename('${dir.path}/$key.json');
    } catch (e) {
      developer.log('SnapshotStore.write($key) failed: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final dir = await _dir();
      if (dir == null) return;
      if (await dir.exists()) await dir.delete(recursive: true);
      _resolved = null;
    } catch (e) {
      developer.log('SnapshotStore.clear failed: $e');
    }
  }
}

/// In memory, for tests and previews.
class MemorySnapshotStore implements SnapshotStore {
  final Map<String, String> _data = {};

  /// Keys written so far, for assertions.
  Iterable<String> get keys => _data.keys;

  @override
  Future<Object?> read(String key) async {
    final raw = _data[key];
    return raw == null ? null : jsonDecode(raw);
  }

  @override
  Future<void> write(String key, Object? json) async {
    _data[key] = jsonEncode(json);
  }

  @override
  Future<void> clear() async => _data.clear();
}
