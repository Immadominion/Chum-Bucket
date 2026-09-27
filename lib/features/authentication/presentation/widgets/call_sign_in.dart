import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every call entry point (including a deep link) has the same way to sign in.
/// The sheet leaves the underlying call/market in place after authentication.
void requestCallSignIn(BuildContext context, {VoidCallback? onRequested}) {
  if (onRequested != null) {
    onRequested();
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder:
        (_) => const Padding(
          padding: EdgeInsets.all(24),
          child: SingleChildScrollView(child: CallSessionPanel()),
        ),
  );
}

class CallSessionPanel extends StatefulWidget {
  const CallSessionPanel({super.key});

  @override
  State<CallSessionPanel> createState() => _CallSessionPanelState();
}

class _CallSessionPanelState extends State<CallSessionPanel> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _needsProfile = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    if (session.error?.isUnlinked == true) _needsProfile = true;
    if (!session.hasSupabaseSession || session.isReady) _needsProfile = false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          session.isReady
              ? 'You’re on record'
              : 'Put your name behind your call',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Follow people, Back or Fade a call, and keep the receipts. '
          'No wallet or deposit needed.',
        ),
        const SizedBox(height: 24),
        if (session.error != null && !session.error!.isUnlinked) ...[
          Text(session.error!.message),
          const SizedBox(height: 16),
        ],
        if (session.isBusy)
          const Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Finishing sign-in…'),
            ],
          )
        else if (session.isReady)
          const Text('Signed in. Your calls use your Chumbucket profile.')
        else if (session.hasSupabaseSession && _needsProfile)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Public name'),
                  validator:
                      (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Choose the name people will see on your calls.'
                              : RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)
                              ? 'Use a name without control characters.'
                              : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This creates a new social profile. It does not move funds '
                  'or merge an existing wallet account.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (_form.currentState!.validate()) {
                      session.completeProfile(_name.text);
                    }
                  },
                  child: const Text('Create my profile'),
                ),
              ],
            ),
          )
        else if (session.hasSupabaseSession)
          FilledButton(
            onPressed: session.retryIdentity,
            child: const Text('Retry account setup'),
          )
        else
          FilledButton(
            onPressed: session.signInWithGoogle,
            child: const Text('Continue with Google'),
          ),
        if (session.hasSupabaseSession && !session.isBusy)
          TextButton(onPressed: session.signOut, child: const Text('Sign out')),
      ],
    );
  }
}
