import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_signers.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_of.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';

import '../add_funds_controller.dart';
import '../data/deposit_order_memory.dart';
import '../data/deposits_client.dart';
import '../data/device_deposit_wallet_source.dart';
import '../data/mwa_deposit_wallet_source.dart';
import '../domain/deposit_wallet_source.dart';

/// Shows Crossmint's checkout for the controller's current order and returns
/// when the person leaves it. Tests replace it; the app pushes a WebView.
typedef DepositCheckoutOpener =
    Future<void> Function(BuildContext context, AddFundsController controller);

/// Everything Add funds needs from the rest of the app.
///
/// Production resolves it from the tree ([DepositsDependencies.of]): the BFF
/// the calls slice already uses, the Supabase session token, the canonical
/// account id and this device's wallet. A `Provider<DepositsDependencies>`
/// above the sheet replaces all of it (widget tests, previews).
class DepositsDependencies {
  const DepositsDependencies({
    required this.createClient,
    this.accountId,
    this.walletSource,
    this.memory,
    this.openCheckout,
  });

  /// A fresh client per sheet; the sheet closes it.
  final DepositsClient Function() createClient;

  /// The canonical public.users.id: keys the "payment in flight" memory only.
  final String? accountId;

  /// This device's trading wallet, or null (the server then picks the
  /// account's own wallet — it never needs the device to name one).
  final DepositWalletSource? walletSource;
  final DepositOrderMemory? memory;
  final DepositCheckoutOpener? openCheckout;

  /// Null when this build can't reach deposits at all (no session in the
  /// tree, or a BFF URL that isn't HTTPS). Callers say so, honestly.
  static DepositsDependencies? of(BuildContext context) {
    final override = context.read<DepositsDependencies?>();
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
    return DepositsDependencies(
      createClient:
          () => DepositsClient(baseUri: base, token: session.bffAuthToken),
      accountId: session.userId,
      walletSource: depositWalletSourceOf(context),
      memory: const SharedPrefsDepositOrderMemory(),
    );
  }
}

/// The wallet this device trades from, as Add funds sees it.
///
/// A connected wallet app (Mobile Wallet Adapter) first, else the account's
/// wallet that lives on this phone once the server has linked it — the same
/// order as `choosePantaSigner`, so Add funds tops up the wallet a trade
/// spends from. With neither, Add funds still works: the server funds the
/// account's own verified wallet, and only an ownership signature (above
/// Crossmint's threshold) needs the device to hold the key.
///
/// With the Chumbucket wallet on, the same order as trades then: a wallet
/// already on this phone, else the Chumbucket wallet, else the wallet app.
DepositWalletSource? depositWalletSourceOf(BuildContext context) {
  final auth = context.read<MwaAuthProvider?>();
  final onPhone = context.read<EmbeddedWalletController?>();
  final chumbucket = chumbucketWalletOf(context);
  final walletApp =
      auth != null && auth.isAuthenticated && auth.walletAddress != null
          ? MwaDepositWalletSource(auth)
          : null;
  final key = onPhone?.signer;
  final phone =
      onPhone != null && key != null
          ? DeviceDepositWalletSource(
            address: key.address,
            currentAddress: () => onPhone.signer?.address,
            sign: (message) async {
              // Re-read: signed out, another account or another wallet since.
              final signer = onPhone.signer;
              if (signer == null || signer.address != key.address) {
                throw const DepositWalletDeclined();
              }
              return signer.sign(message);
            },
          )
          : null;
  if (chumbucket == null) return walletApp ?? phone;
  final own = chumbucket.signer;
  return phone ??
      (own != null ? chumbucketDepositWalletSource(chumbucket, own) : null) ??
      walletApp;
}
