# Packet F — calls inbox and call record mount (applied 2026-10-01)

Referenced by the API's `src/api/notifications.ts` and
`src/notifications/config.ts`, but never filed until now. Recorded after the
fact because the owner chose to have it applied directly.

## File

`src/api/router.ts` (integration-owned), API commit `98a85b2`.

## Diff

```diff
 import { socialCallsRouter, socialMarketsRouter, socialPeopleRouter } from "./calls.ts";
+import { socialNotificationsRouter, socialRecordRouter } from "./notifications.ts";
 ...
   calls: socialCallsRouter,
   markets: socialMarketsRouter,
   people: socialPeopleRouter,
+
+  inbox: socialNotificationsRouter,
+  record: socialRecordRouter,
```

Paths: `inbox.list`, `inbox.unreadCount`, `inbox.markRead`, `record.mine`,
`record.get`.

## Why `inbox`, not `notifications`

The root router already has a legacy `notifications` procedure (wallet-keyed,
with `unreadCount` and `markNotificationsRead`), called by installed apps. A
tRPC key cannot be both a procedure and a namespace, and renaming the legacy
key would break every installed bell. The legacy procedures are untouched.
`tests/socialNotificationsMount.test.ts` pins both halves.

## What breaks without it

Nothing visibly; the calls inbox simply does not exist (`notifications.*`
answered "No procedure found"), so the app can show no Back / Fade / Resolved /
Rematch activity.

## Not in this patch

- `AppConfig.notifications` (config.ts) — the packet falls back to environment
  and defaults, as designed.
- A timer for `deriver.runOnce()` — derivation runs on read (`deriveOnRead`,
  default on), which is idempotent and bounded.
- A durable store — since added (API `7eccba5`): `SupabaseNotificationsStore`
  over the existing `social_notifications` and `call_category_records`, built
  inside the packet's own runtime module, so no integration file changed.
