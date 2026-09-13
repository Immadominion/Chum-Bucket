# Chumbucket recovery manifest — Packet R

**Performed:** 13 September 2026
**Scope:** read-only audit, private WIP preservation, credential inventory, clean product worktrees, baseline test reproduction.
**Destructive operations performed:** none. No `git clean`, `reset`, `checkout -f`, `stash`, `pull`, or `rebase` was run in any checkout. No file was deleted or moved. No credential value was printed, copied, or committed.

All three source working trees were verified byte-for-byte unchanged after the audit by diffing their live `git status --porcelain -uall` against the manifests recorded at audit start.

---

## 1. Repositories

| Role | Path | Remote | Baseline commit | Dirty at audit |
| --- | --- | --- | --- | --- |
| **Canonical mobile** | `/Users/mac/Documents/codes/opensauce/world/chumbucket` | `https://github.com/Immadominion/Chum-Bucket.git` | `cc8acaa921e9e4db02f1b6f7ecfd24415282b471` | 16 modified + 4 untracked = 20 |
| **Canonical API** | `/Users/mac/Documents/codes/opensauce/world/chumbucket-arena` | `https://github.com/Immadominion/chumbucket-arena.git` | `ccac2c4c0ddc326919d53bb2cb5560c9ad773e46` | 1 modified |
| **Legacy / reference** | `/Users/mac/Documents/codes/projects/chum/chumbucket` | `https://github.com/Immadominion/Chum-Bucket.git` | `4ef31ae18d7d2842e0c6a7856a75f936a23025d3` | 49 M + 30 D + 43 untracked = 122 (138 with `-uall`) |

### Lineage verified

- `git merge-base --is-ancestor 4ef31ae cc8acaa` → **true**. `4ef31ae` is an ancestor; `cc8acaa` is **28 commits** newer.
- `git ls-remote origin`: `refs/heads/main` and `refs/tags/v1.0.2` **both resolve to `cc8acaa`**. The roadmap's claim is confirmed.
- No stashes exist in any of the three repositories.

### Nested repository found (not at risk)

`/Users/mac/Documents/codes/projects/chum/chumbucket/chum-bucket/` is a **separate clean git repository**, remote `https://github.com/inspikalu/chum-bucket.git`, HEAD `17382456…`, **0 dirty entries**. It appears as one untracked entry in the legacy status. It needs no rescue and was deliberately excluded from the backups.

---

## 2. Dirty-file inventories

### Canonical mobile `cc8acaa` — 20 entries (the only genuinely unique WIP)

Modified (16):

```
lib/features/arena/data/arena_models.dart
lib/features/arena/data/match_arena_service.dart
lib/features/arena/presentation/screens/arena_activity_screen.dart
lib/features/arena/presentation/screens/calls_screen.dart
lib/features/arena/presentation/screens/dare_yourself_screen.dart
lib/features/arena/presentation/screens/matchday_screen.dart
lib/features/arena/presentation/screens/my_pots_screen.dart
lib/features/arena/presentation/widgets/arena_format.dart
lib/features/authentication/presentation/screens/onboarding/onboarding_screen.dart
lib/features/authentication/presentation/screens/onboarding/widgets/terms_and_conditions_dialog.dart
lib/features/profile/presentation/screens/edit_profile_screen.dart
lib/features/profile/presentation/screens/profile_screen.dart
lib/shared/screens/home/widgets/friends_grid.dart
lib/shared/screens/home/widgets/friends_tab.dart
lib/shared/screens/home/widgets/header.dart
lib/shared/screens/home/widgets/predictions_home_tab.dart
```

Untracked (4):

```
assets/images/image.png
lib/features/arena/presentation/widgets/live_match_strip.dart
lib/features/profile/presentation/screens/widgets/profile_overview_card.dart
test/profile_overview_card_test.dart
```

Diffstat vs `cc8acaa`: 16 files, +541 / −613 (tracked only).

### Canonical API `ccac2c4` — 1 entry

```
M onchain/gaffer_verifier/Cargo.lock     (+13 / −13)
```

**Reviewed and understood.** The only semantic change is a package rename: `gaffer_verifier` → `chumbucket_arena` (plus the checksum churn that follows). It is consistent with the on-chain deploy artifact `onchain/gaffer_verifier/target/deploy/chumbucket_arena-keypair.json`, dated 19 July 2026. It is **intentional** work, preserved separately. It is *not* carried onto the API product branch, because the Gaffer verifier / Arena-pot on-chain path is explicitly retired from the MVP.

