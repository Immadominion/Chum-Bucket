/// Everything the money flows need from the rest of the app, resolved from
/// the tree: the BFF the calls slice uses, the canonical session, and the
/// account's signers (the Chumbucket wallet by default, the wallet on this
/// phone, or a wallet app). A `Provider<MoneyDependencies>` above a screen
/// replaces all of it (widget tests).
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/presentation/screens/widgets/mwa_connect_button.dart'
    show reconnectWalletApp;
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_of.dart';
import 'package:chumbucket/features/chumbucket_wallet/presentation/chumbucket_wallet_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_sheet.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart'
    show PantaReviewedBuy;
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_positions_tab.dart'
    show profilePantaSigners;
import 'package:chumbucket/features/sol_topup/data/sol_topup_client.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_dependencies.dart'
    show solTopUpSignerFor;
import 'package:chumbucket/features/trust/presentation/funded_trading_attestation_sheet.dart';

import '../data/money_client.dart';
import '../domain/money_gas.dart';
import '../domain/money_transfer_signer.dart';
import '../money_call_controller.dart';

class MoneyDependencies {
  const MoneyDependencies({
    required this.createClient,
    required this.createTradingClient,
    required this.buySigner,
    required this.transferSigner,
    required this.claimSigners,
    this.gasTopUp,
    this.setUpWallet,
    this.ensureAttestation,
    this.openCard,
    this.walletApp,
    this.connectWalletApp,
    this.phoneWallets,
    this.pollEvery = const Duration(seconds: 3),
  });

  /// A fresh client per flow; the flow closes it.
  final MoneyClient Function() createClient;
  final PantaTradingClient Function() createTradingClient;

  /// Who signs a buy, in `choosePantaSigner`'s order (the Chumbucket wallet
  /// first when it is on). Null: nobody can sign on this phone yet.
  final MoneyBuySigner? Function(PantaReviewedBuy reviewed) buySigner;

  /// The signer for a transfer paid by [wallet], or null.
  final MoneyTransferSigner? Function(String wallet) transferSigner;

  /// Win claims, per wallet (the positions screen's resolver).
  final PantaSignerResolver claimSigners;

  /// The gasless top-up the server asks for with `NEEDS_GAS`; null when this
  /// build cannot run it.
  final MoneyGasTopUp? gasTopUp;

  /// First need: sets up the Chumbucket wallet. True when it is ready.
  final Future<bool> Function(BuildContext context)? setUpWallet;

  /// 18+, eligibility and venue terms before the first trade.
  final Future<bool> Function(BuildContext context)? ensureAttestation;

  /// Card / Apple Pay / Google Pay through Crossmint (the existing Add funds
  /// checkout). Resolves true when USDC arrived.
  final Future<bool> Function(
    BuildContext context, {
    BigInt? shortfall,
    String? wallet,
  })?
  openCard;

  /// The connected wallet app's address, or null.
  final String? Function()? walletApp;
  final Future<bool> Function(BuildContext context)? connectWalletApp;

  /// The wallets this phone itself knows are the account's: the Chumbucket
  /// wallet alone when it is on, else the wallet app, the wallet on this
  /// phone and the wallet this session signed in with. A deposit only ever
  /// goes to one of these, whatever a server answer names.
  final Set<String> Function()? phoneWallets;
  final Duration pollEvery;

