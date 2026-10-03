# Integration request — Packet Onboarding (the first run)

**Raised:** 3 October 2026 · **Packet:** fleet/onboarding2 (mobile from
`09aaff0`, API from `6ed8a4a`) · **Owner to apply:** integration

The onboarding experience spec (`fleet/onboarding-spec.md`), reconciled with
identity, trust, lockdown, release and wallets. The football/escrow carousel,
its terms dialog, its music and the multi-MB GIFs are gone. New code is under
`lib/features/onboarding/` (mobile) and `people.suggested` + `account.pushStatus`
(API).

## 1. Integration-owned files changed on the branch (please keep)

| File | Change | Why unavoidable |
| --- | --- | --- |
| `lib/main.dart` | `OnboardingProvider` → `OnboardingController` (one provider line + import) | The old provider drove the deleted carousel; the new one is read by the splash, Home, Markets and Settings. |
| `lib/shared/screens/home/home.dart` | `CallFeedScreen(topBanner: HomeSetupCard())`; the shell wrapped in `OnboardingHomeEffects`; `UsernameClaimPrompt(present: (c) => presentOnboardingOverlay(c, OnboardingRun.claimOnly))` opens onboarding's full-screen "Pick your @username" and says what became of the follows its friends step applied | Home is where a run lands (Following/Global choice, follow and restore snackbars, the waiting draft offered after a later sign-in) and where "Make Home yours" sits. The feed lays the card out only while it is offered, so everyone else's Home starts exactly where it did. |
| `pubspec.yaml` | removed `audioplayers` and the asset folders `assets/animations/whisk_ai_generate/`, `assets/images/ai_gen/whisk_animation_fallback/`, `assets/audio/` | Only the deleted carousel used them (checked by grep across lib/, test/, android/, ios/ and docs). |
| `pubspec.lock` | `audioplayers*` entries removed (by `flutter pub get --offline`) | Follows the pubspec. |

Not touched: `src/app.ts`, `src/api/router.ts` (the new procedures live in the
already-mounted `calls`/`people` and `account` routers).

Outside the onboarding feature, also changed (review, 3 Oct):
`lib/core/services/fcm_token_service.dart` asks the local-notifications
plugin for permission only after the OS granted it — asking again after a
refusal put a second OS dialog straight after the first on Android 13+ (two
dialogs for one "Notify me", the second refusal final);
`lib/core/services/push_registration.dart` shows no Settings → Notifications
row ("On") when this server sends no pushes, even where Android allows them.

`ios/Podfile.lock` still lists `audioplayers_darwin`; the next `pod install`
drops it (iOS is not built today).

## 2. Deploy order

1. Deploy the API branch (`people.suggested`, `account.pushStatus`, `avatarId`
   on person cards). Additive: older apps ignore them.
2. Build the app. Against an API without `account.pushStatus` the app asks
   for **no** notification permission anywhere (it never promises a push it
   cannot confirm is sent); against one without `people.suggested` the People
   step composes from deployed reads.

No migration.

## 3. Owner actions

1. **Publish the Terms and Privacy pages.** The consent line on sign-in, U1 and
   Welcome back opens `https://chumbucket.fun/terms` and `/privacy`
   (trust's `LegalLinks`). Both returned **404** on 3 Oct (the pages exist in
   the website source, `web/app/terms` and `web/app/privacy`, but are not
   deployed). Release blocker (spec §14 item 1).
2. **Push.** `account.pushStatus` is true only with `FIREBASE_SERVICE_ACCOUNT_JSON`
   set on the BFF and the notification scheduler on
   (`NOTIFICATIONS_SCHEDULER_ENABLED` not `false`). Until then "You're on
   record" says the receipt shows up in Activity and asks nothing.
3. **On a Seeker** (agents never sign): clean install → Welcome → Topics →
   First call → Lock → Google → username → R; again with the wallet door and
   with X if enabled; a legacy wallet profile (U1); reinstall with Google
   Backup on (B2: Home with "Welcome back, @handle."); a shared call link on a
   cold start (no Welcome in front); TalkBack at 2× font.
4. Decide on the primary button's contrast (white on coral, 3.0–3.6:1; spec
   §14 item 4) and the character art IP (spec §14 item 3). Both unchanged.

## 4. Tests

Mobile: `test/onboarding_{routing,data,store,copy,welcome,topics_people,first_call,account,entry,home}_test.dart`
(160 tests), `test/lockdown_account_test.dart` (the one notification policy),
`test/asset_budget_test.dart`. Opt-in captures for design review:
`flutter test --update-goldens --dart-define=CAPTURE_ONBOARDING=/abs/dir test/onboarding_visual_capture_test.dart`.
API: `tests/peopleSuggested.test.ts`, `tests/lockdownAccount.test.ts`.