### Legacy `4ef31ae` — 122 entries

Full inventory preserved at `~/chumbucket-recovery/20260913/manifests/legacy-status.txt`. Summary: 49 modified, 30 deleted (icon assets, Privy wallet providers, old escrow service, old email/OTP login screens), 43 untracked (MWA services, FCM/notifications, `database_migrations/`, dApp Store `publishing/`, launcher icons).

---

## 3. Unique WIP requiring rescue

### Finding 1 — the legacy checkout contains **no unique work**

Every untracked source file in the legacy checkout already exists at the **same path** in `cc8acaa`. Content comparison (`git hash-object` vs the `cc8acaa` blob):

- **20 of 24 are byte-identical.**
- 4 differ, and in every case the legacy copy is the **older** version that `cc8acaa` superseded:

| File | Legacy (older) | `cc8acaa` (newer) |
| --- | --- | --- |
| `lib/shared/utils/challenge_status_utils.dart` | `phosphor_flutter` icons | Basil icon slugs |
| `lib/features/.../mwa_connect_button.dart` | `Icons.account_balance_wallet_outlined` | `BasilIcon('wallet-outline')` |
| `lib/features/.../mwa_login_screen.dart` | no attribution row | "Powered by Solana Mobile" row |
| `lib/core/services/notification_service.dart` | `@mipmap/ic_launcher` | `@mipmap/launcher_icon` |

**Conclusion:** the legacy dirty tree is a pre-commit staging copy of work that already landed upstream. It is **behind** the pivot base, not ahead. Nothing in it needs to be merged forward. It is archived anyway, for completeness.

### Finding 2 — the canonical mobile WIP is **compile-required**, not optional

`cc8acaa` — the released commit, remote `main`, tag `v1.0.2` — **does not analyze**. It produced **6 errors**:

```
lib/features/arena/data/arena_backend_service.dart:63,73   ArenaLiveScore undefined
lib/features/arena/providers/arena_provider.dart:289        ArenaLiveScore undefined
lib/features/arena/presentation/screens/dare_yourself_screen.dart:16   live_match_strip.dart missing
lib/features/arena/presentation/screens/dare_yourself_screen.dart:368  LiveMatchStrip undefined
lib/features/arena/presentation/screens/dare_yourself_screen.dart:531  ArenaMatchEntry.isLive undefined
```

All five symbols existed **only in the uncommitted working tree**. The release shipped code referencing files that were never committed. Had that working tree been cleaned, the pivot base would have been unrecoverable without re-deriving those files.

Restored surgically on `product/social-calls-v3` (commit `32037ed`): the two additive hunks in `arena_models.dart` (`ArenaLiveScore`, `ArenaMatchEntry.isLive`) and the new `live_match_strip.dart`. The remaining 18 WIP files are UI work-in-progress, archived on the rescue branch and deliberately **not** merged into the pivot base.

---

## 4. Backups

Root: `~/chumbucket-recovery/20260913/`, mode `0700`, outside every git repository.

| Set | Contents | Files | Archive SHA-256 |
| --- | --- | --- | --- |
| `mobile-world-wip` | all 20 dirty entries of `cc8acaa`, byte-for-byte | 20 | `52e91301bede6f298860068aa0677cb5c4e1e7bb55a0aecdbe3d0ca9ef4a7e77` |
| `legacy-wip` | modified + untracked legacy source, secret-free | 104 | `3a821199213c75f4eacc81da604e97b83e17766a592a9352b654dcc7b401d4d2` |
| `api-lockfile` | `onchain/gaffer_verifier/Cargo.lock` | 1 | `67f68b4bbad9b3c284a80431e96bee1810befec76f3d291abce2250c1a2794ca` |

Replayable patches:

| Patch | SHA-256 |
| --- | --- |
| `patches/mobile-world-wip-tracked.patch` (78,813 B) | `0b3620dc18a8362302afab340960bf40c17613ee9a536f13b4fcc4eed8e7cf4d` |
| `patches/legacy-wip-tracked.patch` (4,172,469 B) | `0e454a82f079700cdb3813a18248e56f61d0111143964764744fce538a0daa68` |
| `patches/api-lockfile.patch` | `6f3c127f685c382770b776a1f87dea2312a2d3931c9ce150debe2e05243bbb0e` |

