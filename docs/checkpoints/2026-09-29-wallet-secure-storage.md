# Wallet secure-storage checkpoint — 29 September 2026

## Outcome and scope

MWA reauthorization credentials now use the existing `flutter_secure_storage`
dependency instead of a plaintext SharedPreferences record. Valid existing logins
migrate with their wallet, label and SNS metadata intact. No account/profile is
created, merged or moved. The existing app navigation, wallet entry flow and
Panta-only / funded-trading-off configuration are unchanged.

The secrets-safety skill focused this increment on credential storage, sanitized
errors and backup exclusions. No exposed credential file was opened, scanned or
printed. No external credential was rotated.

Mobile worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`
on `product/social-calls-v3`, starting at `08cb865`.

Changed/added files:

- `lib/features/authentication/session/mwa_auth_result.dart`: existing model moved
  without changing the serialization shape; strict key/address/URI validation and
  redacted debug/error representations.
- `lib/features/authentication/session/mwa_session_storage.dart`: named secure
  record, migration, verified readback, serialized renewal/logout, sign-out marker.
- `lib/features/authentication/providers/mwa_auth_provider.dart`: use that storage,
  retain the model export for existing callers, refuse incomplete restoration.
- `android/app/src/main/AndroidManifest.xml`, `res/xml/backup_rules.xml` and
  `res/xml/data_extraction_rules.xml`: backup/transfer exclusions.
- `test/mwa_session_storage_test.dart`, `test/mwa_storage_fakes.dart` and
  `test/app_session_persistence_test.dart`: storage and provider regressions.
- `tool/wallet_storage_probe.dart`: opt-in synthetic device probe, separate package
  only. It has no Supabase, provider API, wallet-signing or transaction behavior.
- This checkpoint.

API worktree `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`
on `product/social-calls-api` remains clean at `d9068b9`.
No dependencies or lockfiles changed in either product worktree.

The three original user checkouts were not edited. Their read-only dirty-entry
counts remain 20 (canonical mobile), 138 (legacy mobile, `-uall`) and 1 (API).
Recovery backups were not changed.

## Storage behavior

Android uses a dedicated encrypted preferences file and the plugin's Keystore
integration. All operations use identical constructor options. Automatic
reset/delete-all on error is disabled. iOS is configured for a device-only,
unlocked Keychain record with synchronization disabled; iOS was not device-tested.
The locked 9.2.4 plugin may internally fall back from EncryptedSharedPreferences
to its Keystore-backed cipher, not to plaintext. This is not a StrongBox or
hardware-key attestation claim.

Migration writes the secure record, reads back exact bytes, commits a non-secret
state marker and only then removes the two old wallet preferences. Missing,
corrupt or conflicting records fail closed. A prior successful migration cannot
fall back to a residual plaintext credential. An unmarked secure record is only
adopted to finish an interrupted migration with an identical valid old login.

Production providers share one storage queue. Sign-out invalidates pending work,
writes a signed-out marker, attempts both storage removals and verifies absence.
A failure keeps the existing sign-out controller locked for retry. A surviving
token behind a signed-out marker cannot become a login on the next startup.
If every persistence operation fails, durable deletion cannot be guaranteed;
the controller must not report successful sign-out.

Only named wallet keys are removed; onboarding and unrelated on-device preferences
remain. Android backup rules exclude `chumbucket_wallet_secure.xml`, the plugin's
`FlutterSecureKeyStorage.xml` companion and `FlutterSharedPreferences.xml`, in old
cloud-backup rules and both Android 12+ cloud/device-transfer sections. Android
excludes whole files, so unrelated preferences in the latter file also will not
transfer to a different device. Backend profiles/history are unaffected.

Durability limit: 9.2.4 uses Android `SharedPreferences.Editor.apply()` internally.
Readback verifies plugin-visible state; it is not an fsync/power-loss guarantee.
Force-stop/cold-start persistence passed below. Sudden storage loss during migration
may still require wallet reconnection; missing secure state is never treated as
authenticated. Power-loss, full-device reboot, OS backup/restore and key-invalidation
fault injection were not exercised. Do not describe this as an atomic two-store
transaction or a complete release sign-off.

## Verification — actual results

```
flutter test --no-pub --reporter expanded
00:13 +708 ~1: All tests passed!
exit 0

flutter test --no-pub --reporter expanded test/mwa_session_storage_test.dart \
  test/app_session_persistence_test.dart test/app_sign_out_test.dart
00:00 +50: All tests passed!
exit 0

flutter analyze --no-pub
275 issues found. (ran in 3.8s)
0 errors / 0 warnings / 275 existing info
exit 1

bun --no-env-file run typecheck
$ tsc --noEmit
exit 0

bun --no-env-file test
712 pass / 38 skip / 0 fail
2442 expect() calls
Ran 750 tests across 56 files. [951.00ms]
exit 0

