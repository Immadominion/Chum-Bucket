/// The same basic text policy the BFF enforces (src/trust/contentFilter.ts in
/// the API repo), so a person hears the reason before anything is sent.
///
/// The server decides; this only explains early. It matters most for bios and
/// names written through the legacy profile path, which does not pass through
/// the BFF yet.
library;

enum ContentField {
  thesis('your thesis'),
  note('your note'),
  name('your name'),
  handle('that username'),
  bio('your bio');

  const ContentField(this.label);
  final String label;
}

/// Null when the text is fine; otherwise the message to show.
String? contentPolicyProblem(String? text, ContentField field) {
  if (text == null || text.trim().isEmpty) return null;
  if (_hasLink(text)) {
    return "Links aren't allowed in ${field.label}. Remove the web address and try again.";
  }
  if (_hasBlockedLanguage(text)) {
    final label = field.label;
    return '${label[0].toUpperCase()}${label.substring(1)} includes language '
        "we don't allow. Please rephrase it.";
  }
  return null;
}

const _tlds = [
  'com', 'net', 'org', 'io', 'xyz', 'app', 'fun', 'gg', 'co', 'me', 'ly', //
  'link', 'site', 'online', 'ru', 'cn', 'tk', 'info', 'biz', 'finance',
  'money', 'exchange', 'top', 'club', 'vip', 'live', 'tv', 'us', 'uk', 'ai',
  'so', 'to', 'cc', 'pw', 'dev', 'page', 'store', 'shop', 'click', 'lol',
  'win', 'bet', 'casino', 'zip', 'sh', 'im', 'gl', 'ws', 'cx', 'su', 'trade',
  'markets', 'market', 'pro',
];

final _linkPatterns = [
  RegExp(r'\bhttps?://', caseSensitive: false),
  RegExp(r'\bwww\.', caseSensitive: false),
  // Same rule as the server: the suffix is lowercase ("pump.fun",
  // "OpenAI.com"), or all capitals after an all-capitals name ("SCAM.COM").
  // A missed space before a capitalised word ("win.So easy") is a typo.
  RegExp(
    '(?:^|[^A-Za-z0-9-])[A-Za-z0-9][A-Za-z0-9-]{0,62}\\.(?:${_tlds.join('|')})(?![A-Za-z0-9])',
  ),
  RegExp(
    '(?:^|[^A-Za-z0-9-])[A-Z0-9][A-Z0-9-]{1,62}\\.(?:${_tlds.join('|').toUpperCase()})(?![A-Za-z0-9])',
  ),
];

const _blockedWords = {
  'kys', 'fag', 'fags', 'kike', 'kikes', 'spic', 'spics', 'tranny', //
  'trannies', 'wetback', 'wetbacks', 'cunt', 'cunts', 'pussy', 'pussies',
  'twat', 'twats',
};

const _blockedStems = [
  'fuck', 'motherfuck', 'nigger', 'nigga', 'faggot', 'retard', 'cocksuck', //
  'whore', 'slut', 'bitch', 'asshole', 'dickhead', 'rapist',
];

const _leet = {
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', //
  r'$': 's', '!': 'i', '|': 'i',
};

bool _hasLink(String text) => _linkPatterns.any((p) => p.hasMatch(text));

List<String> _tokens(String text) {
  final lowered = text.toLowerCase().split('').map((c) => _leet[c] ?? c).join();
  final raw = lowered.split(RegExp('[^a-z]+')).where((t) => t.isNotEmpty);
  final out = <String>[];
  var run = '';
  for (final t in raw) {
    if (t.length == 1) {
      run += t;
      continue;
    }
    if (run.isNotEmpty) out.add(run);
    run = '';
    out.add(t);
  }
  if (run.isNotEmpty) out.add(run);
  return out;
}

String _unstretch(String t) =>
    t.replaceAllMapped(RegExp(r'([a-z])\1{2,}'), (m) => m.group(1)!);

bool _hasBlockedLanguage(String text) {
  for (final token in _tokens(text)) {
    for (final t in {token, _unstretch(token)}) {
      if (_blockedWords.contains(t)) return true;
      if (_blockedStems.any(t.startsWith)) return true;
    }
  }
  return false;
}
