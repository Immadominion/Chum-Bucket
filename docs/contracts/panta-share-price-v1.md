# Panta native-price evidence v1

28 September 2026. Additive extension to pivot-contracts-v1; old probability
snapshots retain their meaning. Panta is the only live provider selected by
the current product branch. No order, position or funding capability is added.

## Wire shape

`MarketDetail.sharePrice` and `Call.entryPrice` are optional for older receipts.
For a new Panta call, `entryPrice` is required and both `entryProbability` and
`snapshotId` are null. A Panta market detail has `snapshot: null`.

```ts
type SharePriceSnapshot = {
  id: string;                 // UUIDv5("share-price:panta:<marketId>:<observedAt>")
  marketId: string;           // canonical venue-market UUID
  venue: "panta";
  currency: "USDC";
  unit: "per_share";
  yesPrice: string | null;    // independent exact decimal; may exceed 1
  noPrice: string | null;     // never computed from YES
  observedAt: number;        // original server observation, Unix milliseconds
  source: "venue";
  attribution: "Powered by Panta";
  executable: false;
};
```

No additional keys are accepted. Decimal strings permit up to 31 integer and
18 fractional digits; no exponents, signs, NaN or floating-point coercion.
Null means unavailable, not zero. Prices are indicative observations, not
trade quotes, stake amounts, probabilities, or community predictions.

Both sides must exist; an observation from the future or older than ten minutes
cannot lock a call. A Back/Fade pins the responding person's current snapshot,
not the target person's old one. The original price remains unchanged after
later polls, settlement, a restart or withdrawal from distribution.

## Storage and enforcement

New `market_share_price_snapshots` stores an immutable normalized `snapshot`
plus private `raw_evidence`. Public readers can select the price columns only
while the parent market is public. They cannot read raw provider bodies or
write evidence. Panta raw prices/capture identity must match the observation.
UPDATE, DELETE and TRUNCATE are rejected even for the table owner.

New `calls.share_price_snapshot_id` is a restricted FK; `calls.entry_price`
retains the exact referenced snapshot. Neither new column is client-writable.
The new insert/update trigger supplements, never replaces, the existing
closed-market, known-result, parent-market and immutability guards. New Panta
calls must be free and freshly timestamped, with their own stored observation.
Existing callers and historical rows are not rewritten.

The migration widens the market and resolution venue constraints only. It
does not enable Panta in funded orders or positions.

## Mobile behavior

The existing market detail, composer, call card, response sheet and receipt
card render exact USDC/share prices and Panta attribution. The receipt carries
the observed timestamp and snapshot identifier, without an entry-probability
label. Its share caption includes “Powered by Panta.” No navigation, profile,
wallet or account-creation flow changes are part of this packet.

## Release gate

Implemented and tested locally, not deployed. The production runtime still
refuses durable Panta traffic. `allowPantaCalls` is an explicit local test
injection only, not a deployable environment flag. Before lifting that gate:
review/apply the additive migration with approval, complete existing-account
linking, and validate the configured free loop on the Seeker with real usable
Panta market data. Do not substitute another venue or invent a market/result.

No keys belong in Flutter; no funded behavior is enabled by this contract.
