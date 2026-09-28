import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every call entry point (including a deep link) has the same way to sign in.
/// The sheet leaves the underlying call/market in place after authentication.
void requestCallSignIn(BuildContext context, {VoidCallback? onRequested}) {
  if (onRequested != null) {
    onRequested();
    return;
  }
  showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => const ChumbucketWavySheet(
          title: 'Sign in to call',
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: CallSessionPanel(),
          ),
        ),
  );
}

class CallSessionPanel extends StatelessWidget {
  const CallSessionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    final unlinked =
        session.hasSupabaseSession && session.error?.isUnlinked == true;
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
          'Back or Fade a call and keep the receipts. '
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
        else if (unlinked)
          const Text(
            'Google sign-in succeeded, but this account is not linked to a '
            'Chumbucket profile. Account linking is not available in this '
            'preview yet. Your existing profile, wallet and history are '
            'unchanged. Close this sheet to keep browsing.',
          )
        else if (session.hasSupabaseSession)
          ChallengeButton(
            createNewChallenge: session.retryIdentity,
            label: 'Retry sign-in',
          )
        else
          ChallengeButton(
            createNewChallenge: session.signInWithGoogle,
            label: 'Continue with Google',
          ),
        if (session.hasSupabaseSession && !session.isBusy)
          TextButton(onPressed: session.signOut, child: const Text('Sign out')),
      ],
    );
  }
}