Per-file hash manifests are in `manifests/*.sha256`. Rollup (hash of each manifest):

```
mobile-world-wip   7265fab3afa68246d68b2b2450ad45d47e16389d8688bd1d36d41bbc7c02f9a7
legacy-wip         5d8d56dc81facd3da5e2ef751604dc9b8badd7cce65ea5ca28b12568365b75e6
api-lockfile       683aa8f1f42d4d7691953d2fe89d17eb6759344ba5cda2b08c8f9f7c6aba964d
```

### Deliberately excluded from every backup

`.env`, `.env.local`, `*.apk`, `*.aab`, `*.jks`, `*.keystore`, `*keypair*.json`, `*adminsdk*`, `google-services.json`, `GoogleService-Info.plist`, `build/`, `.dart_tool/`, and the nested `chum-bucket/` repo. Notably **not** backed up: `publishing/files/app-release.apk` (194 MB, credential-bearing build output).

Verified: zero secret-shaped filenames and zero private-key / JWT / service-role patterns in the backup tree. The only matches were the key *names* `HELIUS_API_KEY` and `PRIVY_APP_SECRET` inside the tracked `.env.example` template, whose values are placeholders and which is already public in git history.

### Rescue branches (created with git plumbing — no working tree was checked out or modified)

| Branch | Repo | Commit | Parent |
| --- | --- | --- | --- |
| `rescue/world-mobile-wip-2026-09-13` | canonical mobile | `5080d7f` | `cc8acaa` |
| `rescue/legacy-wip-2026-09-13` | legacy | `4eebb1b` | `4ef31ae` |

Neither rescue commit adds a secret-shaped path. (`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` appear in the mobile tree, but they were committed at `cc8acaa` and earlier — pre-existing in public history, not introduced here.)

### Recoverability matrix

| State | Recoverable from |
| --- | --- |
| Legacy `4ef31ae` | git history, both clones, `origin` |
| Legacy dirty WIP | `rescue/legacy-wip-2026-09-13` + `legacy-wip.tar.gz` + patch |
| Released `cc8acaa` | git history, `origin/main`, tag `v1.0.2` |
| Newer mobile dirty WIP | `rescue/world-mobile-wip-2026-09-13` + `mobile-world-wip.tar.gz` + patch |
| API `ccac2c4` | git history, `origin/main` |
| API lockfile change | `api-lockfile.tar.gz` + patch; original still dirty in place |

---

## 5. Product worktrees

Created from the immutable commits, not from either dirty checkout. Both were clean at creation and contain **no** secret-shaped file.

```
/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls       product/social-calls-v3   (from cc8acaa)
/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api   product/social-calls-api  (from ccac2c4)
```

Neither branch nor destination path existed beforehand; nothing was overwritten.

Commits so far on `product/social-calls-v3`:

| Commit | Summary |
| --- | --- |
| `32037ed` | restore the two files `cc8acaa` referenced but never committed |
| `0164f81` | stop bundling `.env` into the app |

`product/social-calls-api` is still at `ccac2c4`, unmodified.

---

## 6. Credential remediation — **by filename only**

No file below was opened, printed, copied, or committed. SHA-256 is recorded as an **identity check** (a hash is not the secret) so the founder can confirm which artifact was rotated. Permissions were tightened in place; nothing was moved or deleted.

### Exposed — rotation required

| # | Filename | Mode was → now | SHA-256 (identity) | Status |
| --- | --- | --- | --- | --- |
| C1 | `chumbucket-service-firebase-adminsdk-fbsvc-0fa2b30a3d.json` (workspace root) | `0644` → `0600` | `1f564783a0cf04a5c3e8234044a4c3573aa182d7aadf1c9b1afa237597419820` | **Open — founder must revoke** |
| C2 | `chumbucket/.env` (canonical mobile) | `0644` → `0600` | `bdb444d669443dee7e9c7c24d45ade9054641c0857c1d05c567462bd8e742e11` | **Open — shipped inside the APK** |
| C3 | `chumbucket-pinocchio/target/deploy/chumbucket_pinocchio-keypair.json` | `0600` (already) | `1b8902210176a77938fbdf8c9a6fdf5a8d38e8181f759be491bf5d03ac1fa2c0` | **Open — verify then transfer** |
| C4 | `chumbucket-arena/onchain/gaffer_verifier/target/deploy/chumbucket_arena-keypair.json` | `0644` → `0600` | `e7c58fee8807b2ba4bf65998823e2c41a1474ce571250ac0264c472f64ef58d0` | **Open — verify then transfer** |
| C5 | `android/app/dappstore.keystore` (identical copy in **both** mobile checkouts) | `0644` → `0600` | `8b99ff9c45e1851fd1bec420327220a9f41bab736bc4ad494bde933c7b0da2dd` | **Open — back up offline; cannot be rotated** |