  static MoneyDependencies? of(BuildContext context) {
    final override = context.read<MoneyDependencies?>();
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
    final auth = context.read<MwaAuthProvider?>();
    final onPhone = context.read<EmbeddedWalletController?>();
    final chumbucket = chumbucketWalletOf(context);
    return MoneyDependencies(
      createClient:
          () => MoneyClient(baseUri: base, token: session.bffAuthToken),
      createTradingClient:
          () => PantaTradingClient(
            baseUri: base,
            session: () async {
              final token = await session.bffAuthToken();
              final id = session.userId;
              return token != null && id != null && session.isReady
                  ? PantaSession(accountId: id, accessToken: token)
                  : null;
            },
          ),
      buySigner: (reviewed) {
        final choice = choosePantaSigner(
          walletApp: auth,
          onPhone: onPhone,
          chumbucket: chumbucket,
          reviewed: reviewed,
        );
        if (choice == null) return null;
        return MoneyBuySigner(
          address: choice.address,
          port: choice.port,
          selectedWallet: choice.selectedWallet,
          opensWalletApp: choice.kind == PantaSigner.walletApp,
        );
      },
      transferSigner:
          (wallet) => moneyTransferSignerFor(
            wallet: wallet,
            walletApp: auth,
            onPhone: onPhone,
            chumbucket: chumbucket,
          ),
      claimSigners: profilePantaSigners(auth, onPhone, chumbucket),
      gasTopUp: (wallet, amount) async {
        final client = SolTopUpClient(baseUri: base, token: session.bffAuthToken);
        try {
          await runGasTopUp(
            client: client,
            signer: solTopUpSignerFor(
              walletApp: auth,
              onPhone: onPhone,
              chumbucket: chumbucket,
              wallet: wallet,
            ),
            wallet: wallet,
            amountBaseUnits: amount,
          );
        } finally {
          client.close();
        }
      },
      setUpWallet:
          chumbucket == null
              ? null
              : (context) => showChumbucketWalletSheet(context, setUp: true),
      ensureAttestation: ensureFundedTradingAttestation,
      openCard:
          (context, {shortfall, wallet}) => showAddFundsSheet(
            context,
            requiredUsdcBaseUnits: shortfall,
            fundWallet: wallet,
          ),
      walletApp:
          auth == null
              ? null
              : () => auth.isAuthenticated ? auth.walletAddress : null,
      connectWalletApp: auth == null ? null : reconnectWalletApp,
      phoneWallets: () {
        if (chumbucket != null) {
          final own = chumbucket.address;
          return {if (own != null) own};
        }
        final app =
            auth != null && auth.isAuthenticated ? auth.walletAddress : null;
        final phone = onPhone?.signer?.address;
        final signedInWith = session.signInWallet;
        return {
          if (app != null) app,
          if (phone != null) phone,
          if (signedInWith != null) signedInWith,
        };
      },
    );
  }
}

/// The signer for a transfer paid by [wallet], in the trade's order: a
/// connected wallet app for its own address, else the wallet on this phone,
/// else the Chumbucket wallet. Each one runs `checkUsdcTransfer` first.
MoneyTransferSigner? moneyTransferSignerFor({
  required String wallet,
  MwaAuthProvider? walletApp,
  EmbeddedWalletController? onPhone,
  ChumbucketWalletController? chumbucket,
}) {
  final app = walletApp;
  if (app != null && app.isAuthenticated && app.walletAddress == wallet) {
    final port = PantaMwaWallet(app);
    return MoneyTransferSigner(
      address: wallet,
      opensWalletApp: true,
      sign: (unsigned, _) => port.signTransaction(unsigned),
    );
  }
  final key = onPhone?.signer;
  if (onPhone != null && key != null && key.address == wallet) {
    return MoneyTransferSigner(
      address: wallet,
      sign: (_, message) async {
        // Re-read: signed out or another account means no key here.
        final now = onPhone.signer;
        if (now == null || now.address != wallet) {
          throw const TransferSignFailed();
        }
        return Uint8List.fromList(await now.sign(message));
      },
    );
  }
  if (chumbucket != null && chumbucket.address == wallet) {
    return MoneyTransferSigner(
      address: wallet,
      sign: (unsigned, _) async {
        final signer = chumbucket.signer;
        if (signer == null || signer.address != wallet) {
          throw const TransferSignFailed();
        }
        return signer.signTransaction(unsigned);
      },
    );
  }
  return null;
}
