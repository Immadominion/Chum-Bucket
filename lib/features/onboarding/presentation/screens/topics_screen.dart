/// T "What are you into?" (onboarding spec §6): only categories that really
/// have open markets, with their counts. The choice orders Markets ("For
/// you"), first-call picks and Home's top calls; it never hides anything.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/topic_chip.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

class TopicsScreen extends StatelessWidget {
  const TopicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final loading = flow.topicsData == StepData.loading;
    final count =
        flow.selectedTopics
            .where((s) => flow.topics.any((t) => t.slug == s))
            .length;
    return OnboardingScaffold(
      onBack: flow.canGoBack ? flow.back : null,
      progress: flow.progress,
      announce: OnboardingCopy.topicsTitle,
      actions: [
        ChumbucketPrimaryButton(
          key: const ValueKey('topics-continue'),
          label:
              count == 0 ? OnboardingCopy.ctaSkip : OnboardingCopy.ctaContinue,
          onPressed: loading ? null : () => unawaited(flow.completeTopics()),
        ),
      ],
      children: [
        const OnbTitle(OnboardingCopy.topicsTitle),
        const SizedBox(height: 8),
        const OnbBody(OnboardingCopy.topicsBody),
        const SizedBox(height: 24),
        if (loading)
          const TopicChipsSkeleton()
        else
          TopicChips(
            topics: flow.topics,
            selected: flow.selectedTopics,
            onToggle: flow.toggleTopic,
          ),
        const SizedBox(height: 20),
        Text(OnboardingCopy.topicsNote, style: OnbText.small),
      ],
    );
  }
}

/// Profile → Settings → Topics: the same chips in the app's wavy sheet.
Future<void> showTopicsSheet(BuildContext context) =>
    showChumbucketWavySheet<void>(
      context: context,
      builder: (_) => const TopicsSheet(),
    );

class TopicsSheet extends StatefulWidget {
  const TopicsSheet({super.key});

  @override
  State<TopicsSheet> createState() => _TopicsSheetState();
}

class _TopicsSheetState extends State<TopicsSheet> {
  Set<String>? _selected;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selected ??= {...context.read<OnboardingController>().topics};
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(context.read<CallsProvider>().loadOpenMarkets());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallsProvider>();
    final topics = topicsFrom(calls.openMarkets, DateTime.now());
    final loading = calls.isLoadingOpenMarkets && topics.isEmpty;
    final selected = _selected!;
    return ChumbucketWavySheet(
      title: OnboardingCopy.topicsSheetTitle,
      subtitle: OnboardingCopy.topicsSheetBody,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child:
            loading
                ? const TopicChipsSkeleton()
                : topics.isEmpty
                ? Text(OnboardingCopy.topicsSheetEmpty, style: OnbText.small)
                : TopicChips(
                  topics: topics,
                  selected: selected,
                  onToggle:
                      (slug) => setState(
                        () =>
                            selected.contains(slug)
                                ? selected.remove(slug)
                                : selected.add(slug),
                      ),
                ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: ChumbucketPrimaryButton(
          key: const ValueKey('topics-sheet-save'),
          label: OnboardingCopy.topicsSheetSave,
          onPressed: () async {
            await context.read<OnboardingController>().setTopics(selected);
            if (context.mounted) Navigator.of(context).maybePop();
          },
        ),
      ),
    );
  }
}
