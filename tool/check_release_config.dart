// Validates (and optionally writes) the release --dart-define file.
//
//   dart run tool/check_release_config.dart                 # committed file only
//   dart run tool/check_release_config.dart --out <path>    # merged, for a build
//
// Exit code 0 means the configuration may become a release. Values are never
// printed, only key names, so the output is safe to paste anywhere.
import 'dart:convert';
import 'dart:io';

import 'release_config.dart';

void main(List<String> args) {
  String? out;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) out = args[++i];
  }

  const committedPath = 'env.release.json';
  if (!File(committedPath).existsSync()) {
    stderr.writeln('Run from the app root: $committedPath not found.');
    exit(2);
  }
  final committed = readDefinesFile(committedPath);

  for (final key in kLocalOnlyKeys) {
    if (committed.containsKey(key)) {
      stderr.writeln(
        '$committedPath must not carry $key; it comes from your machine.',
      );
      exit(1);
    }
  }

  final localPath = 'env.local.json';
  final local =
      File(localPath).existsSync()
          ? readDefinesFile(localPath)
          : const <String, String>{};

  final merged = out == null
      ? committed
      : mergeReleaseConfig(
          committed: committed,
          environment: Platform.environment,
          localFile: local,
        );

  final problems = releaseConfigProblems(
    merged,
    requireLocalKeys: out != null,
  );
  if (problems.isNotEmpty) {
    stderr.writeln('Release configuration refused:');
    for (final p in problems) {
      stderr.writeln('  - $p');
    }
    exit(1);
  }

  if (out != null) {
    final file = File(out)..createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final e in merged.entries)
          if (!e.key.startsWith('_')) e.key: e.value,
      }),
    );
  }
  final keys = merged.keys.where((k) => !k.startsWith('_')).toList()..sort();
  stdout.writeln('Release configuration OK (${keys.join(', ')}).');
}
