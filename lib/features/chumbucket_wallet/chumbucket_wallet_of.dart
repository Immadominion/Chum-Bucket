import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'chumbucket_wallet_controller.dart';

/// The Chumbucket wallet for the signed-in account — only when the server
/// says it is on for THIS account (`wallet.status`; it may be on for admins
/// only). Null otherwise, so every flow behaves exactly as a build without
/// it: no wallet, no setup sheet, no provider session.
ChumbucketWalletController? chumbucketWalletOf(
  BuildContext context, {
  bool listen = false,
}) {
  final wallet =
      listen
          ? context.watch<ChumbucketWalletController?>()
          : context.read<ChumbucketWalletController?>();
  return wallet != null && wallet.enabled ? wallet : null;
}