### Server-side only — not client-exposed, still hardened

| # | Filename | Mode was → now | SHA-256 (identity) |
| --- | --- | --- | --- |
| C6 | `chumbucket-arena/.env` | `0644` → `0600` | `7ff438d87766945f5c56c773316c6f03689f7da7f910b45ce580c7c4da6dfd12` |
| C7 | `chumbucket-arena/web/.env.local` | `0644` → `0600` | `61177635e8813ad8f5811f1eecff80dc8336e59a2c5d3899ad7ad852fbca399a` |
| C8 | `chumbucket/.env` (legacy checkout) | `0644` → `0600` | `dbf028c9cd0a67804348ef03b0252a3b0d7e02fd87fa282887aa33ae3407614f` |

All eight files were re-hashed after `chmod`; contents are unchanged.

### Proof of the APK exposure

`pubspec.yaml` listed `.env` as a Flutter asset. The bundled copies are **byte-identical** to the developer's `.env`:

```
bdb444d6…  .env                                                                   (source)
bdb444d6…  build/flutter_assets/.env
bdb444d6…  build/app/intermediates/assets/release/mergeReleaseAssets/…/.env
```

Every value in that file must be treated as public. The **variable names** present (values never read) are:

```
ARENA_BACKEND_URL          PLATFORM_FEE_PERCENTAGE    SOLANA_RPC_URL
HELIUS_API_KEY   ← secret  PLATFORM_WALLET_ADDRESS    SOLANA_WS_URL
LOCAL_RPC_URL              SOLANA_DEVNET_RPC_URL      SUPABASE_ANON_KEY
MAX_FEE_SOL                SOLANA_MAINNET_RPC_URL     SUPABASE_PUBLISHABLE_KEY
MIN_FEE_SOL                SOLANA_NETWORK             SUPABASE_URL
TAWK_TO_URL                VSC_MCP_ACCESS_TOKEN  ← secret
```

`HELIUS_API_KEY` and `VSC_MCP_ACCESS_TOKEN` are the two confirmed exposed secrets. The `SOLANA_*_RPC_URL` entries must also be checked: a Helius URL embeds its key as `?api-key=…`, which the old `address_name_resolver.dart` even parsed back out. `SUPABASE_ANON_KEY` / `SUPABASE_PUBLISHABLE_KEY` are publishable by design and are not an incident, provided RLS is sound.

**Fixed** in commit `0164f81`: `.env` removed from `pubspec.yaml` assets; configuration now arrives via `--dart-define` through a public allowlist (`lib/core/config/app_config.dart`); `test/app_config_test.dart` fails the build if `.env` returns to the asset list, if a secret-shaped key name is added, or if a credentialed URL survives sanitisation.

### Git-history scan — clean

No `.env`, service account, keystore, deploy keypair, APK, or PEM was **ever** committed in any of the three repositories. The only credential-shaped paths in history are `.env.example` (placeholders), `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist` — Firebase **client** config, public by design, but worth restricting by package name + signing-certificate SHA in the Firebase console.

The Solana program address is public and is **not** a secret: `D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1` (`chumbucket-pinocchio/src/lib.rs:15`). Note that `chumbucket-pinocchio` is **not a git repository at all** — it is entirely unversioned, so the keypair beside its compiled `.so` has no history protecting it.

---

## 7. Founder / admin actions required

These are **not** engineering tasks and none was performed. Nothing was deployed, pushed, rotated, or mutated in production.

