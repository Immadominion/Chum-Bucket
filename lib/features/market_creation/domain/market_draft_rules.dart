/// Mirrors the BFF's `src/marketCreation/rules.ts`, which mirrors Panta's
/// create rules (question <= 512, rules <= 2048, 1-20 sources, eight
/// categories, start < end <= resolution) plus Chumbucket's review lead,
/// horizon and public-link policy. The server stays the authority; this only
/// stops a person sending what we already know will be refused.
library;

import '../data/market_creation_models.dart';

enum DraftField {
  question,
  category,
  closesAt,
  resolvesAt,
  rules,
  sources,
  description,
}

class DraftProblem {
  const DraftProblem(this.field, this.message);
  final DraftField field;
  final String message;
}

final _control = RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]');
final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

/// A public http(s) link a person and the venue can both open.
bool isPublicSourceUrl(String value, {int maxLength = 512}) {
  if (value.isEmpty ||
      value.length > maxLength ||
      RegExp(r'\s').hasMatch(value)) {
    return false;
  }
  final Uri uri;
  try {
    uri = Uri.parse(value);
  } catch (_) {
    return false;
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  if (uri.userInfo.isNotEmpty) return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      !host.contains('.') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      _ipv4.hasMatch(host) ||
      host.contains(':')) {
    return false;
  }
  return true;
}

/// Every problem with a normalised draft, in form order. Empty means it can
/// be proposed now.
List<DraftProblem> validateDraft(
  MarketDraft draft, {
  required DateTime now,
  MarketCreationRules rules = const MarketCreationRules(),
}) {
  final problems = <DraftProblem>[];
  void add(DraftField field, String message) =>
      problems.add(DraftProblem(field, message));

  if (draft.question.length < rules.questionMin) {
    add(
      DraftField.question,
      'Ask a full question (at least ${rules.questionMin} characters).',
    );
  } else if (draft.question.length > rules.questionMax) {
    add(
      DraftField.question,
      'Keep the question under ${rules.questionMax} characters.',
    );
  } else if (_control.hasMatch(draft.question)) {
    add(DraftField.question, 'Remove hidden characters from the question.');
  }

  final closes = draft.closesAt.toUtc();
  final resolves = draft.resolvesAt.toUtc();
  if (closes.isBefore(now.add(rules.proposeMinLead))) {
    add(
      DraftField.closesAt,
      'Trading must stay open for at least ${rules.proposeMinLead.inHours} more hours so the market can be reviewed and published.',
    );
  } else if (closes.isAfter(now.add(rules.maxHorizon))) {
    add(DraftField.closesAt, 'Pick a close within the next two years.');
  }

  if (resolves.isBefore(closes)) {
    add(
      DraftField.resolvesAt,
      'The result can’t be known before trading closes.',
    );
  } else if (resolves.isAfter(closes.add(rules.maxResolutionGap))) {
    add(
      DraftField.resolvesAt,
      'The result must be known within ${rules.maxResolutionGap.inDays} days of trading closing.',
    );
  }

  if (draft.rules.length < rules.rulesMin) {
    add(
      DraftField.rules,
      'Explain exactly how YES or NO is decided (at least ${rules.rulesMin} characters).',
    );
  } else if (draft.rules.length > rules.rulesMax) {
    add(DraftField.rules, 'Keep the rules under ${rules.rulesMax} characters.');
  } else if (_control.hasMatch(draft.rules)) {
    add(DraftField.rules, 'Remove hidden characters from the rules.');
  }

  if (draft.sources.isEmpty) {
    add(
      DraftField.sources,
      'Add at least one link where the result can be checked.',
    );
  } else if (draft.sources.length > rules.sourcesMax) {
    add(DraftField.sources, 'Use at most ${rules.sourcesMax} source links.');
  } else if (!draft.sources.every(
    (s) => isPublicSourceUrl(s, maxLength: rules.sourceUrlMax),
  )) {
    add(DraftField.sources, 'Each source must be a public http(s) link.');
  }

  final description = draft.description;
  if (description != null) {
    if (description.length > rules.descriptionMax) {
      add(
        DraftField.description,
        'Keep the description under ${rules.descriptionMax} characters.',
      );
    } else if (_control.hasMatch(description)) {
      add(
        DraftField.description,
        'Remove hidden characters from the description.',
      );
    }
  }
  return problems;
}
