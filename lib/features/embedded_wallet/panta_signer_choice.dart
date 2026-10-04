/// Which wallet signs a Panta buy for the signed-in account — the one rule
/// every place that opens a trade should use.
///
/// Without the Chumbucket wallet (`chumbucket` is null, the default build):
///  1. A connected wallet app (Phantom, Solflare, Seeker over Mobile Wallet
///     Adapter). It shows its own approval and simulation, so it goes first.
///  2. Otherwise the account's wallet that lives on this phone — but only once
///     the server has confirmed it belongs to the account (`signer` is null
///     before that), and only for the exact buy that was reviewed.
///  3. Otherwise nothing: the caller opens the wallet sheet
///     (`showEmbeddedWalletSheet`) so the person can make, link or connect one.
///
/// With the Chumbucket wallet (`CHUMBUCKET_WALLET_ENABLED`):
///  1. The wallet app, only when the person chose it ([useWalletApp]).
///  2. A wallet already on this phone keeps working, untouched: its money is
///     there.
///  3. The Chumbucket wallet, once linked — the default for everyone else.
///  4. Otherwise nothing: the caller sets the Chumbucket wallet up (first
///     need) and asks again.
library;

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'package:chumbucket/features/chumbucket_wallet/chumbucket_signers.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';

import 'embedded_wallet_controller.dart';
import 'panta_wallet_app.dart';
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
  ChumbucketWalletController? chumbucket,
  bool useWalletApp = false,
}) {
  final app = walletApp;
  final appAddress =
      app != null && app.isAuthenticated ? app.walletAddress : null;
  if (app != null &&
      appAddress != null &&
      (chumbucket == null || useWalletApp)) {
    return PantaSignerChoice._(
      address: appAddress,
      // Checked on this phone before the wallet app opens, like every signer.
      port: walletAppBuyPort(app, owner: appAddress, reviewed: reviewed),
      kind: PantaSigner.walletApp,
      selectedWallet: () => app.walletAddress,
    );
  }
  if (chumbucket != null && useWalletApp) return null;
  final onPhoneChoice = _onPhoneChoice(onPhone, reviewed);
  if (onPhoneChoice != null || chumbucket == null) return onPhoneChoice;
  final wallet = chumbucket.signer;
  if (wallet == null) return null;
  return PantaSignerChoice._(
    address: wallet.address,
    port: PantaChumbucketWallet(
      // Re-read at signing: signed out or another account means no signer.
      signer: () => chumbucket.signer,
      address: wallet.address,
      reviewed: reviewed,
    ),
    kind: PantaSigner.chumbucket,
    selectedWallet: () => chumbucket.address,
  );
}

PantaSignerChoice? _onPhoneChoice(
  EmbeddedWalletController? onPhone,
  PantaReviewedBuy reviewed,
) {
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
