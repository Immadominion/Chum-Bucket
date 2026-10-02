import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// What every entry point says while the server is not accepting links from
/// existing (wallet) profiles to Google.
const kExistingAccountLinkClosed =
    'Linking Google to an existing profile isn’t open yet. Your profile, '
    'friends and challenges are unchanged.';

/// Every entry point (a call, a market, Activity, Profile, a deep link) opens
/// the same sheet: one Chumbucket account, reached with a wallet, Google or X.
/// The first time, the person claims a @username. The sheet leaves the
/// underlying call/market in place after sign-in.
void requestCallSignIn(BuildContext context, {VoidCallback? onRequested}) {
  if (onRequested != null) {
    onRequested();
    return;
  }
  showChumbucketWavySheet<void>(
    context: context,
    builder: (_) => const ChumbucketSignInSheet(),
  );
}

class ChumbucketSignInSheet extends StatelessWidget {
  const ChumbucketSignInSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    final (title, subtitle) =
        session.isReady
            ? ('You’re in', null)
            : session.needsUsername
            ? (
              'Claim your username',
              'One name for your calls, friends and receipts.',
            )
            : (
              'Sign in',
              'One Chumbucket account. Use your wallet, Google or X.',
            );
    return ChumbucketWavySheet(
      title: title,
      subtitle: subtitle,
      canDismiss: !session.isBusy,
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: CallSessionPanel(),
      ),
    );
  }
}

class CallSessionPanel extends StatefulWidget {
  const CallSessionPanel({super.key});

  @override
  State<CallSessionPanel> createState() => _CallSessionPanelState();
}

class _CallSessionPanelState extends State<CallSessionPanel> {
  @override
  void initState() {
    super.initState();
    // Offer only the providers this project has switched on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChumbucketSession>().loadEnabledProviders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    final wallet = context.watch<MwaAuthProvider?>();
    final providers = session.enabledProviders;
    final error = session.error;

    if (session.isBusy) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            session.status == SessionStatus.signingIn
                ? 'Waiting for your sign-in…'
                : 'Setting up your account…',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (session.isReady) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'You’re on record',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Signed in. Your calls use your Chumbucket profile.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ChumbucketPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          TextButton(
            onPressed: () => signOutOfChumbucket(context),
            child: const Text('Sign out'),
          ),
        ],
      );
    }

    if (session.needsUsername) {
      return const ClaimUsernameForm();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null && !error.isUnlinked) ...[
          Text(
            error.message,
            key: const ValueKey('sign-in-error'),
            style: const TextStyle(color: AppColors.error),
          ),
          const SizedBox(height: 16),
        ],
        if (wallet != null) ...[
          ChumbucketPrimaryButton(
            label: 'Continue with wallet',
            onPressed:
                () => session.signInWithWallet(MwaSolanaSignInWallet(wallet)),
          ),
          const SizedBox(height: 10),
        ],
        // Unknown provider settings still offer Google, which is on today.
        if (providers == null || providers.contains('google')) ...[
          _SecondarySignIn(
            label: 'Continue with Google',
            onPressed: session.signInWithGoogle,
          ),
          const SizedBox(height: 10),
        ],
        if (providers?.contains('x') == true) ...[
          _SecondarySignIn(
            label: 'Continue with X',
            onPressed: session.signInWithX,
          ),
          const SizedBox(height: 10),
        ],
        if (wallet != null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Your wallet signs a message, not a transaction: it costs '
              'nothing and moves nothing.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        if (session.hasSupabaseSession)
          TextButton(
            onPressed: () => signOutOfChumbucket(context),
            child: const Text('Sign out'),
          ),
      ],
    );
  }
}

class _SecondarySignIn extends StatelessWidget {
  const _SecondarySignIn({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, ChumbucketPrimaryButton.height),
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.outlineVariant, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ChumbucketPrimaryButton.radius),
      ),
    ),
    child: Text(
      label,
      style: AppTextStyles.sheetAction.copyWith(color: AppColors.textPrimary),
    ),
  );
}

/// Name and @username for a new account, with the username checked as it is
/// typed. The server decides; this only saves a round trip.
class ClaimUsernameForm extends StatefulWidget {
  const ClaimUsernameForm({super.key});

