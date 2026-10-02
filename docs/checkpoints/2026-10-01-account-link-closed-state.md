# Account linking: say "not open yet" instead of offering a dead end — 2026-10-01

## Finding

Production `auth.identityStatus` (read-only, 2026-10-01): `enabled: true`,
`existingAccountClaimsEnabled: false`. For a person with an existing wallet
profile, every "Connect" (Activity, Profile → Calls) and every call entry
opened **Link Google**, whose "Continue with Google" could only end in the
refusal. The gate itself is correct and stays closed: the six steps in
`docs/contracts/existing-account-claim-v1.md` (credential remediation, legacy
authorization review, live migration approval, reviewed ownership anchors,
device tests, release approval) are founder decisions, and none was taken.

## Change (app only)

- `ChumbucketSession.loadIdentityStatus()` / `existingAccountClaimsOpen`: the
  public capability, read once and cached; unknown stays unknown.
- Link Google checks it on open. Closed: one sentence and "Got it" — no
  Google, no wallet prompt, no proof request. Open or unknown: unchanged, and
  the link flow still re-checks before acting.
- Activity and Profile → Calls show the same sentence instead of Connect for
  an existing wallet profile while closed. Walletless people keep normal
  Google sign-in (identity is enabled).
- The refusal copy said "not available in this build"; it is a server
  setting, so it now says linking "isn't open yet".

## Verification

- Link sheet and call-entry tests updated to the new order with the same
  guarantees (refusal visible, Google never started, no claim, only
  `auth.identityStatus` requested, closing returns to the original screen);
  a new Activity test pins the closed row.
- `flutter analyze`: clean. `flutter test`: 1,100 pass / 40 skip / 0 fail.
- Seeker debug 1.0.27: Activity shows the closed row; Home → Call opens Link
  Google with the closed state; "Got it" closes it. Nothing was linked,
  signed or requested beyond the public capability read.
