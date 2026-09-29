/// One call, opened from the feed or from a shared link.
///
/// A shared link lands here for a signed-out visitor too: reading never needs
/// an account. Only answering does.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';

class CallDetailScreen extends StatefulWidget {
  final String callId;

  /// Attribution from a shared link's `?ref=`. Display only.
  final String? sharedByHandle;
  final VoidCallback? onSignInRequested;

  const CallDetailScreen({
    super.key,
    required this.callId,
    this.sharedByHandle,
    this.onSignInRequested,
  });

  @override
  State<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends State<CallDetailScreen> {
  PantaTradeController? _trade;
  PantaTradingClient? _tradingClient;

  @override
  void dispose() {
    _trade?.dispose();
    _tradingClient?.close();
    super.dispose();
  }

  Future<void> _fund(CallFeedEntry entry) async {
    final auth = context.read<MwaAuthProvider>();
    final account = context.read<ChumbucketSession>();
    final wallet = auth.walletAddress;
    if (!account.isReady || wallet == null || !auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use your connected wallet and link Google in Profile → Settings to fund your own call.',
          ),
        ),
      );
      return;
    }
    if (_trade == null || _trade!.phase == PantaTradePhase.cancelled) {
      _trade?.dispose();
      _tradingClient?.close();
      _tradingClient = PantaTradingClient(
        baseUri: Uri.parse(resolveCallsBffBaseUrl()),
        session: () async {
          final token = await account.bffAuthToken();
          final id = account.userId;
          return token != null && id != null && account.isReady
              ? PantaSession(accountId: id, accessToken: token)
              : null;
        },
      );
      _trade = PantaTradeController(
        callId: entry.call.id,
        marketId: entry.market.id,
        venueMarketId: entry.market.venueMarketId,
        side: entry.call.side,
        wallet: wallet,
        client: _tradingClient!,
        walletPort: PantaMwaWallet(auth),
        selectedWallet: () => auth.walletAddress,
      );
    }
    await showPantaTradeSheet(
      context: context,
      controller: _trade!,
      marketQuestion: entry.market.question,
    );
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadCall(widget.callId);
    });
  }

  Future<void> _respond(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final result = await showCallResponseSheet(context: context, entry: entry);
    if (result != null && mounted) {
      await provider.loadCall(widget.callId, force: true);
    }
  }

  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      receipt: CallReceipt.fromEntry(
        entry,
        shareUrl: provider.shareLinkForCall(entry.call.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Call',
          style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
        ),
      ),
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          final detail = provider.callDetail(widget.callId);
          if (detail == null) {
            if (provider.isLoadingCall(widget.callId)) {
              return const CallsLoadingView(rows: 1);
            }
            if (provider.isOffline) {
              return CallsOfflineView(
                onRetry: () => provider.loadCall(widget.callId, force: true),
              );
            }
            return CallsErrorView(
              message:
                  provider.callError(widget.callId) ??
                  'We couldn\'t open that call.',
              onRetry: () => provider.loadCall(widget.callId, force: true),
            );
          }
          return _body(provider, detail);
        },
      ),
    );
  }

  Widget _body(CallsProvider provider, CallDetail detail) {
    final entry = detail.entry;
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
      children: [
        if (widget.sharedByHandle != null)
          CallsNotice(
            icon: 'share-outline',
            color: AppColors.textSecondary,
            message: 'Shared with you by @${widget.sharedByHandle}.',
          ),
        if (provider.isOffline)
          CallsNotice.offline(
            onRetry: () => provider.loadCall(widget.callId, force: true),
          ),
        if (!provider.isSignedIn)
          CallsNotice(
            icon: 'user-outline',
            color: AppColors.textSecondary,
            message:
                'You can read this without an account. Sign in to answer it.',
          ),
        CallCard(
          entry: entry,
          onOpenMarket:
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MarketDetailScreen(marketId: entry.market.id),
                ),
              ),
          onOpenPerson:
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallPersonScreen(personRef: entry.author.id),
                ),
              ),
          onRespond:
              entry.author.id == provider.viewerUserId
                  ? null
                  : () => _respond(entry),
          onShareReceipt: () => _shareReceipt(entry),
        ),

        // Private, optional funding. The free statement/receipt never changes,
        // and somebody else's call never shows their stake or a copy-trade button.
        if (entry.market.venue == MarketVenue.panta &&
            entry.author.id == provider.viewerUserId) ...[
          SizedBox(height: 12.h),
          OutlinedButton(
            onPressed: () => _fund(entry),
            child: Text(
              _trade?.isFunded == true
                  ? 'View your Panta funding'
                  : 'Fund this call · optional',
            ),
          ),
          Text(
            'Powered by Panta',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.sp),
          ),
        ],

        SizedBox(height: 8.h),
        Text(
          CallsFormat.outcomeSentence(entry.outcome),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
        ),

        if (detail.parent != null) ...[
          SizedBox(height: 20.h),
          Text(
            'In response to',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8.h),
          CallCard(
            entry: detail.parent!,
            onOpenMarket:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (_) => MarketDetailScreen(
                          marketId: detail.parent!.market.id,
                        ),
                  ),
                ),
          ),
        ],

        SizedBox(height: 20.h),
        Text(
          detail.responses.isEmpty
              ? 'No one has answered this yet.'
              : '${detail.responses.length} answer'
                  '${detail.responses.length == 1 ? '' : 's'}',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 6.h),
        for (final response in detail.responses)
          Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: Text(
              '${response.kind.label} · ${CallsFormat.relative(response.createdAtUtc)}'
              '${response.resultingCallId == null ? ' · no call created' : ' · created their own call'}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
            ),
          ),
      ],
    );
  }
}
