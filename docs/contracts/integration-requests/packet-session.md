# Integration request — Packet Session (primary Google sign-in)

**Raised:** 19 September 2026 · **Packet:** Session · **Owner to apply:** integration

The mobile app had no primary auth. The only Supabase sign-in in the codebase is
`ArenaProvider.linkOAuthIdentity`, which *links* a Google account onto a wallet that is
already connected — a linking flow, not a way in. `calls.create` needs a verified Supabase
session, so nobody could make a call.

This packet adds the missing half of the chain:

```text
  Google (Supabase OAuth)
       │  ChumbucketSession.signInWithGoogle()  →  dev.cleva.chumbucket://login-callback
       ▼
  access token  ─────────►  session.bffAuthToken  ──►  buildCallsRepository(authToken:)
       │                                               (Authorization: Bearer)
       │  auth.whoami
       ▼
  { userId, authUserId }
       │  userId = canonical public.users.id  (contracts §0 invariant 3)
       ▼
  CallsProvider.setViewer(userId)
```

New files, all additive, all inside `lib/features/authentication/session/` and `test/`:

| File | What it is |
| --- | --- |
| `lib/features/authentication/session/session_state.dart` | `SessionStatus`, `SessionErrorKind`, `SessionErrorCode`, `SessionError`, `SessionIdentity`, `SessionIdentityStatus`. No Flutter, no Supabase, no HTTP. |
| `lib/features/authentication/session/supabase_auth_port.dart` | The five-member seam over `Supabase.instance.client.auth`, plus `SupabaseFlutterAuthPort`, the real implementation. |
| `lib/features/authentication/session/session_bff_client.dart` | `auth.whoami` and `auth.identityStatus` over the same tRPC envelope the calls slice uses. |
| `lib/features/authentication/session/chumbucket_session.dart` | The `ChangeNotifier`. |
| `test/session_fakes.dart` | Fake `SupabaseAuthPort`; reuses `FakeBffServer` from `bff_calls_fixtures.dart`. |
| `test/session_bff_client_test.dart` | 19 tests — wire shape, every error mapping. |
| `test/session_chumbucket_session_test.dart` | 34 tests — all five states, all transitions. |
| `test/session_credential_safety_test.dart` | 5 tests — the token never reaches a URL, a `toString` or a user-facing message. |
| `test/session_main_wiring_test.dart` | 3 tests — **the §1 patch below, executed**: the exact provider graph it produces, against injected fakes. |
| `test/session_supabase_port_test.dart` | 9 tests — the two pure mappings inside the one class that touches `Supabase.instance` (seconds-vs-milliseconds expiry, `AuthChangeEvent` coverage, inert construction, the redirect scheme). |

**No new package.** `supabase_flutter` and `http` were already direct dependencies.
`flutter analyze`: 0 errors, 0 warnings, 282 info (unchanged baseline). `flutter test`:
524 passing (454 baseline + 70).

---

## 1. `lib/main.dart` — register the session and bind it to `CallsProvider`

Two edits. Order matters: `ChumbucketSession` must be registered **above**
`CallsProvider`, because the repository reads the token provider at construction time.

```diff
 import 'package:chumbucket/features/calls/data/calls_repository_factory.dart';
 import 'package:chumbucket/features/calls/providers/calls_provider.dart';
+import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
```

```diff
         ChangeNotifierProvider(create: (_) => ProfileProvider()),
         ChangeNotifierProvider(create: (_) => ArenaProvider()),
+        // Primary identity: Google -> Supabase session -> canonical
+        // public.users.id. `restore()` adopts a session already in storage and
+        // subscribes to auth changes for the life of the app. It is above
+        // CallsProvider on purpose — the repository below reads its token
+        // provider when it is constructed.
+        ChangeNotifierProvider<ChumbucketSession>(
+          create: (_) => ChumbucketSession()..restore(),
+        ),
         // The call/receipt slice. Which repository backs it is a build flag,
         // not an edit here:
         //   --dart-define=CALLS_BACKEND=bff --dart-define=CALLS_BFF_URL=https://…
-        // Defaults to the seeded mock, because the BFF is not deployed yet and
-        // a build silently pointing at localhost would fail every request on a
-        // real device with nothing on screen to explain why.
-        ChangeNotifierProvider<CallsProvider>(
-          create: (_) => CallsProvider(repository: buildCallsRepository()),
-        ),
+        ChangeNotifierProxyProvider<ChumbucketSession, CallsProvider>(
+          create:
+              (context) => CallsProvider(
+                repository: buildCallsRepository(
+                  // `FutureOr<String?> Function()`. Null is not an error — it
+                  // is what signed out looks like, and reading never needs a
+                  // session. The provider refreshes a token that is about to
+                  // expire before handing it over.
+                  authToken: context.read<ChumbucketSession>().bffAuthToken,
+                ),
+              ),
+          // The CANONICAL public.users.id, never authUserId and never a wallet
+          // (contracts §0 invariant 3). Null while signed out or while
+          // `auth.whoami` is still in flight; `setViewer` early-returns when it
+          // has not changed, so this is cheap on every notify.
+          update: (_, session, calls) => calls!..setViewer(session.userId),
+        ),
         ChangeNotifierProvider.value(value: ChallengeStateProvider.instance),
```

