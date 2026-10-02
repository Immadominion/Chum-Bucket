/// Settings → Blocked and muted: see who, and undo it.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';

class BlockedPeopleScreen extends StatefulWidget {
  const BlockedPeopleScreen({super.key, this.repository});
  final TrustRepository? repository;

  @override
  State<BlockedPeopleScreen> createState() => _BlockedPeopleScreenState();
}

class _BlockedPeopleScreenState extends State<BlockedPeopleScreen> {
  late final TrustRepository _repository =
      widget.repository ?? TrustRepository.of(context);
  RelationLists? _lists;
  String? _error;
  int _tab = 0;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final lists = await _repository.lists();
      if (mounted) setState(() => _lists = lists);
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _undo(TrustPerson person, {required bool block}) async {
    setState(() => _busy.add(person.userId));
    try {
      if (block) {
        await _repository.setBlocked(person.userId, blocked: false);
      } else {
        await _repository.setMuted(person.userId, muted: false);
      }
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            block
                ? 'Unblocked @${person.handle}.'
                : 'Unmuted @${person.handle}.',
          ),
        ),
      );
      context.read<CallsProvider?>()?.loadFeed(force: true);
      await _load();
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(person.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final lists = _lists;
    final people =
        lists == null ? null : (_tab == 0 ? lists.blocked : lists.muted);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Blocked and muted'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            ChumbucketTabs(
              labels: const ['Blocked', 'Muted'],
              selectedIndex: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 12),
            Text(
              _tab == 0
                  ? 'You and these people can\'t see each other\'s calls, respond '
                      'to them, or follow each other.'
                  : 'Their calls and notifications are hidden from you. They '
                      'can still see yours.',
              style: styles.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: styles.bodyMedium?.copyWith(color: AppColors.error),
              )
            else if (people == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (people.isEmpty)
              Text(
                _tab == 0
                    ? 'You haven\'t blocked anyone.'
                    : 'You haven\'t muted anyone.',
                style: styles.bodyMedium,
              )
            else
              for (final person in people)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      title: Text(person.displayName, style: styles.titleSmall),
                      subtitle: Text(
                        '@${person.handle}',
                        style: styles.bodySmall,
                      ),
                      trailing: TextButton(
                        onPressed:
                            _busy.contains(person.userId)
                                ? null
                                : () => _undo(person, block: _tab == 0),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(_tab == 0 ? 'Unblock' : 'Unmute'),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
