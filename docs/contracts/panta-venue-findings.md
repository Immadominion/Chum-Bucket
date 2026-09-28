# Panta — what the live API actually is

> **Current product decision (28 September): Panta only.** No Polymarket
> discovery/Jupiter execution split and no alternate-provider fallback. This
> supersedes the recommendations below and the original roadmap's provider
> choice. The API product branch now enforces it; production has not been
> switched. See `../checkpoints/2026-09-28-panta-only.md` for remaining gates.
>
> Historical investigation below, not the current implementation status.
> On 28 September the API product branch gained a live-tested **read-only**
> `PantaVenue` adapter. Production and the phone still use the prior provider.
> The fresh catalog had 85 rows, six titled rows (all resolved), and zero usable
> open questions. See `docs/checkpoints/2026-09-28-panta-read-adapter.md`.
> The discovery/funding split proposed in §4 is not automatic: a Panta position
> can only attach to the same Panta market/rules, not an unrelated Polymarket
> question. Native USDC/share prices must not be relabelled as probabilities.
> Fees and catalog statistics below are historical observations, not current quotes.

**Investigated:** 19 September 2026, against the real API with a live key.
**Why:** the Superteam "Panta API side track" ($5,000 USDG, winners 27 October 2026), and the
question of whether Panta can replace or supplement Polymarket as Chumbucket's venue.

Earlier project research concluded Panta had *"no stable public integration API/SDK"*. **That is
out of date.** It shipped one. Everything below was verified against
`https://live-api.panta.market/api/v1`, not read off a landing page.

---

## 1. Access

| | |
| --- | --- |
| Base URL | `https://live-api.panta.market/api/v1` |
| Auth | `X-Api-Key: pk_test_…` / `pk_live_…`, or `Authorization: Bearer <JWT>` |
| Register | `POST /auth/register/` — `{email, password, name}` → `{userId, access, refresh}` |
| Mint key | `POST /account/keys/` — `{env: "test"\|"live", name, revokeOthers}` → `{secret}` **once** |
| KYC / fee to sign up | none documented |
| `canCreateMarkets` | defaults `true` |

Two traps, both cost time:

- The mint-key body field is **`env`**, not `environment`. Anything else is a `400`.
- **A `pk_test_` key returns SANDBOX FIXTURES**, not real data. The response says so —
  `"Test mode: this response uses sandbox fixtures and does not access Solana mainnet."` — and the
  catalog it returns is a single `"Sandbox test market"`. Always check `apiKeyId` in the response
  against the key you meant to use.

The key is backend-only by Panta's own instruction: never in a mobile app, a frontend, or a query
string. It lives in Railway on `chumbucket-calls-bff` as `PANTA_API_KEY` (live) and
`PANTA_API_KEY_TEST`.

---

## 2. The live catalog is nearly empty

Sampled 50 real mainnet markets:

| | |
| --- | --- |
| with a `title` | **0** |
| with a `description` | **0** |
| `status: open` | **2** |
| `resolved` | 38 |
| open **and** titled **and** priced | **0** |

The detail endpoint does not rescue this — fetching the one open market by id returns
`title: ""`, `description: ""`, `yesPrice: null`.

Status distribution: `resolved` 38, `secondary_active` 5, `cancelled` 3, `open` 2, `secondary` 2.

**Conclusion: Panta cannot be Chumbucket's catalog.** There is nothing to put in front of a person.
This is not a criticism of Panta — it is a young permissionless venue whose markets are
user-created, and an empty catalog is what that looks like early.

---

## 3. Creating a market costs 50 USDC

Verified by quoting a real market with the live key:

```
paymentUsdc              50000000   =  50.00 USDC
  liquidityInjectionUsdc 10000000   =  10.00 USDC
  platformRevenueUsdc    40000000   =  40.00 USDC
expectedEventPda         HUimcA6B4VENfTnZGkRBkyZa1vDwJEpaz45k2X6QogkR
```

So Chumbucket **cannot create markets at volume**. Three curated questions is $150. A feed is
impossible. Any design that assumes "a call creates a market" is dead on arrival at this price.

Creation flow, for when a small number is worth it:

1. `POST /markets/create/image-upload/` *(optional helper — signed Cloudinary fields)*
2. `POST /markets/create/quote/` → fee + `createId`, session lasts ~5 minutes
3. `POST /markets/create/build/` → unsigned `VersionedTransaction` + blockhash (~60s)
4. **You** sign and broadcast on your own RPC — Panta never broadcasts
5. `POST /markets/register/` → verifies the on-chain create, writes catalog/oracle metadata

Constraints worth knowing before building: `imageUrl` is required and must be publicly reachable
(SSRF-guarded, no localhost/private hosts, no data URLs); `startTime` must be at least the on-chain
`minimumStartDelay` ahead — typically 3600s — unless `marketType: "breaking"` with
`eventInProgress`; `category` is one of `sports, crypto, politics, entertainment, finance, science,
world, other`.

---

## 4. Where Panta actually fits

Not as the catalog. As **the funded rail**.

Polymarket is read-only for us: real, titled, priced markets, and no way to take a position through
it. Panta is the mirror image — a thin catalog, but a complete **unsigned-transaction** buy/claim
lifecycle that the user signs with their own wallet. Panta never holds user keys, which is exactly
the boundary `PredictionVenue` was designed around (`createBuyOrder → UnsignedOrder`, mobile
verifies the envelope, the wallet signs).

So the honest shape:

- **Polymarket** — discovery. What a person browses and calls on.
- **Panta** — funding. Where a call optionally becomes a real on-chain position, and where a small
  number of Chumbucket-curated markets can live.

That split is what the roadmap always wanted; only the provider changed.

---

## 5. Wire-shape notes for the adapter

- Timestamps are **unix seconds** in live mode (`endTime: 1800637200`), but **ISO strings** in
  sandbox. Normalising one and not the other is a silent bug waiting to happen.
- Prices (`yesPrice`, `noPrice`, `primaryYesPrice`, `secondaryYesPrice`) are frequently `null`.
  A market with no price cannot be called on — `calls.snapshot_id` is a real FK the store refuses to
  null — so it must be filtered out, exactly as `markets.open` already does for Polymarket.
- `status` carries `open`, `resolved`, `cancelled`, `secondary`, `secondary_active`. `cancelled` is
  a real value here, where Polymarket could not express it at all — so Panta can populate the `VOID`
  resolution that `CallOutcome` has always had a branch for and never seen.
- `marketId` is a base58 Solana address, not an opaque id.
- Money is USDC **base units** (integer strings, 6 decimals) — the frozen contract's money rule
  already says integer base units as a string, so this lines up.
- List responses are `{items, nextCursor}`.

---

## 6. Open decisions for the founder

1. **Spend 50 USDC** to create one real Chumbucket market on mainnet and prove the full live
   lifecycle end to end? The entire flow can otherwise be built and demonstrated on the sandbox key
   for nothing — Panta provides it deliberately, and the side-track judges are Panta themselves.
2. **Fund a wallet** with USDC for creation fees and/or a smallest-size test buy. Nothing is signed
   or spent without an explicit go-ahead and a quoted number first.
