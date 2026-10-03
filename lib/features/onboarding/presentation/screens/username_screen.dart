/// A2 "Claim your @username" (a new account) and A2c "Pick your @username"
/// (a profile carried over from the old app) — onboarding spec §6.
///
/// Uses identity's availability check, claim calls and copy, laid out as a
/// full step so Claim sits in the sticky area above the keyboard. A
/// suggestion from what the person already gave us (X username, wallet name,
/// Google name) is prefilled only when the server says it is available, and
/// never claimed without a tap. A carried-over profile never sees an empty
/// Name field that could overwrite its name.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/username_availability.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/username_suggestions.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/trust/data/content_policy.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

/// The wallet's .sol/.skr name, if it has one. Injectable for tests.
typedef WalletDomainLookup = Future<String?> Function(String address);

Future<String?> _resolveDomain(String address) async {
  try {
    final name = await AddressNameResolver.resolveDisplayName(address);
    return name.contains('...') || name == address ? null : name;
  } catch (_) {
    return null;
  }
}

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key, this.domainLookup = _resolveDomain});

  final WalletDomainLookup domainLookup;

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _handle = TextEditingController();
  final _name = TextEditingController();
  final _handleFocus = FocusNode();
  late final UsernameAvailability _availability;
  UsernameSuggestion? _suggestion;
  String? _error;
  bool _claiming = false;
  int _attempts = 0;
  late final bool _newAccount;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    final session = context.read<ChumbucketSession>();
    _newAccount = session.needsUsername;
    _availability = UsernameAvailability(session.usernameStatus)
      ..addListener(_changed);
    if (_newAccount) {
      final name = nameSuggestion(session.profileHints);
      if (name != null) _name.text = name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prefill());
      if (!_newAccount) unawaited(_loadDisplayName());
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _availability.dispose();
    _handle.dispose();
    _name.dispose();
    _handleFocus.dispose();
    super.dispose();
  }

  Future<void> _loadDisplayName() async {
    final session = context.read<ChumbucketSession>();
    final calls = context.read<CallsProvider>();
    final userId = session.userId;
    if (userId == null) return;
    final person = await calls.loadPerson(userId);
    if (!mounted) return;
    final name = person?.person.displayName;
    // A placeholder (`user-80d78065`) is never shown as anyone's name.
    setState(
      () => _displayName = name == null ? null : visibleDisplayName(name),
    );
  }

  Future<void> _prefill() async {
    final session = context.read<ChumbucketSession>();
    final wallet =
        session.signInWallet ?? context.read<MwaAuthProvider?>()?.walletAddress;
    final domain =
        context.read<MwaAuthProvider?>()?.snsDomain ??
        (wallet == null ? null : await widget.domainLookup(wallet));
    final candidates = usernameCandidates(
      hints: session.profileHints,
      walletDomain: domain,
    );
    for (final candidate in candidates) {
      if (!mounted || _handle.text.isNotEmpty) return;
      final status = await session.usernameStatus(candidate.handle);
      if (!mounted || _handle.text.isNotEmpty) return;
      if (status == UsernameStatus.available) {
        _handle.text = candidate.handle;
        _availability.update(candidate.handle);
        setState(() => _suggestion = candidate);
        return;
      }
    }
  }

  String? get _suggestionLabel {
    final s = _suggestion;
    if (s == null || s.handle != _availability.handle) return null;
    return switch (s.source) {
      UsernameSuggestionSource.x => OnboardingCopy.usernameSuggestedX,
      UsernameSuggestionSource.domain => OnboardingCopy.usernameSuggestedDomain(
        s.domain ?? '',
      ),
      UsernameSuggestionSource.google => OnboardingCopy.usernameSuggestedGoogle,
    };
  }

  bool get _canClaim {
    if (_claiming) return false;
    if (!_availability.formatOk || _availability.unavailable) return false;
    if (_newAccount) {
      final name = _name.text.trim();
      return name.isNotEmpty && name.length <= 60;
    }
    return true;
  }

  Future<void> _claim() async {
    if (!_canClaim) return;
    final session = context.read<ChumbucketSession>();
    final flow = context.read<OnboardingFlowController>();
    final handle = _availability.handle;
    // Trust's content policy, answered at once; the server applies the same
    // rule and has the last word.
    final problem =
        contentPolicyProblem(handle, ContentField.handle) ??
        (_newAccount
            ? contentPolicyProblem(_name.text, ContentField.name)
            : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final calls = context.read<CallsProvider>();
    setState(() {
      _claiming = true;
      _error = null;
    });
    // Back (system or arrow) waits while the claim is in flight: on A2 it
    // would otherwise abandon the sign-in mid-claim.
    flow.setBusy(true);
    _attempts++;
    String? error;
    try {
      if (_newAccount) {
        await session.completeProfile(_name.text.trim(), handle: handle);
        if (!session.isReady) {
          final failure = session.error;
          error =
              failure == null
                  ? OnboardingCopy.usernameNetwork
                  : failure.isNetwork
                  ? OnboardingCopy.usernameNetwork
                  : failure.message;
        }
      } else {
        final failure = await session.claimUsername(handle);
        if (failure != null && failure.code != 'HANDLE_ALREADY_SET') {
          error =
              failure.isNetwork
                  ? OnboardingCopy.usernameNetwork
                  : failure.message;
        }
      }
    } finally {
      flow.setBusy(false);
    }
    if (error == null) {
      // Recorded even if the run has already moved on from this screen.
      final used = _suggestion != null && _suggestion!.handle == handle;
      flow.app.track(
        OnboardingAnalyticsEvents.usernameClaimed(
          path: _newAccount ? 'new' : 'carried_over',
          usedSuggestion: used,
          suggestionSource: used ? _suggestion!.source.wire : 'none',
          attempts: _attempts,
        ),
      );
      // The person's name and @handle show on their calls straight away.
      final userId = session.userId;
      if (userId != null) unawaited(calls.loadPerson(userId, force: true));
    }
    if (!mounted) return;
    setState(() {
      _claiming = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final session = context.watch<ChumbucketSession>();
    final (hint, hintColor) = _availability.hint;
    final handle = _availability.formatOk ? _availability.handle : null;
    final wallet = context.watch<MwaAuthProvider?>();
    final walletElsewhere =
        _newAccount &&
        wallet?.isAuthenticated == true &&
        !session.isWalletSession;
    final title =
        _newAccount
            ? OnboardingCopy.usernameTitle
            : OnboardingCopy.usernameCTitle;
    final busy = _claiming || session.isClaimingHandle || session.isBusy;

    return OnboardingScaffold(
      onBack: flow.canGoBack && !busy ? flow.back : null,
      busy: busy,
      progress: flow.progress,
      announce: title,
      actions: [
        ChumbucketPrimaryButton(
          key: const ValueKey('username-claim'),
          label: OnboardingCopy.usernameClaim(handle),
          busy: busy,
          busyLabel: OnboardingCopy.usernameClaiming,
          onPressed: _canClaim ? _claim : null,
        ),
        const SizedBox(height: 4),
        if (_newAccount)
          OnbTextAction(
            key: const ValueKey('username-different-sign-in'),
            label: OnboardingCopy.usernameDifferentSignIn,
            color: AppColors.textMuted,
            onPressed: busy ? null : () => unawaited(flow.switchSignIn()),
          )
        else
          OnbTextAction(
            key: const ValueKey('username-later'),
            label: OnboardingCopy.usernameCLater,
            color: AppColors.textMuted,
            onPressed: busy ? null : () => unawaited(flow.claimLater()),
          ),
      ],
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: ChumbucketStateArt.compact(ChumbucketStateArtwork.record),
        ),
        const SizedBox(height: 12),
        OnbTitle(title),
        const SizedBox(height: 8),
        OnbBody(
          _newAccount
              ? OnboardingCopy.usernameSubtitle
              : OnboardingCopy.usernameCBody(_displayName),
        ),
        if (walletElsewhere) ...[
          const SizedBox(height: 16),
          OnbSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Already have a Chumbucket profile on this wallet? Sign in '
                  'with your wallet instead to keep it. Claiming here starts '
                  'a new one.',
                  key: const ValueKey('username-wallet-hint'),
                  style: OnbText.small.copyWith(color: AppColors.textPrimary),
                ),
                OnbTextAction(
                  label: 'Sign in with wallet instead',
                  onPressed:
                      busy
                          ? null
                          : () async {
                            await session.signOut();
                            await session.signInWithWallet(
                              MwaSolanaSignInWallet(wallet!),
                            );
                          },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _handle,
          focusNode: _handleFocus,
          key: const ValueKey('username-field'),
          autocorrect: false,
          enabled: !busy,
          maxLength: 20,
          textInputAction:
              _newAccount ? TextInputAction.next : TextInputAction.done,
          onSubmitted: (_) => _newAccount ? null : _claim(),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
          ],
          onChanged: _availability.update,
          style: OnbText.bodyInk,
          decoration: _decoration(
            label: OnboardingCopy.usernameLabel,
            prefix: '@',
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              hint ?? _suggestionLabel ?? ' ',
              key: const ValueKey('username-hint'),
              style: OnbText.small.copyWith(color: _hintColor(hintColor)),
            ),
          ),
        ),
        if (_suggestionLabel != null && hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Text(
              _suggestionLabel!,
              key: const ValueKey('username-suggested'),
              style: OnbText.meta,
            ),
          ),
        if (_newAccount) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            key: const ValueKey('username-name'),
            enabled: !busy,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _claim(),
            onChanged: (_) => setState(() {}),
            style: OnbText.bodyInk,
            decoration: _decoration(label: OnboardingCopy.nameLabel),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(OnboardingCopy.nameHelper, style: OnbText.small),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('username-error'),
              style: OnbText.small.copyWith(color: AppColors.onErrorContainer),
            ),
          ),
        ],
        if (_newAccount) ...[
          const SizedBox(height: 16),
          OnbIconLine(
            key: const ValueKey('username-permanent'),
            icon: 'lock-outline',
            text: OnboardingCopy.usernamePermanent,
          ),
        ],
      ],
    );
  }

  /// Identity's hint colours, darkened to readable inks.
  Color _hintColor(Color? hint) {
    if (hint == AppColors.success) return const Color(0xFF07644C);
    if (hint == AppColors.error) return AppColors.onErrorContainer;
    return AppColors.textMuted;
  }

  InputDecoration _decoration({required String label, String? prefix}) =>
      InputDecoration(
        labelText: label,
        prefixText: prefix,
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      );
}
