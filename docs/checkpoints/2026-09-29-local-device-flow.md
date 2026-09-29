# Existing Profile/Settings on Seeker + local PostgreSQL — 29 September 2026

## Outcome

No separate hosted database/project is needed for this test. The connected
Seeker ran the existing `ProfileScreen` → `ProfileSettingsSheet` →
`IdentityLinkSheet` against the mounted Bun BFF, real PostgREST and a disposable
local PostgreSQL cluster over USB loopback. Both the manual invocation and the
fresh, fully scripted repeat passed **5 / 5 device cases**.

Cases: link succeeds on the same canonical person; wallet cancellation; missing
reviewed ownership evidence; an account already linked to somebody else; and a
lost HTTP reply after commit followed by successful retry from Settings.
Every case returns to the original profile, then re-mounts that production
screen and fetches the original record again. No create-profile fork/RPC runs.
SQL independently verifies all five original canonical ids, names, handles,
wallet mappings, histories and receipts. Exactly two people become linked and
three proof audits exist (the retry signs a fresh proof).

**Scope of evidence:** Google consent/issuer and wallet-app approval are
synthetic. The real `MwaExistingAccountWallet` message/metadata checks, Dart
Ed25519 signing, server verification, HTTP adapters, canonical binding SQL,
PostgREST roles and production Profile/Settings widgets run. Unrelated Arena,
balance and connectivity effects are isolated; this is not the complete app,
real Google callback, real MWA approval, physical restart or Panta E2E signoff.

## Fixes found while running it

1. **Offline font loading:** the first phone run raised a Montserrat download
   exception under the localhost-only HTTP guard. The existing body typeface
   was not bundled. Added unmodified Regular (400) and Medium (500) assets,
   exact SHA-256/length matches for the locked `google_fonts 8.1.0` descriptors,
   plus OFL license and provenance. No theme, typography, layout or route was
   replaced. A regression disables font HTTP fetching and loads both fonts.
   PP Neue Machina display styles remain unchanged.
2. **Incomplete asset security inventory:** adding an asset-list comment made
   the `.env` guard stop reading the list. It now parses the complete YAML,
   including quoted/commented and flavor-specific paths, and rejects hidden
   path segments. Two regressions prevent silent truncation. `yaml 3.1.3` was
   already locked; it is now an explicit dev dependency.
3. **Generated-host toolchain:** the first Android build selected AGP 9 from
   the current Flutter template; the locked wallet plugin's Android-31 AAR
   check failed. The repeatable host uses the product's AGP 8.7 / Kotlin 2.1.21 /
   Gradle 8.10.2 toolchain, without Google Services or release signing. No plugin
   cache or production Android build file was changed.

The application-debugging workflow drove the phone reproduction, boundary
isolation and regressions before rerunning the affected flow.

Bundling follows the package's [font asset guidance](https://pub.dev/packages/google_fonts/versions/8.1.0),
with [Montserrat's OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/OFL.txt).
The bundled font bytes total 350,936; hashes are in
`assets/fonts/Montserrat/README.md`.

## Files / product branches

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`, starting HEAD `27ce57e`.

- `tool/device_account_flow_test.dart`: five actual-device widget/HTTP cases;
  localhost-only socket guard and separate-package assertion.
- `assets/fonts/Montserrat/{Montserrat-Regular.ttf,Montserrat-Medium.ttf,OFL.txt,README.md}`:
  existing body font, license and hashes.
- `test/bundled_body_fonts_test.dart`: no-HTTP font loading regression.
- `test/app_config_test.dart`: complete YAML asset inventory + two regressions.
- `pubspec.yaml`, `pubspec.lock`: font assets, six test-only additions including
  SDK `integration_test`; explicit already-locked YAML dependency. Existing
  application dependency versions are unchanged.
- This checkpoint and the previous integration checkpoint's next-gate correction.

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`, starting HEAD `eb38486`.
Implementation commits: mobile `9784557`, API `3bdf25c`; a subsequent documentation
commit normalizes upstream license whitespace and records these references.

- `scripts/verify-account-link-local.ts`: opt-in device fixtures/report mode;
  representative legacy profile read RPC and fields in its own new database.
- `scripts/verify-account-device-local.ts`: fresh cluster + generated separate
  Android host + serial-targeted USB reverse + five device cases + SQL assertions
  + installed-app preservation check + cleanup.

`main.dart`, home/navigation/profile widgets, application routes, migrations and
Panta configuration are unchanged. No original dirty checkout was edited:
20 canonical-mobile / 138 reference-mobile / 1 original-API dirty entries remain.

## Exact final verification

| Check | Actual result |
| --- | --- |
| Manual Seeker device run after bundling font | `00:21 +5: All tests passed!`, exit 0 |
| Fresh scripted Seeker/local-DB repeat | `00:21 +5: All tests passed!`; SQL/app preservation PASS; runner exit 0 |
| Client-role checks in each local run | 10 anon/authenticated denials for private claim tables and privileged RPCs |
| Device DB preservation | 5 original people/receipts; 2 linked people / 3 proof audits; at least 10 actual legacy profile RPC reads; no profile creation |
| Host-side cross-language account run | 6 pass / 0 fail, exit 0; forged issuer credential refused |
| Targeted existing account UI/controller tests | 47 pass / 0 fail, exit 0 |
| Font + asset configuration tests | 11 pass / 0 fail, exit 0 |
| Full Flutter tests | `00:24 +711 ~7: All tests passed!`, exit 0 |
| Targeted analysis of three changed/new Dart files | No issues, exit 0 |
| Full Flutter analysis | 0 errors / 0 warnings / 275 existing info, 5.2s, exit 1 |
| API typecheck | `tsc --noEmit`, exit 0 |
| API identity transport regressions | 24 pass / 0 fail, 68 assertions, exit 0 |
| Full API tests | 736 pass / 38 skip / 0 fail; 2510 assertions; 774 tests / 57 files; 3.40s; exit 0 |

Flutter's seven skips include the six separate opt-in host cases (all six ran
above). Optional live-DB environment variables were explicitly unset for the
default API suite. Android builds retain locked-dependency Kotlin/deprecation
warnings; no SDK/plugin upgrade is implied by this checkpoint.

