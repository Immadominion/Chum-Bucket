# Integration request — Packet E (BFF-backed calls repository)

**Raised:** 13 September 2026 · **Packet:** E · **Owner to apply:** integration

Packet E adds `BffCallsRepository`, a real `CallsRepository` that speaks to the Bun/tRPC
BFF. **Nothing frozen was changed.** `calls_repository.dart`, `call_models.dart` and
`mock_calls_repository.dart` are untouched, and the slice still analyses clean and passes
its tests on `MockCallsRepository` today.

New files, all additive and all inside `lib/features/calls/data/` and `test/`:

| File | What it is |
| --- | --- |
| `lib/features/calls/data/bff_calls_repository.dart` | The eight `CallsRepository` methods against the §5 procedure table. |
| `lib/features/calls/data/calls_bff_transport.dart` | tRPC envelope + error mapping. A copy of the `arena_backend_service.dart` pattern, not an import of it. |
| `lib/features/calls/data/calls_bff_payloads.dart` | Wire → view-model translation for the Packet-C-local types. |
| `test/bff_calls_fixtures.dart` | Injected in-memory `http.Client` and FROZEN §3 payloads. |
| `test/bff_calls_repository_test.dart` | Round trips for all eight methods. |
| `test/bff_calls_errors_test.dart` | Error mapping, vocabulary safety, malformed envelopes, withheld crowd split. |

No new package. `http` was already a direct dependency, and `package:http/testing.dart`
(`MockClient`) ships inside it.

---

## 1. `lib/main.dart` — swap the repository (the entire migration)

Packet C's request §1 registers `CallsProvider` with `MockCallsRepository`. Moving to the
BFF is one constructor swap; nothing above `calls_repository.dart` changes.

```diff
 import 'package:chumbucket/features/calls/data/calls_repository.dart';
-import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
+import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
 import 'package:chumbucket/features/calls/providers/calls_provider.dart';
```

```diff
         ChangeNotifierProvider<CallsProvider>(
           create:
               (_) => CallsProvider(
-                repository: MockCallsRepository(
-                  latency: const Duration(milliseconds: 350),
-                ),
+                // Base URL comes from configuration — see §2. The session
+                // token is what the server authorises on; `viewerUserId` is
+                // never sent as a request field.
+                repository: BffCallsRepository(
+                  authToken: () =>
+                      Supabase.instance.client.auth.currentSession?.accessToken,
+                ),
               ),
         ),
```

`authToken` is a `FutureOr<String?> Function()`. Returning null is not an error: reading
never requires a session. Only writing does, and `BffCallsRepository` refuses a write with
`CallsSignedOutException` **before any request is sent** when `viewerUserId` is null, so a
signed-out app never fires a request that could only 401.

`baseUrl`, `httpClient`, `timeout` and `linkHost` are all injectable; the tests pass an
in-memory client and never open a socket.

**Degraded without it:** the app keeps running on `MockCallsRepository`. Everything in
Packet E is reachable from a test or a debug screen either way.

---

## 2. `lib/core/config/app_config.dart` — two optional keys

Not integration-owned by the letter of contract §6, so this is a request rather than an
edit only because `publicKeys` is a security decision (adding a key makes the value
readable in every release APK) and that decision is not Packet E's to take.

`BffCallsRepository` reads, in order: `CALLS_BFF_URL`, then `ARENA_BACKEND_URL`, then
`http://localhost:8787` — the same shape `ArenaBackendService` uses. **`ARENA_BACKEND_URL`
is already allowlisted**, and the Bun/tRPC server that serves the arena procedures is the
same one that will serve `calls.*` and `markets.*`, so nothing is required today.

Apply this only if the calls BFF is to live on a different host, or if share links must
point somewhere other than `https://chumbucket.app`:

```diff
     'ARENA_BACKEND_URL',
+    'CALLS_BFF_URL',
+    'CALLS_LINK_HOST',
     'SOLANA_NETWORK',
```

```diff
     'ARENA_BACKEND_URL': String.fromEnvironment('ARENA_BACKEND_URL'),
+    'CALLS_BFF_URL': String.fromEnvironment('CALLS_BFF_URL'),
+    'CALLS_LINK_HOST': String.fromEnvironment('CALLS_LINK_HOST'),
     'SOLANA_NETWORK': String.fromEnvironment('SOLANA_NETWORK'),
```

Neither name trips `forbiddenKeyFragments`, and neither value is a secret: both are hosts.

**Degraded without it:** the calls BFF must share a host with the arena backend, and share
links are built against `https://chumbucket.app` — which is what `kCallDeepLinkHosts` in
`call_deep_link.dart` already expects.

---

## 3. What Packet B must decide — the §5 table is silent on identity

Not a patch. These are the places where the §5 procedure table and the frozen
`CallsRepository` interface do not line up, and where the client has taken a position that
the server has to agree with or the loop is broken.

### 3.1 `viewerUserId` is a parameter of every interface method and a field of no procedure input

