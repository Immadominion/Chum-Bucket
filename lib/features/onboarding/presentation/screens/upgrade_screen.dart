/// U1 "Chumbucket is now about calls" (onboarding spec §7), for a person
/// with a wallet profile from the old app on their first launch of this one.
/// One wallet signature reaches the same profile (carried over); nothing here
/// can create a second account. If the server is not carrying wallet
/// profiles over right now, it says so and goes Home with nothing changed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/sign_in_panel.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key, this.walletDoor = mwaWalletDoor});

  final WalletDoor walletDoor;

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _busy = false;
  String? _error;
  String? _closed;

  Future<void> _continue() async {
    final flow = context.read<OnboardingFlowController>();
    final session = context.read<ChumbucketSession>();
    setState(() {
      _busy = true;
      _error = null;
    });
    flow.setBusy(true);
    flow.signInStarted(
      SignInMethod.wallet,
      lastUsed: session.lastSignInMethod == SignInMethod.wallet,
    );
    try {
      // Only when the server carries a wallet's profile over: otherwise a
      // signature here would start a new, empty account.
      final status = await session.checkIdentityStatus();
      if (!mounted) return;
      if (status == null ||
          !status.walletSignIn ||
          !status.walletProfileCarry) {
        setState(() => _closed = kExistingAccountLinkClosed);
        return;
      }
      final failure = await widget.walletDoor(context, onSigned: () {});
      if (!mounted) return;
      if (failure != null) {
        flow.signInFailed(SignInMethod.wallet, failure.wire);
        setState(() => _error = failure.message);
        return;
      }
      if (session.needsUsername) {
        // No profile came across for this wallet: never make one here.
        await session.signOut();
        if (mounted) setState(() => _closed = kExistingAccountLinkClosed);
        return;
      }
      final error = session.error;
      if (!session.isReady && error != null) {
        flow.signInFailed(
          SignInMethod.wallet,
          error.isNetwork ? 'network' : 'refused',
        );
        setState(
          () =>
              _error =
                  error.isNetwork
                      ? OnboardingCopy.signInErrNetwork
                      : error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      flow.setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final closed = _closed;
    return OnboardingScaffold(
      announce: OnboardingCopy.upgradeTitle,
      busy: _busy,
      header: const OnboardingBrandBand(artwork: ChumbucketStateArtwork.people),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      actions: [
        if (closed == null) ...[
          ChumbucketPrimaryButton(
            key: const ValueKey('upgrade-continue'),
            label: OnboardingCopy.upgradeCta,
            busy: _busy,
            busyLabel: OnboardingCopy.signInWalletOpening,
            onPressed: _busy ? null : _continue,
          ),
          const SizedBox(height: 4),
          OnbTextAction(
            key: const ValueKey('upgrade-not-now'),
            label: OnboardingCopy.upgradeLater,
            color: AppColors.textMuted,
            onPressed: _busy ? null : () => unawaited(flow.lookAround()),
          ),
        ] else
          ChumbucketPrimaryButton(
            key: const ValueKey('upgrade-home'),
            label: OnboardingCopy.recordDone,
            onPressed: () => unawaited(flow.lookAround(outcome: 'link_closed')),
          ),
      ],
      children: [
        const OnbTitle(OnboardingCopy.upgradeTitle),
        const SizedBox(height: 8),
        const OnbBody(OnboardingCopy.upgradeBody),
        const SizedBox(height: 20),
        OnbSurface(
          child: OnbIconLine(
            icon: 'shield-outline',
            text: OnboardingCopy.upgradeSafe,
            color: AppColors.textPrimary,
            style: OnbText.bodyInk,
          ),
        ),
        const SizedBox(height: 24),
        const HowItWorksList(),
        const SizedBox(height: 20),
        Text(
          OnboardingCopy.signInWalletLine,
          textAlign: TextAlign.center,
          style: OnbText.meta,
        ),
        if (_error != null || closed != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('upgrade-message'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    closed != null
                        ? const Color(0xFFECEFF2)
                        : AppColors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                closed ?? _error!,
                style: OnbText.small.copyWith(
                  color:
                      closed != null
                          ? const Color(0xFF525D6E)
                          : AppColors.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
