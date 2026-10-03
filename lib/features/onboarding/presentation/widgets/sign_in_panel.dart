/// The ways in, for onboarding's sign-in steps (A1, B1, U1): identity's own
/// door buttons and "Last used" pill, identity's session calls, in the order
/// the onboarding spec asks for (§6 A1) — the method last used first and
/// filled; otherwise wallet first when a wallet app is installed, else
/// Google; with no wallet app the wallet door moves last and says why.
///
/// It owns the hand-off states: what the button says while the wallet or
/// browser is open, and an inline, announced error when it comes back
/// without a sign-in. Nothing here navigates; the flow moves on when the
/// session does.
library;

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/front_door_options.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';

/// Why a wallet hand-off came back without a signature, for analytics.
enum WalletDoorFailure {
  noWallet('no_wallet'),
  declined('declined'),
  noAnswer('timeout');

  const WalletDoorFailure(this.wire);
  final String wire;

  String get message => switch (this) {
    WalletDoorFailure.noWallet => OnboardingCopy.signInErrNoWallet,
    WalletDoorFailure.declined => OnboardingCopy.signInErrDeclined,
    WalletDoorFailure.noAnswer => OnboardingCopy.signInErrNoAnswer,
  };
}

/// One visit to the wallet: connect, then sign the Chumbucket sign-in
/// message (no transaction). Returns null when the session sign-in started,
/// or why it did not.
typedef WalletDoor =
    Future<WalletDoorFailure?> Function(
      BuildContext context, {
      required VoidCallback onSigned,
    });

/// The real wallet door, over identity's [MwaAuthProvider] and session.
Future<WalletDoorFailure?> mwaWalletDoor(
  BuildContext context, {
  required VoidCallback onSigned,
}) async {
  final auth = context.read<MwaAuthProvider>();
  final session = context.read<ChumbucketSession>();
  final wallets = context.read<MwaWalletProvider?>();
  if (!await auth.isWalletAvailable()) return WalletDoorFailure.noWallet;
  // An old app's wallet session (U1) is kept whatever happens here.
  final heldBefore = auth.isAuthenticated;
  final connected = await auth.authorize(
    signInMessageFor:
        (address) =>
            solanaSignInMessage(address: address, issuedAt: DateTime.now()),
  );
  if (!connected) {
    return auth.errorMessage == 'Authorization was cancelled or failed'
        ? WalletDoorFailure.declined
        : WalletDoorFailure.noAnswer;
  }
  final signed = auth.takeSignedSignIn();
  if (signed == null) {
    // Connected, but the sign-in message was not signed: "Nothing was
    // signed", so nothing is kept either. A wallet connection left behind
    // would read as an old app's profile on the next launch (U1).
    if (!heldBefore) await auth.forgetSession();
    return WalletDoorFailure.declined;
  }
  onSigned();
  unawaited(wallets?.initializeFromAuth(auth));
  await session.signInWithSignedMessage(
    signed.message,
    base64Url.encode(signed.signature),
  );
  return null;
}

Future<bool> _online() async {
  try {
    final result = await Connectivity().checkConnectivity();
    return !result.every((r) => r == ConnectivityResult.none);
  } catch (_) {
    return true;
  }
}

class OnboardingSignInPanel extends StatefulWidget {
  const OnboardingSignInPanel({
    super.key,
    this.walletDoor = mwaWalletDoor,
    this.isOnline = _online,
    this.walletAvailable,
    this.onStarted,
    this.onFailed,
    this.onBusyChanged,
    this.walletOnly = false,
    this.compact = false,
  });

  /// Onboarding's layout: the main way in as a full button, the others as
  /// round buttons under an "or", and no explanatory lines.
  final bool compact;

  final WalletDoor walletDoor;
  final Future<bool> Function() isOnline;

  /// Whether a wallet app is installed. Default: ask MWA.
  final Future<bool> Function()? walletAvailable;
  final void Function(SignInMethod method, bool lastUsed)? onStarted;
  final void Function(SignInMethod method, String reason)? onFailed;
  final ValueChanged<bool>? onBusyChanged;

  /// U1: only the wallet door (the carried-over account is a wallet's).
  final bool walletOnly;

  @override
  State<OnboardingSignInPanel> createState() => _OnboardingSignInPanelState();
}