The frozen interface takes `viewerUserId` on six of eight methods. **Not one §5 input
carries a viewer field.** Packet E treats that as deliberate and correct, and sends the
session instead:

* `Authorization: Bearer <token>` on every request, from the injected `authToken`.
* `viewerUserId` is used **only** client-side, to decide before any request is sent
  whether a write may be attempted at all.

Contract §8 finding 4 records "several tRPC read procedures take `wallet: z.string()` on
`publicProcedure` with no proof at all" as a live production defect, and §0 invariant 3
says nothing authorises on a client-supplied string. A `viewerUserId` in a request body
would be exactly that defect again: it would let any caller read a `followers`-only call,
read someone else's `viewerHasCalled`, or unlock a crowd split by naming a stranger who
has already called.

**Packet B must therefore derive the viewer from the session**, and the three server-side
behaviours in packet-c.md §5 (`crowdSplit` withheld, back/fade minting the actor's own
call, service-derived results) must key off that same session identity. A test asserts
that no request this client sends contains `userId` or `viewerUserId`.

If Packet B chooses a different session mechanism (a cookie, a different header name), it
is one line in `calls_bff_transport.dart` — but it must not be a body field.

### 3.2 `calls.feed` in `following` mode with no session

The interface says `following` is "unavailable" when `viewerUserId` is null, but does not
say what unavailable means. The client passes the mode through unchanged and lets the
server answer; an `UNAUTHORIZED` comes back as `CallsSignedOutException`, which is the
state the UI already renders. Packet B should return `UNAUTHORIZED` rather than an empty
page, so the difference between "you follow nobody" and "we don't know who you are" stays
visible.

### 3.3 `calls.invitations` takes `{}` but the interface takes `viewerUserId`

`MockCallsRepository` returns `const []` when signed out rather than throwing, and Packet E
matches that exactly — including sending no request at all. So `calls.invitations` is only
ever called with a session. It should still be a protected procedure.

### 3.4 `fromCache` is on two view models and on no payload

`CallFeedPage.fromCache` and `MarketDetail.fromCache` have no §5 field, and cannot: a page
that came from the BFF is live by definition. They stay `false`. Only a caching decorator
around this repository may ever set them, and there is none today.

### 3.5 `ChallengeInvitation` has no frozen shape

§3 freezes `CallResponse.kind = 'challenge'` but declares no invitation type, so
packet-c.md declares a Packet-C-local one. Packet E parses exactly those field names:
`id`, `fromUserId`, `toUserId`, `marketId`, `sourceCallId`, `responseId`, `note`,
`createdAt`. There is no amount, no escrow and no transaction, and
`ChallengeInvitation.hasEscrow` is structurally false — a money field on the wire has
nowhere to land even if one were sent.

### 3.6 The two invariants the client now enforces on the response

`calls.respond` is checked against the contract rather than trusted:

* `back` / `fade` with no `resultingCall` → `CallVocabularyException`.
* `challenge` with a `resultingCall` → `CallVocabularyException`.

A BFF that drifts here would otherwise show a user a call that silently did not happen, or
a challenge that silently became one.

---

## 4. Error mapping Packet B should emit

The client distinguishes four states and nothing else. tRPC's `error.json.data.code` is
what it reads, falling back to `httpStatus` and then to the HTTP status.

| tRPC code | Client state |
| --- | --- |
| `UNAUTHORIZED` | `CallsSignedOutException` |
| `BAD_REQUEST`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `PRECONDITION_FAILED`, `UNPROCESSABLE_CONTENT`, `TOO_MANY_REQUESTS`, `PARSE_ERROR`, `METHOD_NOT_SUPPORTED`, `PAYLOAD_TOO_LARGE`, `UNSUPPORTED_MEDIA_TYPE`, `TIMEOUT`, `CLIENT_CLOSED_REQUEST` | `CallsRejectedException`, **carrying the server's `message` verbatim to the user** |
| `INTERNAL_SERVER_ERROR`, `NOT_IMPLEMENTED`, `BAD_GATEWAY`, `SERVICE_UNAVAILABLE`, `GATEWAY_TIMEOUT` | `CallsFailure` |
| — no response at all (DNS, refused socket, client timeout) | `CallsOfflineException` |

Two consequences worth stating:

1. **A refusal message is user-facing copy.** "This market is closed — no new calls." is
   rendered as written. Do not put a stack trace, a table name or a constraint name in it.
2. **A 5xx is never "you're offline".** The server answered, so saying the device has no
   connection would be a lie. Only a round trip that never completed is offline.

---

## 5. Not requested

- No change to `calls_repository.dart`, `call_models.dart` or `mock_calls_repository.dart`.
  All three are frozen and all three are untouched.
- No new package.
- No migration.
- No change to `pubspec.yaml`, `lib/shared/screens/home/home.dart`, the bottom navigation,
  `android/**`, `ios/**`, `lib/features/authentication/**` or `lib/features/arena/**`.
  `arena_backend_service.dart` in particular was read and copied from, never imported and
  never edited.
