// The owner's rule for every default-navigation screen: the app refreshes on
// its own and never narrates it. No "stale or incomplete", no "Last updated",
// no "updated 3m ago", no Refresh and no Retry — a failed read keeps what is
// on screen, and the one action on an error state is "Try again".
//
// A source scan, so a merge that brings an old label back fails here even if
// no widget test happens to render that screen. Legacy Arena screens (behind
// callReceiptExperienceEnabled = false) are exempt and keep theirs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _literal = RegExp(
  "'(?:[^'\\\\]|\\\\.)*'" r'|"(?:[^"\\]|\\.)*"',
);

final _forbidden = <String, RegExp>{
  'stale or incomplete': RegExp('stale or incomplete', caseSensitive: false),
  'Last updated': RegExp('last updated', caseSensitive: false),
  'updated … ago': RegExp(r'updated\b.*\bago\b|updated \$', caseSensitive: false),
  'Refresh': RegExp(r'\bRefresh\b'),
  'Retry': RegExp(r'\bRetry\b'),
};

/// Lines that are logs, not copy anyone sees.
final _log = RegExp(
  r'AppLogger|developer\.log|debugPrint|\bprint\(|_log\(|\blog\(',
);

void main() {
  test('no default-navigation copy narrates freshness or asks to retry', () {
    final hits = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('lib/features/arena/'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        // A log's message often starts on the line after its call.
        final previous = i == 0 ? '' : lines[i - 1];
        if (line.startsWith('//') ||
            _log.hasMatch(line) ||
            _log.hasMatch(previous)) {
          continue;
        }
        for (final literal in _literal.allMatches(line)) {
          for (final MapEntry(:key, :value) in _forbidden.entries) {
            if (value.hasMatch(literal.group(0)!)) {
              hits.add('${file.path}:${i + 1} [$key] ${literal.group(0)}');
            }
          }
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
