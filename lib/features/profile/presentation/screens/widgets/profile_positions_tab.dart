/// Profile → Positions, wired to the signed-in account and its signers.
///
/// The positions themselves come from the BFF, keyed by the canonical
/// session. Claim signing is resolved per wallet through
/// [PantaSignerResolver]: today a connected wallet app over Mobile Wallet
/// Adapter signs for its own address. fleet/identity adds the wallet that
/// lives on this phone by extending [profilePantaSigners] — the flows here do
/// not change.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

/// The signers this device can offer for a Panta approval on [wallet].
PantaSignerResolver profilePantaSigners(MwaAuthProvider? auth) =>
    (wallet, intent) =>
        auth != null && auth.isAuthenticated && auth.walletAddress == wallet
            ? PantaMwaWallet(auth)
            : null;

class ProfilePositionsTab extends StatefulWidget {
  const ProfilePositionsTab({super.key, this.controllerOverride});

  /// Tests supply their own controller; the app builds one from the session.
  final PantaPositionsController? controllerOverride;

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
        signerFor: profilePantaSigners(auth),
      );
    } on ArgumentError {
      // A build without an HTTPS calls server cannot reach funded positions.
      _unavailable = true;
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
  Widget build(BuildContext context) => ListTile(
    tileColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    contentPadding: const EdgeInsets.all(16),
    title: const Text('Sign in to see your positions'),
    subtitle: const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        'Funded Panta positions belong to your account. Free calls are not '
        'positions.',
      ),
    ),
    onTap: onSignIn,
  );
}

class _Unconfigured extends StatelessWidget {
  const _Unconfigured();
  @override
  Widget build(BuildContext context) => const ListTile(
    tileColor: Colors.white,
    contentPadding: EdgeInsets.all(16),
    title: Text('Positions are not available in this build'),
    subtitle: Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text('This build has no secure calls server configured.'),
    ),
  );
}
