/// Which wallet signs a Panta buy for the signed-in account — the one rule
/// every place that opens a trade should use.
///
///  1. A connected wallet app (Phantom, Solflare, Seeker over Mobile Wallet
///     Adapter). It shows its own approval and simulation, so it goes first.
///  2. Otherwise the account's wallet that lives on this phone — but only once
///     the server has confirmed it belongs to the account (`signer` is null
///     before that), and only for the exact buy that was reviewed.
///  3. Otherwise nothing: the caller opens the wallet sheet
///     (`showEmbeddedWalletSheet`) so the person can make, link or connect one.
library;

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'embedded_wallet_controller.dart';
import 'panta_embedded_wallet.dart';

class PantaSignerChoice {
  const PantaSignerChoice._({
    required this.address,
    required this.port,
    required this.kind,
    required this.selectedWallet,
  });

  /// The wallet the trade is quoted for and must be signed by.
  final String address;

  /// Signs the reviewed transaction (never broadcasts).
  final PantaWalletPort port;

  /// Decides the trade sheet's copy: a wallet app's own approval screen, or
  /// this sheet's button as the only approval.
  final PantaSigner kind;

  /// The wallet selected right now, re-read before signing so a change of
  /// wallet or account between review and signing is refused.
  final String? Function() selectedWallet;
}

PantaSignerChoice? choosePantaSigner({
  required MwaAuthProvider? walletApp,
  required EmbeddedWalletController? onPhone,
  required PantaReviewedBuy reviewed,
}) {
  final app = walletApp;
  final appAddress =
      app != null && app.isAuthenticated ? app.walletAddress : null;
  if (app != null && appAddress != null) {
    return PantaSignerChoice._(
      address: appAddress,
      port: PantaMwaWallet(app),
      kind: PantaSigner.walletApp,
      selectedWallet: () => app.walletAddress,
    );
  }
  final phone = onPhone;
  final key = phone?.signer;
  if (phone == null || key == null) return null;
  return PantaSignerChoice._(
    address: key.address,
    port: PantaEmbeddedWallet(
      // Re-read at signing: signed out or another account means no key here.
      signer:
          () =>
              phone.signer ??
              (throw const PantaException(PantaErrorCode.walletChanged)),
      address: key.address,
      reviewed: reviewed,
    ),
    kind: PantaSigner.thisPhone,
    selectedWallet: () => phone.signer?.address,
  );
}
