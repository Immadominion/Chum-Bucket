# Solana dApp Store listing: Chumbucket 1.0.34 (calls product)

Status: **draft, not submitted.** `config.yaml` already carries this copy for the
`dapp-store` CLI. Nothing in this folder uploads or publishes anything by itself.

## Before submitting (owner)

1. Build with `scripts/build_release.sh` using the original upload key. The script
   refuses any APK whose signer is not `315b22c7…e1c7` (the certificate in
   `config.yaml`), so a passing build is already the right key.
2. Replace `media/screenshot1.png` … `screenshot4.png`. The current files show the
   old friend-challenge product (wallets, escrow, "Challenge a new friend").
   Shot list below.
3. Replace the policy URLs. `license_url`, `copyright_url` and `privacy_policy_url`
   still point at `chum-bucket.vercel.app`, whose privacy page is a placeholder.
   Publish counsel-reviewed Terms and Privacy (they must mention Firebase
   Crashlytics, Supabase, Panta, USDC, Google sign-in and the Telegram analytics,
   or that analytics must go) and point these fields at them.
4. Smoke-test the release APK on a Seeker: MWA sign-in, a free call, Back/Fade,
   share a receipt link (opens in the app once `assetlinks.json` is live), push,
   and Settings > Share crash reports.
5. `media/banner.png` ("Chumbucket mobile app") and `media/icon.png` can stay.
6. **Decide the legacy friend challenges before submitting.** A release build is on
   mainnet, and People > Friends > (a friend) still opens the old SOL-staked
   challenge, which locks real SOL in the escrow program
   `D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1`. That program is deployed on
   mainnet (checked read-only on 2 Oct 2026), so those stakes are real money,
   resolved by a witness rather than a venue. The copy below does not describe
   that flow. Either archive it into read-only history (prod-readiness audit
   M13) or add it to the copy and the Terms.

## Catalog copy (en-US)

**Name** (≤ 30): `Chumbucket`

**Short description** (≤ 30, currently 30): `Follow the calls. Back or fade`

**Long description**

> Chumbucket is a people-first feed of calls on real prediction markets. See what
> named people call on live Panta markets, the price they called it at, and how
> often they have been right.
>
> Back a call, fade it, or challenge a friend to go on record. Calls are free and
> carry no money.
>
> Every call locks who made it, which side, when and at what price. When the market
> resolves on Panta, the call becomes a receipt nobody can edit, and you can share
> it as a chumbucket.fun link anyone can open.
>
> Want skin in the game? Take the position on Panta with USDC on Solana mainnet,
> approved in your own wallet. Chumbucket never holds your funds.
>
> Funded positions are real money: prices move and you can lose what you put in.
> Check that prediction markets are legal where you live.

**What's new in 1.0.34**

> A new Chumbucket, built around people and their calls.
> - Follow what people call on live Panta prediction markets
> - Back, fade or challenge any call, free
> - Every call becomes a receipt you can share at chumbucket.fun
> - Optionally take the position on Panta with USDC from your own wallet
> - Crash reports are now opt-in (Settings)

**Saga/Seeker features**: Sign in and approve trades with Mobile Wallet Adapter,
including Seed Vault on Seeker.

Every sentence above is checked against the 1.0.34 build. If the build changes,
change the copy: for example, if Google sign-in ships, step 1 of the testing notes
should mention it; if funded positions are switched off on the BFF
(`FUNDED_POSITIONS`), drop the "skin in the game" paragraph before submitting.

## Testing notes for reviewers

Calls are free. A reviewer needs a wallet on the device but no funds.

1. Open the app and sign in with your wallet (Mobile Wallet Adapter / Seed Vault).
2. **Home** shows what people are calling. Tap a call to see its receipt: who,
   which side, when, the entry price, and the result once Panta resolves it.
3. **Markets**: open a market, pick Yes or No, optionally add a reason, and lock
   your call. It appears on your profile.
4. On someone else's call, tap **Back**, **Fade** or **Challenge**. All are free.
5. **Share** a receipt. The link (`https://chumbucket.fun/c/…`) opens in the app on
   a phone that has it installed and as a web page anywhere else.
6. Optional, real money: a funded position is a real trade on Panta in USDC on
   Solana mainnet, approved in your wallet, capped at 100 USDC per approval.
   Reviewing the app does not require placing one.
7. **Settings > Share crash reports** is off by default; nothing is sent unless it
   is turned on.

No test account or credentials are needed.

## Screenshot list

Format: portrait PNG from the **release build on a Seeker**, same size for every
shot (1080×2400 recommended; the current files are 1200×1200 square mockups). Real
accounts that agreed to appear, real markets. Nothing labelled **DEMO DATA** may
appear: that label means the build is on the seeded catalog, which a store build
can never be.

| # | File | Screen | Must show |
| - | ---- | ------ | --------- |
| 1 | `screenshot1.png` | Home feed | Several named people's calls with sides, entry prices and Back / Fade |
| 2 | `screenshot2.png` | A resolved receipt | "Correct" (or "Incorrect"), locked time, entry price, who resolved it |
| 3 | `screenshot3.png` | Market detail with the call composer | Panta Yes/No prices, closing time, Yes/No choice |
| 4 | `screenshot4.png` | A person's profile | Their record (settled / right) and recent calls |
| 5 | optional | Funded-position review sheet | The real-money risk copy and the wallet approval step |
| 6 | optional | A shared link on chumbucket.fun | The web receipt with "Open in the app" |

Optional shots need matching `- purpose: screenshot` entries under `release.media`
in `config.yaml` once the files exist; the CLI rejects entries for missing files.
