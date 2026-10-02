/// The three ways in — wallet, Google, X — on the first screen.
///
/// One Chumbucket account whichever is used (the server resolves every
/// sign-in to the same canonical person). The option this device last used
/// carries a "Last used" badge and the primary style, as on web sign-in pages.
/// X appears only when the project has it switched on.
///
/// Google and X finish in the system browser and come back through the
/// `login-callback` deep link. A first sign-in with no account claims a
/// @username here, before anything is created; then the person is taken in.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

import 'mwa_connect_button.dart';

class FrontDoorOptions extends StatefulWidget {
  const FrontDoorOptions({super.key, this.onEntered, this.connectWallet});

  /// Where an account that is ready goes. Default: Home, replacing the stack.
  final void Function(BuildContext context)? onEntered;

  /// The wallet door. Default: [connectWalletAndEnter] (which goes Home itself).
  final Future<bool> Function(BuildContext context)? connectWallet;

  @override
  State<FrontDoorOptions> createState() => _FrontDoorOptionsState();
}

class _FrontDoorOptionsState extends State<FrontDoorOptions> {
  ChumbucketSession? _session;
  bool _socialStarted = false;
  bool _walletBusy = false;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<ChumbucketSession?>();
    if (identical(session, _session)) return;
    _session?.removeListener(_onSession);
    _session = session?..addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      session?.loadEnabledProviders();
      session?.loadLastSignInMethod();
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final session = _session;
    if (!mounted || session == null || _entered) return;
    if (_socialStarted && session.isReady) {
      _entered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (widget.onEntered ?? _goHome)(context);
      });
    }
  }

  static void _goHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _social(Future<void> Function() start) {
    setState(() => _socialStarted = true);
    unawaited(start());
  }

  Future<void> _wallet() async {
    if (_walletBusy) return;
    setState(() => _walletBusy = true);
    try {
      await (widget.connectWallet ?? connectWalletAndEnter)(context);
    } finally {
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  Future<void> _cancelSocial() async {
    setState(() => _socialStarted = false);
    await _session?.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession?>();
    // No account surface in this build: the wallet door alone.
    if (session == null) return const MwaConnectButton();

    if (_socialStarted && session.needsUsername) {
      return _ClaimFirstUsername(onCancel: _cancelSocial);
    }
    if (_socialStarted && (session.isBusy || session.isReady)) {
      return _Waiting(
        label:
            session.status == SessionStatus.signingIn
                ? 'Finish signing in in your browser…'
                : 'Setting up your account…',
        onCancel:
            session.status == SessionStatus.signingIn ? _cancelSocial : null,
      );
    }

    final walletState = context.watch<MwaAuthProvider?>()?.state;
    final walletBusy = _walletBusy || walletState == MwaAuthState.loading;
    final providers = session.enabledProviders;
    final last = session.lastSignInMethod;
    final shown = <SignInMethod>[
      SignInMethod.wallet,
      // Unknown provider settings still offer Google, which is on today.
      if (providers == null || providers.contains('google'))
        SignInMethod.google,
      if (providers?.contains('x') == true) SignInMethod.x,
    ];
    final primary =
        last != null && shown.contains(last) ? last : SignInMethod.wallet;
    final error = _socialStarted ? session.error : null;
    final busy = walletBusy || session.isBusy;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null && !error.isUnlinked) ...[
          Text(
            error.message,
            key: const ValueKey('front-door-error'),
            textAlign: TextAlign.center,
            style: AppTextStyles.textTheme.bodyMedium?.copyWith(
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final method in shown) ...[
          FrontDoorButton(
            method: method,
            primary: method == primary,
            lastUsed: method == last,
            busy: method == SignInMethod.wallet && walletBusy,
            onPressed:
                busy
                    ? null
                    : switch (method) {
                      SignInMethod.wallet => _wallet,
                      SignInMethod.google =>
                        () => _social(session.signInWithGoogle),
                      SignInMethod.x => () => _social(session.signInWithX),
                    },
          ),
          const SizedBox(height: 14),
        ],
        Text(
          'Your wallet signs a message, not a transaction — it costs nothing. '
          'With Google or X you need no wallet; you can make one on this '
          'phone later if you want to trade.',
          textAlign: TextAlign.center,
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// One way in: the primary (filled) style for the method this phone used
/// last, outlined otherwise, with the "Last used" pill straddling its top
/// edge. Shared by the front door and onboarding's sign-in steps.
class FrontDoorButton extends StatelessWidget {
  const FrontDoorButton({
    super.key,
    required this.method,
    required this.primary,
    required this.lastUsed,
    required this.busy,
    required this.onPressed,
    this.busyLabel,
    this.subtitle,
  });

  final SignInMethod method;
  final bool primary;
  final bool lastUsed;
  final bool busy;
  final VoidCallback? onPressed;

  /// What the button says while busy. Default: "Opening your wallet…".
  final String? busyLabel;

  /// A line under the button (e.g. why the wallet door needs a wallet app).
  final String? subtitle;

  /// How far the "Last used" pill reaches into the button: less than either
  /// button style's 12dp vertical padding.
  static const _badgeOverlap = 8.0;

  String get label => switch (method) {
    SignInMethod.wallet => 'Continue with wallet',
    SignInMethod.google => 'Continue with Google',
    SignInMethod.x => 'Continue with X',
  };

  Widget _icon(Color color) => switch (method) {
    SignInMethod.wallet => BasilIcon('wallet-outline', size: 20, color: color),
    SignInMethod.google => BasilIcon('google-outline', size: 20, color: color),
    // X's mark is a letter; the old bird would be wrong.
    SignInMethod.x => Text(
      'X',
      style: AppTextStyles.pageTitle.copyWith(
        fontSize: 18,
        height: 1,
        color: color,
      ),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final core =
        primary
            ? ChumbucketPrimaryButton(
              key: ValueKey('front-door-${method.wire}'),
              label: label,
              busy: busy,
              busyLabel: busyLabel ?? 'Opening your wallet…',
              leading: _icon(Colors.white),
              onPressed: onPressed,
            )
            : _OutlinedOption(
              key: ValueKey('front-door-${method.wire}'),
              label: label,
              busyLabel: busyLabel,
              icon: _icon(AppColors.textPrimary),
              busy: busy,
              onPressed: onPressed,
            );
    final note = subtitle;
    final button =
        note == null
            ? core
            : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                core,
                const SizedBox(height: 6),
                Text(
                  note,
                  key: ValueKey('front-door-${method.wire}-note'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            );
    if (!lastUsed) return button;
    // The pill straddles the button's top edge, as on web sign-in pages. Its
    // height follows the text size and the button sits below it, so the two
    // overlap by exactly [_badgeOverlap] — inside the button's own 12dp top
    // padding, which means the pill can never cover the label, even at 2x.
    final pillHeight =
        MediaQuery.textScalerOf(context).scale(12) * 1.2 + 10; // + 3+2 each
    return Semantics(
      hint: 'Last used on this phone',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(top: pillHeight - _badgeOverlap),
            child: button,
          ),
          Positioned(
            top: 0,
            right: 16,
            child: ExcludeSemantics(
              child: Container(
                key: const ValueKey('front-door-last-used'),
                height: pillHeight,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  'Last used',
                  maxLines: 1,
                  style: AppTextStyles.sheetCaption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedOption extends StatelessWidget {
  const _OutlinedOption({
    super.key,
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    this.busyLabel,
  });

  final String label;
  final String? busyLabel;
  final Widget icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: busy ? (busyLabel ?? label) : label,
    excludeSemantics: true,
    child: Opacity(
      opacity: onPressed == null && !busy ? .5 : 1,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChumbucketPrimaryButton.radius),
          side: const BorderSide(color: AppColors.outline, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ChumbucketPrimaryButton.height,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    icon,
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      busy ? (busyLabel ?? label) : label,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.sheetAction.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.label, this.onCancel});
  final String label;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      const SizedBox(height: 16),
      Text(
        label,
        key: const ValueKey('front-door-waiting'),
        textAlign: TextAlign.center,
        style: AppTextStyles.textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
        ),
      ),
      if (onCancel != null)
        ChumbucketTextAction(
          label: 'Use a different way in',
          color: AppColors.textSecondary,
          onPressed: onCancel,
        ),
    ],
  );
}

class _ClaimFirstUsername extends StatelessWidget {
  const _ClaimFirstUsername({required this.onCancel});
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Claim your username',
        style: AppTextStyles.textTheme.headlineSmall?.copyWith(fontSize: 22),
      ),
      const SizedBox(height: 6),
      Text(
        'One name for your calls, friends and receipts.',
        style: AppTextStyles.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 12),
      ClaimUsernameForm(onUseDifferentSignIn: onCancel),
    ],
  );
}