This supersedes §1 of `packet-e.md`, which wired `authToken` straight to
`Supabase.instance.client.auth.currentSession?.accessToken`. That reads a token but never
resolves a canonical user, so `setViewer` stayed null and the feed never personalised.

This exact graph — same ordering, same two callbacks — is built and driven in
`test/session_main_wiring_test.dart`, so the diff above is executed rather than merely
proposed. The only difference there is `ChangeNotifierProvider.value` (the test owns the
session's lifetime) and `backend: CallsBackend.mock` (the test measures the wiring, not
the BFF).

**Degraded without it:** nothing regresses — the app keeps working exactly as it does
today, signed out, read-only. Every line of this packet is exercised by `test/session_*`
regardless.

### Calling it from a screen

No screen change is required by this packet, and none is included. When one is added:

```dart
final session = context.watch<ChumbucketSession>();
switch (session.status) {
  case SessionStatus.signedOut:   // show "Sign in with Google"
  case SessionStatus.signingIn:   // spinner; the browser is open
  case SessionStatus.identityPending: // spinner; we have a token, not a viewer
  case SessionStatus.ready:       // session.userId is the viewer
  case SessionStatus.failed:      // session.error!.isNetwork ? retry : explain
}
await context.read<ChumbucketSession>().signInWithGoogle();
```

`session.isBusy` covers the two spinner states; `session.isReady` is the only state in
which a write may be offered.

---

## 2. `src/api/authRoutes.ts` — `auth.whoami` must be a mutation, not a query

**This is the one change without which the chain cannot complete.** It is one word.

```diff
   whoami: publicProcedure
     .input(z.object({ supabaseAccessToken: accessToken }))
-    .query(({ ctx, input }) =>
+    .mutation(({ ctx, input }) =>
       run(async () => {
         const identity = await serviceFor(ctx.app.config).authenticate(input.supabaseAccessToken);
         return { userId: identity.userId, authUserId: identity.authUserId };
       }),
     ),
```

`authRoutes.ts` is Packet A's file, so this is raised to the integration owner rather than
edited here (contracts §6).

### Why it cannot be avoided

`auth.whoami` takes the access token as a procedure **input**. tRPC derives the procedure
type from the HTTP method — GET is a query, POST is a mutation — so a *query* can only be
reached by a GET, and a GET carries its input in `?input={"json":{…}}`. Reaching the
deployed procedure therefore means putting a live Supabase JWT in a URL: in the Railway
access log, in every proxy between the device and the origin, and in any error report that
captures a request URI. A bearer credential in a query string is the leak this packet was
explicitly told not to create, and it is not one a client can mitigate.

Verified against the live deployment on 19 September 2026:

```
POST /auth.whoami  → 405 {"code":"METHOD_NOT_SUPPORTED",
                          "message":"Unsupported POST-request to query procedure
                                     at path \"auth.whoami\""}
GET  /auth.whoami?input={"json":{"supabaseAccessToken":"…"}}
                   → 401 AUTH_TOKEN_INVALID    (i.e. the procedure works, GET-only)
```

`allowMethodOverride`, `?_method=GET`, `x-http-method-override` and `?batch=1` were all
tried against the deployment; the standalone adapter accepts none of them.

