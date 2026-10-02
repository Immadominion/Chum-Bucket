import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';

import '../data/sol_topup_client.dart';
import '../data/sol_topup_models.dart';
import '../domain/sol_topup_signer.dart';

/// Everything "SOL for fees" needs from the rest of the app. Production
/// resolves it from the tree; a `Provider<SolTopUpDependencies>` above the
/// sheet replaces all of it (widget tests).
class SolTopUpDependencies {
  const SolTopUpDependencies({
    required this.createClient,
    required this.signerFor,
  });

  /// A fresh client per sheet or prompt; the owner closes it.
  final SolTopUpClient Function() createClient;

  /// This device's signer for [wallet], or null when its key isn't here.
  final SolTopUpSigner? Function(String wallet) signerFor;

  /// Null when this build can't reach the BFF (no session in the tree, or a
  /// BFF URL that isn't HTTPS). Callers then show the "send SOL" path only.
  static SolTopUpDependencies? of(BuildContext context) {
    final override = context.read<SolTopUpDependencies?>();
    if (override != null) return override;
    final session = context.read<ChumbucketSession?>();
    if (session == null) return null;
    final base = Uri.tryParse(resolveCallsBffBaseUrl());
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return null;
    }
    final walletApp = context.read<MwaAuthProvider?>();
    final onPhone = context.read<EmbeddedWalletController?>();
    return SolTopUpDependencies(
      createClient:
          () => SolTopUpClient(baseUri: base, token: session.bffAuthToken),
      signerFor:
          (wallet) => solTopUpSignerFor(
            walletApp: walletApp,
            onPhone: onPhone,
            wallet: wallet,
          ),
    );
  }
}

/// The same rule as Panta trades (`choosePantaSigner`): a connected wallet app
/// first, else the wallet on this phone once the server has linked it — and
/// only for the exact wallet being topped up.
SolTopUpSigner? solTopUpSignerFor({
  required MwaAuthProvider? walletApp,
  required EmbeddedWalletController? onPhone,
  required String wallet,
}) {
  final app = walletApp;
  if (app != null && app.isAuthenticated && app.walletAddress == wallet) {
    return MwaSolTopUpSigner(app);
  }
  final key = onPhone?.signer;
  if (onPhone != null && key != null && key.address == wallet) {
    return EmbeddedSolTopUpSigner(
      signer: () => onPhone.signer,
      address: wallet,
    );
  }
  return null;
}

/// Whether swaps are switched on, remembered for a few minutes so prompts
/// don't ask on every build. Only ever the server's answer; null = not known.
class SolTopUpAvailability {
  SolTopUpAvailability._();

  static TopUpStatus? _status;
  static DateTime? _at;
  static Future<TopUpStatus?>? _inFlight;

  /// The last answer, if it is fresh.
  static TopUpStatus? get cached {
    final at = _at;
    if (at == null || DateTime.now().difference(at) > _ttl) return null;
    return _status;
  }

  static const _ttl = Duration(minutes: 5);

  static Future<TopUpStatus?> read(SolTopUpDependencies deps) {
    final held = cached;
    if (held != null) return Future.value(held);
    return _inFlight ??= () async {
      final client = deps.createClient();
      try {
        final status = await client.status();
        _status = status;
        _at = DateTime.now();
        return status;
      } on TopUpException {
        return null;
      } finally {
        client.close();
        _inFlight = null;
      }
    }();
  }

  @visibleForTesting
  static void reset() {
    _status = null;
    _at = null;
    _inFlight = null;
  }
}
