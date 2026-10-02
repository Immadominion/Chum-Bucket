/// "Claim your @username" for an account that already exists but has none —
/// made before usernames, or a wallet profile carried over to wallet sign-in.
/// Such accounts show a `user-xxxxxxxx` placeholder everywhere until they do.
///
/// [UsernameClaimPrompt] asks once per account on this device, right after
/// sign-in; Profile keeps a "Claim your @username" row until it is done. A
/// claimed username is permanent here: the server never renames one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

import 'username_availability.dart';

Future<void> showClaimHandleSheet(BuildContext context) =>
    showChumbucketWavySheet<void>(
      context: context,
      builder: (_) => const ClaimHandleSheet(),
    );

class ClaimHandleSheet extends StatelessWidget {
  const ClaimHandleSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    return ChumbucketWavySheet(
      title: 'Claim your username',
      subtitle: 'How people find you, follow you and see your calls.',
      canDismiss: !session.isClaimingHandle,
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ClaimHandleForm(),
      ),
    );
  }
}

class ClaimHandleForm extends StatefulWidget {
  const ClaimHandleForm({super.key, this.onClaimed});

  /// Called after a successful claim; by default the sheet closes.
  final VoidCallback? onClaimed;

  @override
  State<ClaimHandleForm> createState() => _ClaimHandleFormState();
}

class _ClaimHandleFormState extends State<ClaimHandleForm> {
  final _handle = TextEditingController();
  late final _availability = UsernameAvailability(
    context.read<ChumbucketSession>().usernameStatus,
  )..addListener(_changed);
  String? _error;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _availability.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final session = context.read<ChumbucketSession>();
    final calls = context.read<CallsProvider?>();
    setState(() => _error = null);
    final failure = await session.claimUsername(_availability.handle);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure.message);
      return;
    }
    // The feed and profile show the new name at once.
    final userId = session.userId;
    if (userId != null) await calls?.loadPerson(userId, force: true);
    if (!mounted) return;
    final done = widget.onClaimed;
    if (done != null) {
      done();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    final busy = session.isClaimingHandle;
    final handle = _availability.handle;
    final (hint, hintColor) = _availability.hint;
    final canClaim = _availability.formatOk && !_availability.unavailable;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your account doesn’t have a username yet, so people see a '
          'placeholder next to your calls. Pick one — it can’t be changed '
          'later.',
          style: AppTextStyles.textTheme.bodyMedium?.copyWith(
            color: AppColors.textPrimary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _handle,
          key: const ValueKey('claim-handle'),
          autocorrect: false,
          enabled: !busy,
          maxLength: 20,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
          ],
          onChanged: _availability.update,
          decoration: InputDecoration(
            labelText: 'Username',
            prefixText: '@',
            helperText: hint,
            helperStyle: TextStyle(color: hintColor),
            counterText: '',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('claim-handle-error'),
            style: const TextStyle(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 18),
        ChumbucketPrimaryButton(
          label: _availability.formatOk ? 'Claim @$handle' : 'Claim username',
          busy: busy,
          busyLabel: 'Claiming…',
          onPressed: canClaim ? _claim : null,
        ),
        ChumbucketTextAction(
          label: 'Not now',
          color: AppColors.textSecondary,
          onPressed: busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// Remembers, per account and device, that the claim was offered once.
abstract interface class HandlePromptMemory {
  Future<bool> wasOffered(String userId);
  Future<void> markOffered(String userId);
}

class PreferencesHandlePromptMemory implements HandlePromptMemory {
  const PreferencesHandlePromptMemory();

  static String _key(String userId) => 'chumbucket_handle_prompted_v1_$userId';

  @override
  Future<bool> wasOffered(String userId) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key(userId)) ==
          true;
    } catch (_) {
      // Unknown: do not nag. Profile still offers the claim.
      return true;
    }
  }

  @override
  Future<void> markOffered(String userId) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key(userId), true);
    } catch (_) {}
  }
}

/// Wraps the signed-in shell. The first time an account without a @username
/// is seen on this device, it is asked to claim one — once.
class UsernameClaimPrompt extends StatefulWidget {
  const UsernameClaimPrompt({
    super.key,
    required this.child,
    this.memory = const PreferencesHandlePromptMemory(),
  });

  final Widget child;
  final HandlePromptMemory memory;

  @override
  State<UsernameClaimPrompt> createState() => _UsernameClaimPromptState();
}

class _UsernameClaimPromptState extends State<UsernameClaimPrompt> {
  ChumbucketSession? _session;
  final Set<String> _considered = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<ChumbucketSession?>();
    if (identical(session, _session)) return;
    _session?.removeListener(_check);
    _session = session?..addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _session?.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    final session = _session;
    if (!mounted || session == null || !session.needsHandleClaim) return;
    final userId = session.userId!;
    if (!_considered.add(userId)) return;
    if (await widget.memory.wasOffered(userId)) return;
    if (!mounted || session.userId != userId || !session.needsHandleClaim) {
      return;
    }
    await widget.memory.markOffered(userId);
    if (!mounted) return;
    await showClaimHandleSheet(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