  @override
  State<ClaimUsernameForm> createState() => _ClaimUsernameFormState();
}

class _ClaimUsernameFormState extends State<ClaimUsernameForm> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  Timer? _debounce;
  String _checked = '';
  UsernameStatus? _status;
  bool _checking = false;

  static final _format = RegExp(r'^[a-z0-9_]{3,20}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    super.dispose();
  }

  void _onHandleChanged(String value) {
    _debounce?.cancel();
    final handle = value.trim().toLowerCase();
    setState(() {
      _status = null;
      _checking = _format.hasMatch(handle);
    });
    if (!_format.hasMatch(handle)) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final status = await context.read<ChumbucketSession>().usernameStatus(
        handle,
      );
      if (!mounted || _handle.text.trim().toLowerCase() != handle) return;
      setState(() {
        _checked = handle;
        _status = status;
        _checking = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    final handle = _handle.text.trim().toLowerCase();
    final name = _name.text.trim();
    final formatOk = _format.hasMatch(handle);
    final checkedHere = _checked == handle;
    final (hint, hintColor) = switch ((
      formatOk,
      checkedHere ? _status : null,
    )) {
      (false, _) when handle.isEmpty => (null, null),
      (false, _) => ('3–20 letters, numbers or _', AppColors.textSecondary),
      (true, UsernameStatus.available) => (
        '@$handle is yours to claim',
        AppColors.success,
      ),
      (true, UsernameStatus.taken) => ('@$handle is taken', AppColors.error),
      (true, UsernameStatus.reserved) => (
        '@$handle is reserved',
        AppColors.error,
      ),
      (true, UsernameStatus.invalid) => (
        '3–20 letters, numbers or _',
        AppColors.error,
      ),
      _ => (_checking ? 'Checking @$handle…' : null, AppColors.textSecondary),
    };
    final unavailable =
        checkedHere &&
        (_status == UsernameStatus.taken || _status == UsernameStatus.reserved);
    final canClaim =
        formatOk && !unavailable && name.isNotEmpty && name.length <= 60;
    final error = session.error;
    // Someone whose wallet is connected but who signed in another way may
    // already have a profile at that wallet: say so before a second one exists.
    final wallet = context.watch<MwaAuthProvider?>();
    final walletElsewhere =
        wallet?.isAuthenticated == true && !session.isWalletSession;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (walletElsewhere) ...[
          Container(
            key: const ValueKey('claim-wallet-hint'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECEFF2),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Text(
              'Already have a Chumbucket profile on this wallet? Sign in with '
              'your wallet instead to keep it. Claiming here starts a new one.',
              style: TextStyle(fontSize: 13, color: Color(0xFF525D6E)),
            ),
          ),
          TextButton(
            // Ends only this Google/X session; the wallet stays connected.
            onPressed: () async {
              await session.signOut();
              await session.signInWithWallet(MwaSolanaSignInWallet(wallet!));
            },
            child: const Text('Sign in with wallet instead'),
          ),
          const SizedBox(height: 4),
        ],
        TextField(
          controller: _handle,
          key: const ValueKey('claim-username'),
          autocorrect: false,
          maxLength: 20,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
          ],
          onChanged: _onHandleChanged,
          decoration: InputDecoration(
            labelText: 'Username',
            prefixText: '@',
            helperText: hint,
            helperStyle: TextStyle(color: hintColor),
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          key: const ValueKey('claim-name'),
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'How you appear next to your calls.',
            counterText: '',
          ),
        ),
        if (error != null && !error.isUnlinked) ...[
          const SizedBox(height: 12),
          Text(
            error.message,
            key: const ValueKey('claim-error'),
            style: const TextStyle(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 18),
        ChumbucketPrimaryButton(
          label: formatOk ? 'Claim @$handle' : 'Claim username',
          onPressed:
              canClaim
                  ? () => session.completeProfile(name, handle: handle)
                  : null,
        ),
        TextButton(
          onPressed: session.signOut,
          child: const Text('Use a different sign-in'),
        ),
      ],
    );
  }
}
