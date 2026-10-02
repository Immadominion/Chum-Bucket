/// Who signs for a wallet, and what they are being asked to sign.
///
/// Every Panta approval in the app — a buy today, a win claim here — goes
/// through a [PantaWalletPort]. This file is the seam that picks one for a
/// given wallet, so a new kind of wallet plugs in without touching the flows:
///
///  * a wallet app over Mobile Wallet Adapter (`PantaMwaWallet`) shows its own
///    simulation and approval for whatever it is handed;
///  * a wallet that lives on this phone (fleet/identity's embedded wallet) has
///    no second screen, so it must check the exact shape of what it signs.
///    [PantaSigningIntent] tells it what the person reviewed, and it must
///    refuse anything else (throw `PantaException(PantaErrorCode.signingFailed)`).
///
/// A resolver returns null when this device cannot sign for [wallet] right
/// now; the app then says so and offers Panta's own site instead.
library;

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;

import 'panta_wallet_port.dart';

/// What the person reviewed and is about to approve.
sealed class PantaSigningIntent {
  const PantaSigningIntent();
}

/// A `claim_win_usdc` for [venueMarketId], paying [owner]'s own USDC account.
/// The BFF already refused anything outside the documented claim profile; an
/// on-phone signer must re-check it before signing.
class PantaClaimSigningIntent extends PantaSigningIntent {
  const PantaClaimSigningIntent({
    required this.owner,
    required this.venueMarketId,
    required this.outcome,
    required this.winningShares,
  });
  final String owner;
  final String venueMarketId;
  final Side outcome;
  final String winningShares;
}

/// Picks the signer for [wallet] and [intent], or null when none is available.
typedef PantaSignerResolver =
    PantaWalletPort? Function(String wallet, PantaSigningIntent intent);
