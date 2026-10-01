# Chumbucket state illustrations

Generated 2026-10-01 with the built-in image-generation tool, using the existing
`assets/images/ai_gen/logo/bucket_logo.png` as the style reference. The original
logo is unchanged. Image-generation and design-system skills guided the coherent
family, explicit state mapping, compact sizing and accessible text separation.

![The eleven state illustrations](../../test/goldens/state_art_family.png)

## Assets and state inventory

All files live in `assets/images/states/`. Each is a separate, square 1254px PNG
with genuine alpha transparency, not a white background or a sprite-sheet crop.
The family is approximately 11 MiB. Flutter decodes displayed illustrations at
512px and loads them only when their state is shown.

| Asset | Meaning | Integrated surfaces |
| --- | --- | --- |
| `empty_calls.png` | Nothing posted yet; blank call sign | Global call feed and the shared empty-call view |
| `people.png` | Bring your people; two bucket-houses | Empty friends grid, Following feed, Following people card, empty All Friends sheet |
| `search.png` | Nothing available for this search/window | Markets, market picker, empty open-market section in Predictions |
| `inbox.png` | No notifications; empty mailbox | Social inbox (All/Unread), original notification sheet |
| `record.png` | Nothing on record; blank clipboard | Loaded-empty profile calls, person calls/record, original prediction-history empty state |
| `challenges.png` | No invitations/challenges; two blank bubbles | Original challenge list and challenge preview |
| `waiting.png` | No result yet; hourglass | Rematch's not-settled state |
| `offline.png` | Disconnected; separated cable ends | Shared calls offline state and generic network-error widget |
| `error.png` | Recoverable load failure; repair wrench | Shared calls error, friends load failure, Following failure, original inbox failure, generic error/loading-error widgets |
| `access.png` | An account is needed; key | Shared signed-out state and Following sign-in card |
| `success.png` | Explicit confirmation; single check | Available in the shared library; deliberately not substituted for trading, claims or financial result evidence |

The call detail and market detail screens reuse the same shared error/offline/
signed-out components. No provider state, data retrieval, status derivation,
identity, trading eligibility or action callback was changed.

### States that deliberately keep their current treatment

- **Loading:** feed skeletons, list placeholders, spinners and wallet-approval
  progress remain progress indicators. An empty illustration must not imply a
  request has completed.
- **Stale/offline with cached content:** retain content plus the compact notice.
  Never replace usable cached rows with an offline illustration.
- **Inline validation, snackbar feedback, private/deleted invitation rows,
  webview errors and deep-link refusals:** retain concise live text/icons.
  Repeating a 144px illustration in each row would overwhelm the content.
- **Profile account connection and private positions unavailable:** retain the
  existing action rows and precise unavailable copy. Not having a positions
  reader is not evidence that the person has no positions.
- **Panta submitted/pending/filled/rejected/claim statuses, receipts, record
  scores, SOL-transfer results and original challenge lifecycle results:** keep
  their status-specific labels/indicators. No generic “success” scene is allowed
  to turn a submission into a fill or imply a winning resolution.
- **Original Arena routes outside the Panta default navigation:** the notification
  sheet and empty history use this family. Separate historic activity/call,
  matchday, caller-profile and caller-list placeholders retain their existing
  icons/text; the corresponding `calls`, `search`, `record` and `error` assets
  are available without redesigning those screens in this asset pass.
- **Unused generic `EmptyStateContainer`:** no live call sites were found; no
  extra migration was introduced simply to exercise the new library.

## Component contract

`lib/shared/widgets/chumbucket_state_art.dart` owns the typed asset mapping and
rendering. Choose a semantic enum explicitly; do not infer it from English copy
or an icon name.

```dart
const ChumbucketStateArt(ChumbucketStateArtwork.people); // 144dp
const ChumbucketStateArt.compact(ChumbucketStateArtwork.inbox); // 96dp

const CallsEmptyView(
  artwork: ChumbucketStateArtwork.record,
  title: 'Nothing on record yet',
  message: 'When they make a call, it shows up here.',
);
```

- The artwork has no words, prices, probability, balance, score or venue evidence.
- It is excluded from screen-reader semantics; adjacent live text conveys the
  state, and existing accessible actions remain available.
- 144dp for standalone states; 96dp for compact cards/sheets. No extra screen
  percentage, minimum panel height, spacer or artificial bottom gap.
- Keep at most one principal recovery action, never hide it behind the artwork.
- Missing artwork must not prevent reading the message or using its action.
- Do not show `success` for empty content. This pass specifically removes the
  old `done.json` celebration from the empty challenge list.

## Reproducibility

The exact prompts and original output paths are in [state-art-prompts.json](state-art-prompts.json).
Each sibling used the first generated call illustration as its style anchor.
The first record variation looked too much like a paper dispenser, so it was
rejected and regenerated as a blank clipboard. Rejected/original outputs remain
outside the repository; only the eleven selected outputs are bundled.

`test/chumbucket_state_art_test.dart` verifies bundling, real transparent
backgrounds and substantial opaque artwork, decorative semantics, compact
dimensions, small-screen/2x-text recovery actions, unchanged loading/cached
notices, Add Friend action, empty challenge meaning and content-fit sheet height.
It also renders the contact-sheet golden above using actual Flutter widgets and
local fonts.

```sh
flutter test --no-pub test/chumbucket_state_art_test.dart
# Only after visually reviewing intentional artwork changes:
flutter test --no-pub --update-goldens test/chumbucket_state_art_test.dart
```
