/// Profile → Positions, wired to the signed-in account and its signers.
///
/// The positions themselves come from the BFF, keyed by the canonical
/// session. Claim signing is resolved per wallet through
/// [PantaSignerResolver] ([profilePantaSigners]): a connected wallet app over
/// Mobile Wallet Adapter signs for its own address; otherwise the account's
/// linked wallet on this phone signs a win claim for its own address, and only
/// the reviewed claim (`PantaEmbeddedClaimWallet`).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_signers.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_of.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_claim.dart';
import 'package:chumbucket/features/embedded_wallet/panta_wallet_app.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';

/// The signers this device can offer for a Panta approval on [wallet], in
/// `choosePantaSigner`'s order: a connected wallet app for its own address,
/// else the linked wallet on this phone (its `signer` is null until the
/// server confirmed it is the account's) for a win claim on its own address,
/// else the linked Chumbucket wallet, likewise.
PantaSignerResolver profilePantaSigners(
  MwaAuthProvider? auth, [
  EmbeddedWalletController? onPhone,
  ChumbucketWalletController? chumbucket,
]) => (wallet, intent) {
  if (auth != null &&
      auth.isAuthenticated &&
      auth.walletAddress == wallet &&
      intent is PantaClaimSigningIntent &&
      intent.owner == wallet) {
    // The claim check runs on this phone before the wallet app opens.
    return walletAppClaimPort(auth, intent: intent);
  }
  final key = onPhone?.signer;
  if (onPhone != null &&
      key != null &&
      key.address == wallet &&
      intent is PantaClaimSigningIntent &&
      intent.owner == wallet) {
    return PantaEmbeddedClaimWallet(
      // Re-read at signing: signed out or another account means no key.
      signer: () => onPhone.signer,
      intent: intent,
    );
  }
  // The linked Chumbucket wallet, for a win claim on its own address.
  if (chumbucket != null &&
      chumbucket.address == wallet &&
      intent is PantaClaimSigningIntent &&
      intent.owner == wallet) {
    return PantaChumbucketClaimWallet(
      signer: () => chumbucket.signer,
      intent: intent,
    );
  }
  return null;
};

class ProfilePositionsTab extends StatefulWidget {
  const ProfilePositionsTab({
    super.key,
    this.controllerOverride,
    this.refreshTick = 0,
  });

  /// Tests supply their own controller; the app builds one from the session.
  final PantaPositionsController? controllerOverride;

  /// Profile's pull-to-refresh bumps this; the positions read again quietly.
  final int refreshTick;

  @override
  State<ProfilePositionsTab> createState() => _ProfilePositionsTabState();
}

class _ProfilePositionsTabState extends State<ProfilePositionsTab> {
  PantaTradingClient? _client;
  PantaPositionsController? _controller;
  bool _unavailable = false;

  PantaPositionsController? get _active =>
      widget.controllerOverride ?? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controllerOverride != null || _controller != null) return;
    final session = context.read<ChumbucketSession?>();
    if (session == null) return;
    final auth = context.read<MwaAuthProvider?>();
    final onPhone = context.read<EmbeddedWalletController?>();
    final chumbucket = chumbucketWalletOf(context);
    try {
      _client = PantaTradingClient(
        baseUri: Uri.parse(resolveCallsBffBaseUrl()),
        session: () async {
          final token = await session.bffAuthToken();
          final id = session.userId;
          return token != null && id != null && session.isReady
              ? PantaSession(accountId: id, accessToken: token)
              : null;
        },
      );
      _controller = PantaPositionsController(
        client: _client!,
        signerFor: profilePantaSigners(auth, onPhone, chumbucket),
      );
    } on ArgumentError {
      // A build without an HTTPS calls server cannot reach funded positions.
      _unavailable = true;
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePositionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _active;
    if (oldWidget.refreshTick != widget.refreshTick &&
        controller != null &&
        !controller.loading) {
      controller.load();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ChumbucketSession?>();
    final controller = _active;
    if (widget.controllerOverride == null && session?.isReady != true) {
      return _SignedOut(onSignIn: () => requestCallSignIn(context));
    }
    if (_unavailable || controller == null) {
      return const _Unconfigured();
    }
    return PantaPositionsView(
      controller: controller,
      onOpenCall:
          (callId) => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CallDetailScreen(callId: callId)),
          ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onSignIn});
  final VoidCallback onSignIn;
  @override
  Widget build(BuildContext context) => ChumbucketStateView(
    artwork: ChumbucketStateArtwork.access,
    message: 'Sign in to see your positions',
    semanticsHint:
        'Funded Panta positions belong to your account. Free calls are not '
        'positions.',
    actionLabel: 'Sign in',
    actionIcon: 'login-outline',
    onAction: onSignIn,
  );
}

class _Unconfigured extends StatelessWidget {
  const _Unconfigured();
  @override
  Widget build(BuildContext context) => const ChumbucketStateView(
    artwork: ChumbucketStateArtwork.waiting,
    message: 'Positions are not available in this build',
    compact: true,
  );
}
