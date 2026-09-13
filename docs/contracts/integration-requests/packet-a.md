# Packet A — integration requests (identity, RLS, wallet proof)

**Raised:** 13 September 2026 · **Packet:** A · **Target repo:** API worktree (`product/social-calls-api`)

Three requests. **Only #1 is required** for Packet A to be reachable by a client. #2 and
#3 are hardening/ergonomics and the packet ships correctly without them — each states
exactly what it is being built against in the meantime.

Nothing in this packet edits an integration-owned file. Everything below is a patch for
the integration owner to apply.

---

## 1. `src/api/router.ts` — mount `authRouter` (REQUIRED)

**Why it cannot be avoided.** Contract §6 gives Packet A `src/api/authRoutes.ts` and gives
the integration owner `src/api/router.ts`. A tRPC sub-router is reachable only once it is
a key on the parent router (§1: "A sub-router is one added key. No `mergeRouters`, no
registry."). Nothing else in the packet can do this.

**What breaks without it.** Every procedure in `authRoutes.ts` is unreachable over HTTP.
Mobile cannot obtain a wallet nonce, cannot link a wallet, and cannot resolve its Supabase
session to a canonical `public.users.id` — which means the pivot's invariant 3 has no
transport. The migrations and the service are already correct and fully tested; this is
purely the wire-up.

**Exact patch** — two lines, one import and one router key:

```diff
--- a/src/api/router.ts
+++ b/src/api/router.ts
@@
 import { streamEvents } from "./eventStream.ts";
 import { authedProcedure, guard, publicProcedure, router } from "./trpc.ts";
 import { verifyCallProof, verifyGenericAction, verifySocialAction } from "../auth/WalletSignature.ts";
+import { authRouter } from "./authRoutes.ts";
@@
 export const appRouter = router({
+  // Packet A — identity, wallet proof, legacy claims. Self-contained: it reads
+  // ctx.app.config and builds its own store lazily, so nothing in createApp changes.
+  auth: authRouter,
+
   // ── health / meta ────────────────────────────────────────────────────────
   health: publicProcedure.query(({ ctx }) => ({
```

Resulting client paths: `auth.identityStatus`, `auth.whoami`, `auth.requestWalletNonce`,
`auth.linkWallet`, `auth.claimLegacyIdentity`.

**Built against in the meantime.** Every test in `tests/authIdentity*.test.ts` drives the
router through `authRouter.createCaller(ctx)`, using the same `Context` shape
`makeContext` produces. Mounting changes no behaviour, only reachability.

---

## 2. `src/config.ts` — an `authIdentity` block for the SIWS allowlist (RECOMMENDED)

**Why.** A SIWS proof is bound to a `domain` and a `uri`, and the server must hold an
allowlist of both — otherwise a phishing origin can request a challenge that its own
domain satisfies. That allowlist is deployment configuration, and `AppConfig` is where
this codebase keeps deployment configuration.

**What breaks without it.** Nothing breaks. `src/auth/AuthIdentityRuntime.ts` already
reads `config.authIdentity` defensively and falls back to
`FIXTURE_AUTH_IDENTITY_POLICY` — a hardcoded, deny-by-default allowlist of exactly
`chumbucket.app` / `https://chumbucket.app`. That fixture is safe to ship: it denies every
other origin. The cost of not applying this patch is that changing the product domain, or
running a staging origin, requires a code change instead of an env var.

**Exact patch:**

```diff
--- a/src/config.ts
+++ b/src/config.ts
@@ export interface AppConfig {
   /** External indexer/webhook integration settings. */
   indexer?: {
     heliusWebhookAuth?: string;
   };
+  /**
+   * Packet A — SIWS wallet-proof policy. The domain/uri allowlist a signed
+   * message may name, and how long a challenge stays redeemable. Absent → the
+   * fixture allowlist in src/auth/AuthIdentityRuntime.ts (chumbucket.app only).
+   */
+  authIdentity?: {
+    siwsDomains?: string[];
+    siwsUris?: string[];
+    nonceTtlSeconds?: number;
+  };
@@ export function loadConfig(env: Record<string, string | undefined> = process.env): AppConfig {
   if (env.HELIUS_WEBHOOK_AUTH) {
     cfg.indexer = { heliusWebhookAuth: env.HELIUS_WEBHOOK_AUTH };
   }
+  if (env.SIWS_DOMAINS || env.SIWS_URIS || env.SIWS_NONCE_TTL_SECONDS) {
+    cfg.authIdentity = {
+      ...(env.SIWS_DOMAINS
+        ? { siwsDomains: env.SIWS_DOMAINS.split(",").map((d) => d.trim()).filter(Boolean) }
+        : {}),
+      ...(env.SIWS_URIS
+        ? { siwsUris: env.SIWS_URIS.split(",").map((u) => u.trim()).filter(Boolean) }
+        : {}),
+      ...(env.SIWS_NONCE_TTL_SECONDS ? { nonceTtlSeconds: num(env.SIWS_NONCE_TTL_SECONDS, 300) } : {}),
+    };
+  }
```

`resolveAuthIdentityPolicy` already clamps `nonceTtlSeconds` to 30–900s, so a bad env
value cannot widen the replay window; and an empty/whitespace-only list falls back to the
fixture rather than to "allow everything".

---

## 3. `src/api/trpc.ts` — carry the Supabase access token on `Context` (OPTIONAL)

**Why.** Packet A's procedures currently take `supabaseAccessToken` as a procedure
**input**, because `Context` is integration-owned. That is safe — the token is verified
against the issuer on every call, exactly as a header would be — but a header is the more
conventional place for a credential, keeps it out of request bodies and logs, and lets the
token be attached once rather than by every caller.

**What breaks without it.** Nothing. The input-based form is the tested, shipping design.

**Exact patch:**

```diff
--- a/src/api/trpc.ts
+++ b/src/api/trpc.ts
@@ export interface Context {
   /** The provider's own user id (e.g. Privy user id) — needed to ask the Auth
    *  port for that user's already-linked social identities (X/Google). */
   privyUserId?: string;
+  /** Raw Supabase Auth access token (x-supabase-authorization). Verified by
+   *  Packet A against GoTrue; never trusted unverified and never logged. */
+  supabaseAccessToken?: string;
 }

-export async function makeContext(app: App, token: string | undefined): Promise<Context> {
+export async function makeContext(
+  app: App,
+  token: string | undefined,
+  supabaseAccessToken?: string,
+): Promise<Context> {
   const user = await app.auth.verify(token ?? "");
-  if (!user) return { app };
+  if (!user) return { app, ...(supabaseAccessToken ? { supabaseAccessToken } : {}) };
   return {
     app,
     wallet: user.wallet,
     ...(user.privyWalletId ? { privyWalletId: user.privyWalletId } : {}),
     ...(user.userId ? { privyUserId: user.userId } : {}),
+    ...(supabaseAccessToken ? { supabaseAccessToken } : {}),
   };
 }
```

`src/api/server.ts` would then read the header and pass it through. If this lands, Packet A
will make `supabaseAccessToken` an optional input that defaults to `ctx.supabaseAccessToken`
— a one-line change per procedure, no behaviour change.

---

## Not a request — recorded for the integration owner

These are **production** issues from contract §8 that Packet A deliberately did **not**
fix, because fixing them is a production change needing founder approval. Two of them
interact with this packet and should be scheduled:

1. **§8 finding 1 — anon can still rewrite `public.users`.** `001_complete_schema.sql:587`
   grants ALL on every public table to `anon`/`authenticated`, and `users_insert` /
   `users_update` are `WITH CHECK (true)` / `USING (true)`. Packet A's migration does
   **not** fix this, but it does fence its own new column off: it revokes the table-level
   INSERT/UPDATE and re-grants every *other* column, so `users.auth_user_id` is
   service-role-only while every pre-existing column keeps exactly the access it had. That
   is the established pattern from `20260719161500`. **Consequence to be aware of:** after
   this migration there is no table-level INSERT/UPDATE grant on `public.users`, so a
   future column is fail-closed for anon until explicitly granted.

2. **§8 finding 2 — `sync_user_by_wallet` is anon-executable and upserts
   `ON CONFLICT (wallet_address) DO UPDATE SET user_id = EXCLUDED.user_id`.** Anyone can
   claim the globally unique slot for a wallet they do not control. Packet A provides the
   replacement path (`requestWalletNonce` → `linkWallet` → `attach_verified_wallet_v1`,
   which uses `ON CONFLICT DO NOTHING` and refuses to repoint an active address), but the
   legacy function is untouched and still live. **Retiring it is the change that actually
   closes the hole**; until then both paths exist side by side and the legacy one wins by
   being anon-callable.