So `SessionBffClient` POSTs the token in the body and sends it again as
`Authorization: Bearer`, and **will not** fall back to a GET. Until this patch lands, the
session reaches `SessionStatus.failed` with
`SessionErrorCode.whoamiMethodNotSupported` — an honest, named, non-blaming state
("This build of the server cannot finish signing you in yet. Nothing is wrong with your
account.") rather than a silent credential leak. The moment the patch lands, the same
client succeeds with no mobile change at all; `test/session_bff_client_test.dart` covers
both the 405 and the success.

Changing `.query` to `.mutation` is not a breaking change for any current caller: nothing
in the mobile app calls `auth.whoami` today.

**Degraded without it:** sign-in completes, the access token is held and handed to the
calls repository, but no canonical `userId` is resolved, so `setViewer` stays null and the
feed stays impersonal. Reading is unaffected.

---

## 3. `src/api/trpc.ts` — `Context` must carry the bearer (this is packet-d's ask, restated)

Writes need this, independently of §2. Confirmed against the deployment on
19 September 2026:

```
POST /calls.create  (no credential)            → 401 "connect your wallet (x-wallet)"
POST /calls.create  Authorization: Bearer <jwt> → 400 (input validation) — auth passed
```

Auth passes because the deployed server is wired `"auth":"dev"` (`GET /health` →
`wiring.auth`), and `DevAuth.verify` treats *the credential itself* as a Solana address
(`src/auth/DevAuth.ts`). So a Supabase JWT arrives as `ctx.wallet = "<the whole JWT>"`.
`callsRuntimeFor` then chains `supabaseViewerResolver` → `walletDirectoryViewerResolver`
(`src/calls/runtime.ts:185`), and:

* `supabaseViewerResolver` reads `ctx.supabaseAccessToken`, which `makeContext` never sets
  (`src/api/trpc.ts:29-37`), so it returns null;
* `walletDirectoryViewerResolver` looks up a person by a wallet address that is really a
  JWT, so it returns null too.

`requireViewer` therefore raises `UNAUTHORIZED` — *"Your account isn't linked yet"* — for
every signed-in person. `src/calls/viewer.ts` already anticipates this and reads the field
defensively, so the patch is additive:

```diff
 export interface Context {
   app: App;
   wallet?: Wallet;
   privyWalletId?: string;
   privyUserId?: string;
+  /** Raw Supabase access token from `Authorization: Bearer`. Read by
+   *  `supabaseViewerResolver`; never trusted without verification. */
+  supabaseAccessToken?: string;
 }

 export async function makeContext(app: App, token: string | undefined): Promise<Context> {
   const user = await app.auth.verify(token ?? "");
-  if (!user) return { app };
+  const supabase = token && token.split(".").length === 3 ? { supabaseAccessToken: token } : {};
+  if (!user) return { app, ...supabase };
   return {
     app,
     wallet: user.wallet,
     ...(user.privyWalletId ? { privyWalletId: user.privyWalletId } : {}),
     ...(user.userId ? { privyUserId: user.userId } : {}),
+    ...supabase,
   };
 }
```

The three-segment shape test is only a cheap way to avoid handing a bare wallet string to
the JWT verifier; it proves nothing and authorises nothing. `supabaseViewerResolver`
verifies the token against the issuer before it maps anything, and returns null on any
failure — so a forged value resolves to "no session", never to a user.

Also worth settling separately: the production deployment is running `auth: "dev"`, where
the credential *is* the identity with no verification at all. That is fine for the free
read path and is not fine for a funded one.

**Degraded without it:** reading, sign-in and `auth.whoami` all work; `calls.create`,
`calls.respond` and everything else behind `authedProcedure` refuse with
"Your account isn't linked yet."

---

## 4. Nothing else is requested

* No `pubspec.yaml` change — `supabase_flutter` and `http` are already direct dependencies,
  and `package:http/testing.dart` ships inside `http`.
* No Android or iOS change — `dev.cleva.chumbucket://login-callback` is already declared in
  `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`, and
  `DeepLinkHost` already leaves the Supabase callback alone for its existing handler.
* No migration — `public.users.auth_user_id` and `current_app_user_id()` are Packet A's,
  already applied, and `auth.whoami` is the client's only view of them.
* No change to `lib/features/calls/**`. `buildCallsRepository(authToken:)` and
  `CallsProvider.setViewer(String?)` were already the right shape.
