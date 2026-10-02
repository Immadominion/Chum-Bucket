# Optional Panta funding integration

This isolated feature does not register a route or alter the call/social loop.
Main can import `panta_trading.dart` from the existing `CallDetailScreen` after
review. Construct a `PantaTradingClient` with the existing HTTPS tRPC base URI
and a callback returning the canonical Supabase account ID/access token.
The account ID stays local; the token is used only in an Authorization header.
Status is public and all five procedures use POST with a `{ "json": ... }` body.

Construct `PantaTradeController` with the existing call ID, local catalog market
ID, market's Panta `venueMarketId`, `Side`, wallet address, client, wallet port,
and a callback for the currently selected wallet. Pass the controller and
existing question to `showPantaTradeSheet`. It inherits AppTheme and reuses the
existing AppColors, ChumbucketWavySheet, ChallengeButton, and BasilIcon.
The local amount limit is 100 USDC and slippage is fixed at 100 bps.

The wallet port must wrap the existing `MwaAuthProvider.createSigningSession`
and `signTransactions`, verify the MWA-authorized selected address equals the
reviewed wallet (including after authorization), return signed serialized
`Uint8List` bytes, and close the signing session. It must not call a broadcast
or send-and-sign method. Map a user decline to `PantaWalletCancelled`. The
controller independently rechecks the canonical account and selected wallet
before signing and submitting; local v0 parsing verifies round-trip bytes,
signer placement, unchanged message, and signature slots. The server remains
responsible for exact reviewed message/signature validation and RPC broadcast.
Local structural checks do not prove a valid signature or a real wallet approval.

An expired unsigned quote never opens the wallet or reaches submit. The current
BFF will not renew an expired UUID, so the user must explicitly cancel it or
edit the amount before a new UUID and fresh review can be prepared. A dropped
prepare reply always retries the same UUID, including if the server refuses
that expired intent; mobile never silently creates a second intent.

Keep the same controller alive while a submit reply is uncertain. Retry sends
the identical stored signed bytes/order ID, even after expiry; it does not
requote or reopen the wallet. Signed bytes are memory-only. The feature does
not restore them after process death. A fresh controller uses POST `forCall`
with only the existing call ID and wallet, through the canonical bearer session,
before prepare and during its initial status load. A recovered SUBMITTED/FILLED
order is checked against the exact wallet, Panta market and side and enters the
order phase. It allows manual order-ID reconciliation without a prepared quote;
it never opens the wallet or starts another buy. Failed/foreign recovery blocks
prepare. The server scopes the lookup to the canonical person/call/wallet.
The trade sheet itself still checks manually (`refreshOrder`, “Check order
status”). After it closes, the BFF's reconciler re-verifies every SUBMITTED
order on its own, and the call shows `PantaOrderStatusRow`, which re-reads the
ledger (`pantaTrading.callOrder`, never Panta) every 8 s while the order is
pending (30 s after five minutes) and stops once it is FILLED or FAILED.
Only server `FILLED` with complete fill evidence displays “Funded”.

Before submit, dismissal cancels the local intent and invalidates late wallet
callbacks. After submit begins, dismissal merely closes the sheet and makes
no cancellation claim. Main owns controller disposal and client closure;
an injected HTTP client remains owned by its caller. Dispose the controller
only when its pending result no longer needs retry/reconciliation. No amount,
wallet, order, or fill data is added to social call/share metadata.

`test/panta_trading_bff_contract_test.dart` drives the actual sibling BFF's
tRPC fetch adapter, Panta router, trading service, execution builder, and exact
message/signature checks over stdio. It requires the already-installed Bun
and `../chumbucket-social-calls-api` dependencies; it installs nothing. The
test-only `testing/bff_contract_harness.ts` disables network and .env loading
and injects synthetic identity, ledger, venue, and chain boundaries. Its public
deterministic fixture signing does not represent MWA approval or live fills.
The test harness is not exported by the feature.

## After the buy: positions, claims, funded calls

- `pantaTrading.positions` (session only) feeds `PantaPositionsController` and
  `PantaPositionsView` (Profile → Positions): proven cost, Panta's quoted
  shares, entry/current price, value and P&L as exact USDC base units, and the
  status `pending · failed · open · awaiting_result · won_claimable · won ·
  claiming · claimed · lost · void`. A missing source shows "—", never zero.
  It refreshes itself while an order or claim is still being confirmed.
- Claims: `claimPrepare` → local v0 checks → the signer from
  `PantaSignerResolver` (`domain/panta_signer.dart`) → re-check of the signed
  message → `claimSubmit`; a lost reply retries the identical signed bytes and
  never re-signs. The server confirms only on chain proof of a USDC payout.
  The resolver is the plug-in point for wallets: the profile tab maps a
  connected MWA wallet to `PantaMwaWallet`; an on-phone wallet should return
  its own `PantaWalletPort` for its address and check the
  `PantaClaimSigningIntent` it is given before signing.
- Selling: Panta's public API has no sell/close. The app links to
  `https://panta.market/market/<venueMarketId>` (`pantaMarketUri`,
  `PantaMarketLink`), which is also how receipts and market detail show
  "Resolved by Panta" instead of the authenticated API URL.
- Feed entries carry `funding` only for a confirmed fill; cards read "Funded"
  and receipts say "Backed with a Panta position" — never an amount.

## Files

All implementation and support files are new under `lib/features/panta_trading/`:

- `panta_trading.dart` — feature exports.
- `data/panta_trading_models.dart` — exact typed contracts, decimal amounts, fixed errors.
- `data/panta_trading_client.dart` — POST transport, header-only bearer, no redirects/logging.
- `domain/panta_wallet_port.dart` — existing session/selected-wallet callbacks and signing port.
- `domain/panta_transaction_validator.dart` — local native v0 structural/message checks.
- `panta_trade_controller.dart` — review, approval, replay, manual checks and cold recovery.
- `data/panta_lifecycle_models.dart` — positions, claims, call order, exact money display.
- `domain/panta_signer.dart` — signer resolver and signing intents (wallet plug-in point).
- `panta_positions_controller.dart` — positions, auto refresh, claim flow.
- `presentation/panta_positions_view.dart`, `panta_order_status_row.dart`, `panta_market_link.dart`.
- `presentation/panta_trade_sheet.dart` — existing wavy-sheet/button/icon treatment.
- `testing/bff_contract_harness.ts` — local real-router contract test bridge, no network.
- `README.md` — integration, ownership, retry and recovery notes.

New scoped tests:

- `test/panta_trading_client_test.dart`
- `test/panta_trading_controller_test.dart`
- `test/panta_trading_sheet_test.dart`
- `test/panta_trading_bff_contract_test.dart`
- `test/panta_lifecycle_test.dart`, `test/panta_lifecycle_surfaces_test.dart`
