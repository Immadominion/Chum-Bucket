# Panta SOL-quoted markets v1

4 October 2026. Additive extension of `panta-share-price-v1.md`. Nothing
existing changes meaning.

## Why

Panta's partner API lists only USDC-quoted markets. The same Panta program
(`6gM5afTQBq5VZCfgpGqcsqzfWd5maLSCKWtGjbEobZMp`) also holds SOL-quoted markets,
which panta.market shows but the API never returns. On 2026-10-04 the program
held 201 markets; 12 were open: 6 USDC (all already in Chumbucket) and 6 SOL
(missing). The BFF now reads SOL markets from the program account itself.
They take free calls. They are never tradable, because Chumbucket's trade path
is Panta's USDC primary buy.

## Wire shape (all additive)

Every served Panta market (`markets.open`, `markets.detail`, call feed entries,
`predictions.catalog`) carries two fields beside the frozen `VenueMarket`:

```ts
quoteCurrency: "USDC" | "SOL" | null; // null = a normalisation this build does not know
tradable: boolean;                    // true only where Chumbucket can trade (USDC)
```

`SharePriceSnapshot.currency` widens from `"USDC"` to `"USDC" | "SOL"`. A SOL
price is the program's `last_yes_price` on its 1e9 scale and its complement:
the figure panta.market shows, in SOL per share. It is never converted to USD
and never shown as a percent.

`VenueMarket.payloadVersion` says which normalisation wrote the row: `1` is
Panta's partner API (USDC), `2` is a SOL market read from its program account.
`quoteCurrency` is derived from it, so it survives restarts.

## Trust

- Quote asset: proven, not guessed. The program derives a SOL market's address
  as PDA("event", creator, sha256(question)) and a USDC market's as
  PDA("event_usdc", …). An account matching neither is not served. This also
  proves the question is the one the market was created with.
- Evidence: the raw account bytes (base64) and slot, re-derived on every read
  of stored evidence. Prices that disagree with their bytes are refused.
- Results: only the program's own final flags, behind the partner adapter's
  gates (no pending review, review window over, claimable).
- Category: display-only, from panta.market's public registry; "other" when
  unavailable. Never used for settlement.

## Storage

Migration `20261004090000_panta_sol_quoted_prices.sql` widens two CHECK
constraints on `market_share_price_snapshots`: `currency` may be SOL, with
payload-version-2 chain evidence whose `quoteAsset` is SOL. No row is
rewritten; every existing row still passes.

## Mobile behaviour

- Prices read in their own unit everywhere (`0.67 SOL/share`). The catalog
  legend no longer claims one unit for every row.
- A non-tradable market shows no Trade action at all (market detail, call
  detail): one full-width "Make a call", caption "Calling is free."
- An older server sends neither field; the app then treats Panta markets as
  tradable USDC, which is all an older server served.

## Release order

Install the mobile build before the BFF that serves SOL markets: an older app
rejects a `currency: "SOL"` price. Apply the migration before that BFF writes
SOL prices. Kill switch: `PANTA_SOL_MARKETS=false`. Optional dedicated RPC:
`PANTA_CATALOG_RPC_URL` (else `SOLANA_RPC_URL`).
