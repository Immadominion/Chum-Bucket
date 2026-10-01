# Character-led state art — 2026-10-01

Founder correction: the Chum Bucket is a building/brand mark, not something to
repeat in every state. Use Plankton and Karen with varied expressions/actions.

Worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`.
Branch: `product/social-calls-v3`; starting HEAD `8aa1fe3`.

## Changed

- Replaced the house-based PNGs with eight separate transparent character scenes:
  megaphone, tin-can invitation, detective search, empty inbox, unwritten record,
  disconnected Karen, repair scene and high-five confirmation.
- Eleven semantic state variants remain; friendly invitations also serve
  challenges/account access, and thoughtful Plankton also serves waiting.
- Removed unused `access.png`, `challenges.png` and `waiting.png` house assets
  from the bundle. All superseded house images remain recoverable in `8aa1fe3`.
- Updated only the asset mapping/comment, inventory, exact prompts, tests and
  family preview. Existing screen integrations, compact sizes, live copy,
  semantics, actions and all backend/session/trading behavior are unchanged.
- Artwork is 1254px square RGBA, approximately 6.2 MiB total, decoded at 512px
  for the existing 144dp / compact 96dp presentation.

Used the built-in image-generation tool, with the generated Plankton/Karen
friends scene as the later character reference. No CLI/API fallback. Tool-side
output rejections prevented selected challenge/waiting/access variants; the
completed scenes cover those states instead. No blocked output was bypassed or
recovered. Eight distinct assets are delivered, not eleven unique pictures.

## Verification

- `flutter analyze --no-pub`: **No issues found**, exit 0, 5.5s.
- Focused state-art suite, including updated preview generation: **26 pass /
  0 fail**, exit 0. Transparent-background/core-opacity assertions unchanged.
- `flutter test --no-pub --concurrency=2 --reporter expanded`: **1,086 pass /
  35 existing skips / 0 fail**, exit 0, 57s. This also compared the reviewed
  golden without updating it.
- Added an inventory assertion: actual bundled PNGs exactly equal the eight
  unique paths used by eleven enum cases; no unreferenced house PNGs remain.
- Reviewed all selected scenes and their production-size Flutter contact sheet.

The shared worktree still has separate typography/sheet work. It was preserved
and excluded from this commit; full-suite numbers describe the combined tree.
No APK build/install, device interaction, deployment or credential access here.

Preview: [state_art_family.png](../../test/goldens/state_art_family.png).
Inventory: [state-art.md](../design/state-art.md).
Exact prompts: [state-art-prompts.json](../design/state-art-prompts.json).
Test log: `/private/tmp/chumbucket-character-art-20261001.ky519Z/full-test.log`.
