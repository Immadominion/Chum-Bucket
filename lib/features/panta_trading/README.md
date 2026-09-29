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
No automatic polling exists: `refreshOrder` and “Check order status” are manual.
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

## Files

All implementation and support files are new under `lib/features/panta_trading/`:

- `panta_trading.dart` — feature exports.
- `data/panta_trading_models.dart` — exact typed contracts, decimal amounts, fixed errors.
- `data/panta_trading_client.dart` — POST transport, header-only bearer, no redirects/logging.
- `domain/panta_wallet_port.dart` — existing session/selected-wallet callbacks and signing port.
- `domain/panta_transaction_validator.dart` — local native v0 structural/message checks.
- `panta_trade_controller.dart` — review, approval, replay, manual checks and cold recovery.
- `presentation/panta_trade_sheet.dart` — existing wavy-sheet/button/icon treatment.
- `testing/bff_contract_harness.ts` — local real-router contract test bridge, no network.
- `README.md` — integration, ownership, retry and recovery notes.

New scoped tests:

- `test/panta_trading_client_test.dart`
- `test/panta_trading_controller_test.dart`
- `test/panta_trading_sheet_test.dart`
- `test/panta_trading_bff_contract_test.dart`
