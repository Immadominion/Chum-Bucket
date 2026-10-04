/// "Create a market": propose a YES/NO Panta market for review.
///
/// Proposing is free and touches no wallet. The form validates against the
/// server's rules (which mirror Panta's) as the person types, and the server
/// re-checks everything. A dropped reply is retried with the same idempotency
/// key, so it can never create a second proposal.
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';

import '../data/market_creation_models.dart';
import '../domain/market_draft_rules.dart';
import '../market_creation_controller.dart';
import 'widgets/proposal_widgets.dart';

class CreateMarketScreen extends StatefulWidget {
  const CreateMarketScreen({
    super.key,
    required this.controller,
    this.initial,
    this.now,
  });

  /// Owned by the caller, which keeps it alive across the flow.
  final MarketCreationController controller;

  /// Prefill, e.g. proposing a clearer version of a rejected market.
  final MarketDraft? initial;
  final DateTime Function()? now;

  @override
  State<CreateMarketScreen> createState() => _CreateMarketScreenState();
}

class _CreateMarketScreenState extends State<CreateMarketScreen> {
  static const _maxSourceFields = 5;
  final _question = TextEditingController();
  final _rules = TextEditingController();
  final _description = TextEditingController();
  final List<TextEditingController> _sources = [TextEditingController()];
  MarketCategory? _category;
  DateTime? _closesAt;
  DateTime? _resolvesAt;
  bool _attempted = false;
  String? _submitError;

  MarketCreationController get _controller => widget.controller;
  DateTime _now() => (widget.now ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _question.text = initial.question;
      _rules.text = initial.rules;
      _description.text = initial.description ?? '';
      _category = initial.category;
      // Times are re-picked when the old close is already too near.
      final lead = _controller.rules.proposeMinLead;
      if (initial.closesAt.isAfter(_now().add(lead))) {
        _closesAt = initial.closesAt.toUtc();
        _resolvesAt = initial.resolvesAt.toUtc();
      }
      _sources
        ..first.text = initial.sources.isEmpty ? '' : initial.sources.first
        ..addAll([
          for (final source in initial.sources
              .skip(1)
              .take(_maxSourceFields - 1))
            TextEditingController(text: source),
        ]);
    }
    _controller.addListener(_changed);
    if (_controller.status == null && !_controller.loadingStatus) {
      unawaited(_controller.loadStatus());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    for (final c in [_question, _rules, _description, ..._sources]) {
      c.dispose();
    }
    super.dispose();
  }

  MarketDraft? get _draft {
    final category = _category, closes = _closesAt;
    if (category == null || closes == null) return null;
    return MarketDraft(
      question: _question.text,
      category: category,
      closesAt: closes,
      resolvesAt: _resolvesAt ?? closes,
      rules: _rules.text,
      sources: [for (final s in _sources) s.text],
      description: _description.text,
    ).normalized();
  }

  Map<DraftField, String> get _problems {
    final draft = _draft;
    final problems = <DraftField, String>{};
    if (_category == null) problems[DraftField.category] = 'Pick a category.';
    if (_closesAt == null) {
      problems[DraftField.closesAt] = 'Pick when trading closes.';
    }
    final fallback =
        MarketDraft(
          question: _question.text,
          category: _category ?? MarketCategory.other,
          closesAt: _closesAt ?? _now().add(const Duration(days: 1)),
          resolvesAt:
              _resolvesAt ?? _closesAt ?? _now().add(const Duration(days: 1)),
          rules: _rules.text,
          sources: [for (final s in _sources) s.text],
          description: _description.text,
        ).normalized();
    for (final p in validateDraft(
      draft ?? fallback,
      now: _now(),
      rules: _controller.rules,
    )) {
      if (draft == null &&
          (p.field == DraftField.closesAt ||
              p.field == DraftField.resolvesAt)) {
        continue;
      }
      problems.putIfAbsent(p.field, () => p.message);
    }
    return problems;
  }

  String? _errorFor(DraftField field) => _attempted ? _problems[field] : null;

  Future<DateTime?> _pick(
    DateTime initial,
    DateTime first,
    DateTime last,
  ) async {
    // The picker asserts first <= initial <= last; a value picked earlier can
    // fall out of range while the form stays open.
    final start =
        initial.isBefore(first)
            ? first
            : initial.isAfter(last)
            ? last
            : initial;
    final date = await showDatePicker(
      context: context,
      initialDate: start.toLocal(),
      firstDate: first.toLocal(),
      lastDate: last.toLocal(),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start.toLocal()),
    );
    if (time == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
  }

  Future<void> _pickClose() async {
    final suggested = _closesAt ?? _now().add(const Duration(days: 1));
    final picked = await _pick(
      suggested,
      _now(),
      _now().add(_controller.rules.maxHorizon),
    );
    if (picked == null) return;
    setState(() {
      _closesAt = picked;
      // Keep "result known by" valid unless the person chose it on purpose.
      if (_resolvesAt == null || _resolvesAt!.isBefore(picked)) {
        _resolvesAt = picked;
      }
    });
  }