git diff --check
exit 0
```

Mobile added 32 tests over the prior 676 baseline. Coverage includes interrupted
migration, orphan/conflicting records, corruption, failed reads/writes/readback/
marker/removal, renewal/logout races, provider disposal, failed sign-out and retry,
metadata preservation, native-channel options and backup exclusions.

The final full and focused runs include the companion-file backup assertion.
Targeted analysis of all seven changed/new Dart files also reports `No issues
found!`, exit 0. All three database URL opt-ins plus `VERIFY_LOCAL_PG` were unset
for API verification. No database was started or contacted.

Environment/test corrections, not hidden passes:

- Missing `.dart_tool/package_config.json` caused the first analyzer invocation to
  report unresolved packages. `flutter pub get --offline` restored it, exit 0;
  `pubspec.lock` stayed unchanged.
- Initial focused tests: 49 pass / 1 fail because a macOS test assumed the plugin
  dispatched Android options. The plugin uses `dart:io Platform`; the corrected
  test verifies configured Android/iOS options separately and Android runs below.
- API initially had no installed packages: typecheck exit 127; tests 100 pass,
  11 skip, 47 fail / 47 module-loading errors. `bun --no-env-file install
  --frozen-lockfile --ignore-scripts` restored 172 locked packages, exit 0, without
  editing the lockfile. Final typecheck/tests are shown above.

## Seeker evidence — isolated synthetic package

Temporary project: `/private/tmp/chumbucket-storage-probe.ZBjLup`.
Application ID: `dev.cleva.wallet_storage_probe`; absent before this test.
Device: Seeker `SM02G40619141343` (the other attached Android device was not used).

The probe copies the two production storage/model files byte-for-byte, with the
same locked `flutter_secure_storage` 9.2.4, `shared_preferences` 2.5.3,
`shared_preferences_android` 2.4.12 and `solana` 0.31.2+1. It seeds only synthetic
data in its own sandbox and runs one stage per cold process start. Output contains
only fixed PASS/FAIL markers, never stored values or exception payloads.

Final probe APK build:

```
flutter build apk --debug --no-pub -t lib/probe_main.dart \
  --dart-define=WALLET_STORAGE_PROBE=true
exit 0

09-29 02:15:15.563  CHUM_STORAGE_PROBE: PASS migration
09-29 02:15:18.772  CHUM_STORAGE_PROBE: PASS cold-restart-and-renewal
09-29 02:15:21.466  CHUM_STORAGE_PROBE: PASS renewed-restart-and-signout
09-29 02:15:23.923  CHUM_STORAGE_PROBE: PASS signed-out-cold-restart
```

Each stage was separated by `am force-stop` and a cold activity launch. Only the
probe PID's fixed markers were read from logcat. Filename-only inspection revealed
the companion key-wrapper file, prompting its additional backup exclusion.
Boolean-only searches inside the probe sandbox found neither original/renewed
synthetic token text nor the old credential key in plaintext after migration and
renewal (grep exit 1, no output). `aapt dump xmltree` confirmed all three exclusions
in each section of the final compiled resource. No real app data was inspected.

SHA-256:

| Artifact | Hash |
| --- | --- |
| Production/probe `mwa_auth_result.dart` | `51bc02db615862040df1174873b63660b6e104c394307f32ab5f609d28735cb0` |
| Production/probe `mwa_session_storage.dart` | `43bd22d9a706dda3249e238f21254e24fbfb256978b32267c737b9d4d139a3ed` |
| Final probe APK | `f7c95c5875d2a2b7d2a6e3680736314fad9437908b2b045e07aeb593f9565e9d` |

The probe package and its synthetic data were uninstalled afterward (Success);
`pm path` confirms it is absent. The temporary host project/APK remain for inspection.
Chumbucket `dev.cleva.chumbucket` was never replaced, cleared or uninstalled:
version 1.0.2/code 2 and last update `2026-09-28 00:54:23` were identical before and
after. No production Chumbucket APK was built or installed in this increment.

To reproduce: generate a separate disposable Flutter Android project with the
exact probe application ID, add the four pinned dependencies above, copy the two
storage files into `lib/`, copy `tool/wallet_storage_probe.dart` into
`lib/probe_main.dart` and change only its two Chumbucket package imports to local
imports. Copy the two backup XML files and their manifest attributes. Build with
the explicit probe define, verify the APK package ID with `aapt`, install only if
that probe package is absent, launch/force-stop for the four stages, then uninstall
only that probe. Never run the entry point against Chumbucket's installed package.

## Next checkpoint and remaining release gates

Next: validate the existing-account linking path with a configured non-production
BFF and disposable database, then the complete Seeker app flow with the same
canonical person/profile/history. Do not enable Google claims without reviewed
ownership anchors, or install a replacement live-package build without confirming
its configuration and update signature.

This storage probe does not prove Google OAuth, MWA 2.0 compatibility, SIWS signing,
Panta live catalog/order behavior, database migrations or the whole app journey.
Existing credential rotation, legacy authorization review, account-claim approval
and Panta durable-runtime gates remain outstanding. Funded trading stays off.
No push, deployment, production write, provider contact, funding or trade occurred.

References consulted: [locked secure-storage package](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4),
[Android backup rules](https://developer.android.com/identity/data/autobackup),
and the [official MWA specification](https://solana-mobile.github.io/mobile-wallet-adapter/spec/spec.html)
for HTTPS wallet URI validation; implementation decisions also checked against
the actual locally locked SDK source.