| # | Action | Owner | Where |
| --- | --- | --- | --- |
| F1 | Revoke the Firebase Admin service-account key (C1), issue a replacement, store it only in Railway secrets. Review IAM audit logs for use from unexpected IPs. | Founder | Google Cloud IAM → Service Accounts → Keys |
| F2 | Rotate the Helius API key (C2). Check usage history for anomalous volume. Restrict the new key; **never** put it in the client — route RPC through the BFF. | Founder | Helius dashboard |
| F3 | Revoke `VSC_MCP_ACCESS_TOKEN` (C2). Identify the issuing service and confirm what the token could reach. | Founder | issuing service |
| F4 | Confirm whether program `D6mjMGW1…` is deployed and what its **upgrade authority** is: `solana program show D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1 --url mainnet-beta`. If upgradeable and live, transfer the authority to a hardware/multisig wallet — or set it immutable if the program is retired. (C3, C4) | Founder | Solana CLI |
| F5 | Back up `dappstore.keystore` (C5) to offline encrypted storage. An app signing key **cannot be rotated** — losing it means losing the ability to publish updates under the same identity, and leaking it lets someone else sign as Chumbucket. | Founder | offline |
| F6 | Delete or archive every old APK containing the exposed `.env`: `publishing/files/app-release.apk` and all of `build/app/outputs/`. Withdraw any published build carrying it. | Founder | local + store listings |
| F7 | Restrict the Firebase client config (`google-services.json`, `GoogleService-Info.plist`) by package name and signing-certificate SHA. | Founder | Firebase console |
| F8 | Re-run the production Supabase/Privy inventory: live profile count, verified emails, wallet types, balances, open positions. Keep the export out of git. | Founder | Supabase + Privy |
| F9 | Ask CLOCK IN organisers whether a substantially new product may reuse a repository whose history predates the 8 June 2026 eligibility window. | Founder | organisers |

---

## 8. Baseline test results — measured, not claimed

Neither README states a test count, so there was no claim to contradict. Toolchain: Flutter 3.44.2 / Dart 3.12.2, Bun 1.3.14, Node v24.5.0, rustc 1.95.0, solana-cli 3.1.10, OpenJDK 17.0.16, git 2.50.1.

### API — `product/social-calls-api` @ `ccac2c4`, unmodified

| Command | Result |
| --- | --- |
| `bun install` | 172 packages, 11.52 s. **No lockfile drift** — `git status` clean afterwards. |
| `bun run typecheck` | **PASS** (`tsc --noEmit`, exit 0, no output) |
| `bun test` | **142 pass, 0 fail**, 446 `expect()` calls, 19 files, 1.64 s |

### Mobile — `product/social-calls-v3`

| Command | At `cc8acaa` (as released) | After `32037ed` + `0164f81` |
| --- | --- | --- |
| `flutter pub get` | OK (138 packages pinned below latest) | OK |
| `flutter analyze` | 289 issues — **6 errors**, 283 info | **282 issues — 0 errors, 0 warnings**, 282 info |
| `flutter test` | **Could not run.** `Error detected in pubspec.yaml: No file or variants found for asset: .env` → `Failed to build asset bundle` | **21/21 pass** |

The mobile baseline could not be built or tested from a clean checkout at all: the pubspec required a gitignored secret file. Removing `.env` from the asset list fixed the security exposure and the build reproducibility in the same change.

Remaining 282 analyzer issues are all `info`-level lint (`avoid_print` in `test/escrow_integration_test.dart`, `use_build_context_synchronously`, `curly_braces_in_flow_control_structures`). None blocks the pivot; they are not addressed here to keep Packet R free of product-code churn.

---

## 9. Residual risk

1. **Exposed credentials are still live.** Every item in §7 is open. Rotation needs founder access and explicit approval; nothing was rotated here.
2. **Old APKs still carry the secrets.** Removing `.env` from the asset list protects future builds. Already-distributed builds remain compromised until the underlying credentials are rotated (F2, F3) and the artifacts withdrawn (F6).
3. **`chumbucket-pinocchio` is unversioned.** No git history protects its source or the deploy keypair beside it. A single `rm -rf` loses it. It is out of the MVP path but should still be committed to a private repo.
4. **The app signing key is duplicated.** `dappstore.keystore` exists in two checkouts at the same hash, and was world-readable until this audit. It cannot be rotated (F5).
5. **The release is unreproducible without the fix.** Anyone cloning `cc8acaa` gets 6 analyzer errors and an unbuildable asset bundle. Both are fixed only on `product/social-calls-v3`; `main` still carries them.
6. **The arena lockfile rename is preserved but unmerged.** It belongs to the Gaffer/Arena-pot on-chain path that the MVP retires. If that program is still deployed, F4 applies to it too.
