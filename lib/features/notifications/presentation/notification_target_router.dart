/// Turns a [CallNotificationTarget] into a destination.
///
/// Kept out of the screen so the "tapping a notification opens the exact thing
/// it refers to" guarantee is one exhaustive `switch` a reviewer can read in
/// one sitting, and so a test can substitute its own opener without a
/// Navigator.
///
/// The app has no router and no named routes (contract §2), so this pushes
/// `MaterialPageRoute`s onto whatever navigator it is given — exactly what
/// `call_deep_link_router.dart` already does for shared links.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';

/// Signature the inbox screen accepts so a test — or a future shell that owns
/// navigation differently — can open targets its own way.
typedef NotificationTargetOpener =
    Future<void> Function(BuildContext context, CallNotificationTarget target);

/// The default opener.
///
/// Requires a [CallsProvider] in the tree, because a receipt is built from a
/// call the call slice owns: there is no second source of truth for what a
/// receipt says.
Future<void> openNotificationTarget(
  BuildContext context,
  CallNotificationTarget target,
) async {
  switch (target) {
    case NotificationCallTarget(:final callId):
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CallDetailScreen(callId: callId)),
      );

    case NotificationPersonTarget(:final personRef):
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallPersonScreen(personRef: personRef),
        ),
      );

    case NotificationReceiptTarget(:final callId):
      final provider = context.read<CallsProvider>();
      // Force, because a resolution notification is precisely the moment the
      // cached copy of that call went stale.
      final detail = await provider.loadCall(callId, force: true);
      if (!context.mounted) return;
      if (detail == null) {
        // The receipt could not be fetched. Say so where the tap happened
        // rather than opening an empty sheet.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              provider.callError(callId) ??
                  'We couldn\'t open that receipt. Try again.',
            ),
          ),
        );
        return;
      }
      await showCallReceiptSheet(
        context: context,
        receipt: CallReceipt.fromEntry(
          detail.entry,
          shareUrl: provider.shareLinkForCall(callId),
        ),
      );
  }
}