Before fixes: the first generated-host build failed; the first phone run had
0 pass / 5 fail after the font exception cascaded through the test binding; and
the first full Flutter run after the font addition had 708 pass / 7 skip / 1 fail
in the brittle asset-list guard. Final results above include both corrections.

## Reproduce

From the API product worktree, with the Seeker attached and unlocked:

```sh
POSTGREST_BIN=/absolute/path/to/postgrest \
FLUTTER_BIN=/absolute/path/to/flutter \
ADB_BIN=/absolute/path/to/adb \
bun --no-env-file scripts/verify-account-device-local.ts --run SM02G40619141343
```

Do not run the device test directly from the production mobile project: its
normal application id belongs to the installed app. The runner generates
`dev.cleva.chumbucket.localtest` in an owner-only temporary directory and refuses
a pre-existing test package. It reuses the current product library/screens and
locked assets/dependencies; no second product shell or profile setup is added.

All BFF, gateway, PostgREST and database listeners bind 127.0.0.1. Only the
runner's fresh ports are forwarded to the selected phone. Those mappings are
removed afterward; pre-existing reverse mappings are preserved. Android HTTP
cannot escape localhost, backups are disabled in the test host and no OAuth
intent filters can intercept the installed app's callback. The fixture endpoint
contains synthetic credentials only; none is compiled into the APK or logged.
The Google port has no durable SDK persistence. No real wallet/keypair is opened.

Only the account-link representative schema/two claim migrations are applied,
not production's full migration history. The normal PostgreSQL16 service,
production credentials, provider APIs and databases are untouched.

## Device / retained artifacts

Seeker serial: `SM02G40619141343`. Installed `dev.cleva.chumbucket` remained
version `1.0.2`, code `2`, lastUpdateTime `2026-09-28 00:54:23`. It was not
replaced, uninstalled or cleared. The scripted run additionally compared a hash
of this installed-app metadata before/after.

The temporary synthetic test package was removed after each successful run;
the generated hosts/APKs and stopped test databases are retained for inspection
and reproducible reinstall. No user data was deleted.

- Manual host: `/private/tmp/chumbucket-account-device.0FnesB`.
  Final APK SHA-256: `ec33a1fc69906f87193de461b8fdeb7d7f2a4c1854e071504d734abbe70deb28`.
- Scripted host: `/private/var/folders/zm/v0w94xb95p11_5df6rxm0js80000gp/T/chumbucket-account-device-OQHeUT`.
  APK SHA-256: `6cb7ad35989d70f61bb419d943ddef95abb0567918946b396d79cccffc580907`.
- Manual device database: `/private/var/folders/zm/v0w94xb95p11_5df6rxm0js80000gp/T/chumbucket-account-flow-DOx1QQ/isolated-db`.
- Scripted device database: `/private/var/folders/zm/v0w94xb95p11_5df6rxm0js80000gp/T/chumbucket-account-flow-mjRRU4/isolated-db`.
- Host-only database: `/private/var/folders/zm/v0w94xb95p11_5df6rxm0js80000gp/T/chumbucket-account-flow-D3Ou4q/isolated-db`.

`pg_ctl status` independently confirmed both device clusters stopped. APK
filename checks found no `.env`, Firebase Admin or deploy-keypair paths; that is
not a claim of a complete release security audit.

## Next packet / remaining gates

Use this local/device mechanism for Panta's durable **free** call → Back/Fade →
immutable receipt flow inside the existing four-tab app. Panta remains the only
live provider; funded trading stays off and no wallet funding is needed here.
Real Google/MWA consent, Panta evidence/device continuity, complete navigation /
return-loop release testing and founder credential remediation remain separate
gates. No push, deployment, production write, trade or credential rotation occurred.