enum _WalletPhase { idle, opening, checking }

class _OnboardingSignInPanelState extends State<OnboardingSignInPanel> {
  bool? _walletApp;
  bool _online = true;
  _WalletPhase _walletPhase = _WalletPhase.idle;
  SignInMethod? _social;
  String? _error;
  SessionStatus? _seenStatus;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final session = context.read<ChumbucketSession>();
      unawaited(session.loadEnabledProviders());
      unawaited(session.loadLastSignInMethod());
      final probe =
          widget.walletAvailable ??
          context.read<MwaAuthProvider?>()?.isWalletAvailable;
      final online = await widget.isOnline();
      final wallet = probe == null ? false : await probe();
      if (!mounted) return;
      setState(() {
        _online = online;
        _walletApp = wallet;
      });
    });
  }

  void _setBusy(bool busy) {
    if (_busy == busy) return;
    _busy = busy;
    widget.onBusyChanged?.call(busy);
  }

  Future<void> _wallet(bool lastUsed) async {
    if (_walletPhase != _WalletPhase.idle) return;
    widget.onStarted?.call(SignInMethod.wallet, lastUsed);
    onbAnnounce(context, OnboardingCopy.signInOpeningWalletA11y);
    setState(() {
      _error = null;
      _social = null;
      _walletPhase = _WalletPhase.opening;
    });
    _setBusy(true);
    try {
      final failure = await widget.walletDoor(
        context,
        onSigned: () {
          if (mounted) setState(() => _walletPhase = _WalletPhase.checking);
        },
      );
      if (!mounted) return;
      if (failure != null) {
        widget.onFailed?.call(SignInMethod.wallet, failure.wire);
        setState(() => _error = failure.message);
        onbAnnounce(context, failure.message);
        return;
      }
      _reportSessionFailure(SignInMethod.wallet);
    } catch (_) {
      if (!mounted) return;
      widget.onFailed?.call(SignInMethod.wallet, 'network');
      setState(() => _error = OnboardingCopy.signInErrNetwork);
    } finally {
      if (mounted) setState(() => _walletPhase = _WalletPhase.idle);
      _setBusy(false);
    }
  }

  void _startSocial(SignInMethod method, bool lastUsed) {
    final session = context.read<ChumbucketSession>();
    widget.onStarted?.call(method, lastUsed);
    onbAnnounce(context, OnboardingCopy.signInOpeningBrowserA11y);
    setState(() {
      _error = null;
      _social = method;
    });
    unawaited(
      method == SignInMethod.x
          ? session.signInWithX()
          : session.signInWithGoogle(),
    );
  }

  Future<void> _cancelSocial() async {
    setState(() => _social = null);
    await context.read<ChumbucketSession>().signOut();
  }

  /// The session came back refused or unreachable: say why, inline.
  void _reportSessionFailure(SignInMethod method) {
    final session = context.read<ChumbucketSession>();
    final error = session.error;
    if (session.status != SessionStatus.failed ||
        error == null ||
        error.isUnlinked) {
      return;
    }
    final (message, reason) =
        error.code == SessionErrorCode.oauthCancelled
            ? (OnboardingCopy.signInErrCancelled, 'cancelled')
            : error.isNetwork
            ? (OnboardingCopy.signInErrNetwork, 'network')
            : (error.message, 'refused');
    widget.onFailed?.call(method, reason);
    setState(() {
      _error = message;
      _social = null;
    });
    onbAnnounce(context, message);
  }

  List<SignInMethod> _order(ChumbucketSession session) {
    final providers = session.enabledProviders;
    final shown = <SignInMethod>[
      SignInMethod.wallet,
      if (!widget.walletOnly &&
          (providers == null || providers.contains('google')))
        SignInMethod.google,
      if (!widget.walletOnly && providers?.contains('x') == true)
        SignInMethod.x,
    ];
    final last = session.lastSignInMethod;
    final noWalletApp = _walletApp == false && !widget.walletOnly;
    final ordered = <SignInMethod>[
      if (last != null &&
          shown.contains(last) &&
          !(noWalletApp && last == SignInMethod.wallet))
        last,
      if (!noWalletApp) SignInMethod.wallet,
      SignInMethod.google,
      SignInMethod.x,
      SignInMethod.wallet,
    ];
    final out = <SignInMethod>[];
    for (final m in ordered) {
      if (shown.contains(m) && !out.contains(m)) out.add(m);
    }
    return out;
  }

  VoidCallback? _press(SignInMethod method, SignInMethod? last, bool busy) =>
      !_online || busy
          ? null
          : method == SignInMethod.wallet
          ? () => _wallet(method == last)
          : () => _startSocial(method, method == last);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession>();
    // A social sign-in that came back without one: report it once.
    if (_social != null &&
        session.status != _seenStatus &&
        session.status == SessionStatus.failed) {
      final method = _social!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportSessionFailure(method);
      });
    }
    _seenStatus = session.status;
    final socialBusy = _social != null && session.isBusy;
    final busy = socialBusy || _walletPhase != _WalletPhase.idle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setBusy(busy);
    });

    final order = _order(session);
    final last = session.lastSignInMethod;
    String busyLabel(SignInMethod method) {
      if (method == SignInMethod.wallet) {
        if (_walletPhase == _WalletPhase.checking) {
          return session.status == SessionStatus.identityPending
              ? OnboardingCopy.signInSettingUp
              : OnboardingCopy.signInWalletChecking;
        }
        return OnboardingCopy.signInWalletOpening;
      }
      return session.status == SessionStatus.identityPending
          ? OnboardingCopy.signInSettingUp
          : OnboardingCopy.signInWaiting;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_online)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: OnbIconLine(
                key: const ValueKey('sign-in-offline'),
                icon: 'cloud-off-outline',
                text: OnboardingCopy.signInOffline,
                color: AppColors.onWarningContainer,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('sign-in-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: OnbText.small.copyWith(
                    color: AppColors.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
        if (widget.compact && order.isNotEmpty) ...[
          FrontDoorButton(
            method: order.first,
            primary: true,
            lastUsed: order.first == last,
            busy:
                order.first == SignInMethod.wallet
                    ? _walletPhase != _WalletPhase.idle
                    : socialBusy && _social == order.first,
            busyLabel: busyLabel(order.first),
            subtitle:
                order.first == SignInMethod.wallet &&
                        _walletApp == false &&
                        !widget.walletOnly
                    ? OnboardingCopy.signInNoWallet
                    : null,
            onPressed: _press(order.first, last, busy),
          ),
          if (order.length > 1) ...[
            const SizedBox(height: 18),
            const _OrRule(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i < order.length; i++) ...[
                  if (i > 1) const SizedBox(width: 20),
                  FrontDoorCircleButton(
                    method: order[i],
                    lastUsed: order[i] == last,
                    busy: socialBusy && _social == order[i],
                    onPressed: _press(order[i], last, busy),
                  ),
                ],
              ],
            ),
          ],
        ] else
          for (var i = 0; i < order.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            FrontDoorButton(
              method: order[i],
              primary: i == 0,
              lastUsed: order[i] == last,
              busy:
                  order[i] == SignInMethod.wallet
                      ? _walletPhase != _WalletPhase.idle
                      : socialBusy && _social == order[i],
              busyLabel: busyLabel(order[i]),
              subtitle:
                  order[i] == SignInMethod.wallet &&
                          _walletApp == false &&
                          !widget.walletOnly
                      ? OnboardingCopy.signInNoWallet
                      : null,
              onPressed:
                  !_online || busy
                      ? null
                      : switch (order[i]) {
                        SignInMethod.wallet => () => _wallet(order[i] == last),
                        final method =>
                          () => _startSocial(method, method == last),
                      },
            ),
          ],
        if (socialBusy && session.status == SessionStatus.signingIn)
          OnbTextAction(
            key: const ValueKey('sign-in-cancel'),
            label: 'Use a different way in',
            color: AppColors.textMuted,
            onPressed: _cancelSocial,
          ),
        if (!widget.compact && order.contains(SignInMethod.wallet)) ...[
          const SizedBox(height: 14),
          Text(
            OnboardingCopy.signInWalletLine,
            textAlign: TextAlign.center,
            style: OnbText.meta,
          ),
        ],
      ],
    );
  }
}

/// "or" between the main way in and the round ones.
class _OrRule extends StatelessWidget {
  const _OrRule();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: OnbText.meta),
        ),
        const Expanded(child: Divider(color: AppColors.divider, height: 1)),
      ],
    ),
  );
}