  Future<void> _pickResolve() async {
    final closes = _closesAt;
    if (closes == null) return _pickClose();
    final picked = await _pick(
      _resolvesAt ?? closes,
      closes,
      closes.add(_controller.rules.maxResolutionGap),
    );
    if (picked != null) setState(() => _resolvesAt = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _attempted = true;
      _submitError = null;
    });
    final draft = _draft;
    if (draft == null || _problems.isNotEmpty) return;
    try {
      final proposal = await _controller.propose(draft);
      if (mounted) Navigator.of(context).pop(proposal);
    } on CallsException catch (error) {
      if (mounted) setState(() => _submitError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _controller.status;
    final enabled = status?.proposalsEnabled ?? false;
    final rules = _controller.rules;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Create a market',
          style: AppTextStyles.textTheme.titleLarge,
        ),
        leading: IconButton(
          tooltip: 'Back',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const BasilIcon(
            'arrow-left-outline',
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'Ask a YES/NO question people can call. Chumbucket reviews it, then it’s published on Panta for anyone to call and trade.',
              style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (_controller.loadingStatus && status == null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ] else if (status == null && _controller.statusError != null)
              _Notice(
                text: _controller.statusError!,
                action: 'Try again',
                onAction: _controller.loadStatus,
              )
            else if (status != null && !enabled)
              // The server's reason is operator copy; say what it means here.
              const _Notice(
                text: 'Market proposals aren’t open yet. Check back soon.',
              ),
            const SizedBox(height: 16),
            _Section(
              label: 'Question',
              error: _errorFor(DraftField.question),
              child: TextField(
                controller: _question,
                maxLength: rules.questionMax,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: _input(
                  'Will BTC close above \$120,000 on 31 Dec 2026?',
                  helper: 'Be specific: what happens, by when, measured how.',
                ),
              ),
            ),
            _Section(
              label: 'Outcomes',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _OutcomeChip('YES', AppColors.success),
                  const _OutcomeChip('NO', AppColors.onPrimaryContainer),
                  Text(
                    'Panta markets are YES/NO.',
                    style: AppTextStyles.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _Section(
              label: 'Category',
              error: _errorFor(DraftField.category),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in MarketCategory.values)
                    Semantics(
                      selected: _category == category,
                      child: MarketFilterChip(
                        label: category.label,
                        selected: _category == category,
                        onPressed: () => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
            _Section(
              label: 'Trading closes',
              error: _errorFor(DraftField.closesAt),
              child: _TimeButton(
                value: _closesAt,
                placeholder: 'Pick a date and time',
                onPressed: _pickClose,
              ),
            ),
            _Section(
              label: 'Result known by',
              error: _errorFor(DraftField.resolvesAt),
              child: _TimeButton(
                value: _resolvesAt ?? _closesAt,
                placeholder: 'Same as close',
                onPressed: _pickResolve,
              ),
            ),
            _Section(
              label: 'How it resolves',
              error: _errorFor(DraftField.rules),
              child: TextField(
                controller: _rules,
                maxLength: rules.rulesMax,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: _input(
                  'Resolves YES if the CoinGecko BTC/USD daily close on 31 Dec 2026 (UTC) is above 120,000. Otherwise NO.',
                  helper:
                      'Name the exact source, value and time. Anyone should reach the same answer.',
                ),
              ),
            ),
            _Section(
              label: 'Source links',
              error: _errorFor(DraftField.sources),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, field) in _sources.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: field,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onChanged: (_) => setState(() {}),
                              decoration: _input(
                                'https://www.coingecko.com/en/coins/bitcoin',
                              ),
                            ),
                          ),
                          if (_sources.length > 1)
                            IconButton(
                              tooltip: 'Remove link',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed:
                                  () => setState(
                                    () => _sources.removeAt(index).dispose(),
                                  ),
                              icon: const BasilIcon(
                                'trash-outline',
                                size: 20,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_sources.length < _maxSourceFields)
                    TextButton.icon(
                      onPressed:
                          () => setState(
                            () => _sources.add(TextEditingController()),
                          ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const BasilIcon(
                        'add-outline',
                        size: 18,
                        color: AppColors.primary,
                      ),
                      label: const Text('Add another link'),
                    ),
                ],
              ),
            ),
            _Section(
              label: 'Description (optional)',
              error: _errorFor(DraftField.description),
              child: TextField(
                controller: _description,
                maxLength: rules.descriptionMax,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: _input(
                  'Context people should know before calling it.',
                ),
              ),
            ),
            const _FeeNote(),
            if (_submitError != null) ...[
              const SizedBox(height: 12),
              Text(
                _submitError!,
                style: AppTextStyles.textTheme.bodyMedium?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            if (_attempted && _problems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Fix the highlighted fields to send this for review.',
                style: AppTextStyles.textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ChumbucketPrimaryButton(
              label: 'Send for review',
              busy: _controller.proposing,
              busyLabel: 'Sending…',
              onPressed: enabled ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _input(String hint, {String? helper}) => InputDecoration(
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    hintMaxLines: 4,
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(label, style: AppTextStyles.textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.error,
            ),
          ),
        ],
      ],
    ),
  );
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: AppTextStyles.textTheme.labelLarge?.copyWith(color: color),
    ),
  );
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.value,
    required this.placeholder,
    required this.onPressed,
  });
  final DateTime? value;
  final String placeholder;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    icon: const BasilIcon(
      'calendar-outline',
      size: 20,
      color: AppColors.textSecondary,
    ),
    label: Text(
      value == null ? placeholder : localTime(value!),
      style: AppTextStyles.textTheme.bodyMedium?.copyWith(
        color: value == null ? AppColors.textSecondary : AppColors.textPrimary,
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warningContainer,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: AppTextStyles.textTheme.bodyMedium?.copyWith(
            color: AppColors.onWarningContainer,
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(action!),
          ),
      ],
    ),
  );
}

/// What it costs, said before anyone commits to anything.
class _FeeNote extends StatelessWidget {
  const _FeeNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Proposing is free', style: AppTextStyles.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          'Once approved, publishing on Panta costs a USDC creation fee plus a small SOL network fee, paid from the publishing wallet and not refundable. You’ll see the exact fee before your wallet signs anything.',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        const PoweredByPanta(),
      ],
    ),
  );
}
