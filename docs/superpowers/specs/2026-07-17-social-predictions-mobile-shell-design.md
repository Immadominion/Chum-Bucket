# Chumbucket Social Predictions Mobile Shell

Date: 2026-07-17
Status: Approved

## Product Direction

Chumbucket is a social prediction product, not a friend-challenge app with an
Arena feature attached. The mobile hierarchy should support this loop:

1. See today's markets and what people are calling.
2. Make a call, copy a call, or challenge a friend.
3. Follow the live and settled state.
4. Claim winnings and build a public record.

FOMO is a reference for information hierarchy, social density, and persistent
navigation. Chumbucket keeps its own light, friendly visual language and its
existing MWA, Pinocchio, Supabase, Arena, and TxLINE workflows.

## Information Architecture

The authenticated app uses four persistent destinations:

### Home

- Existing wallet/profile header without a second page title.
- Claimable winnings appear as a compact, conditional action.
- Today's open prediction markets are the primary content.
- Active friend challenges appear as a short preview, not a separate root.
- Market rows open the existing call flow.

### Calls

- One `Calls` heading with notification access.
- Global and Following feed filters.
- Feed items show caller identity, prediction, stake, status, market, and time.
- `Call too` reuses the existing Arena transaction flow.
- Caller identity opens a full profile screen instead of a large bottom sheet.
- Hot callers and claim banners do not compete with the feed on this screen.

### Friends

- Friends and Leaderboard are sibling tabs.
- Existing friends and add-friend behavior remain intact.
- Friend rows expose the existing Challenge flow.
- Leaderboard rows open public prediction profiles and support follow state.

### Profile

- Existing identity, wallet, editing, and settings behavior remains available.
- Positions and challenge history become first-class profile sections.
- Claimable positions route to the existing claim flow.
- Public prediction performance is shown only when backed by server data.

`Arena` remains an internal module/backend term and does not appear as a main
consumer destination. Challenges remain product objects and contextual actions,
not a root navigation category.

## Visual Contract

- App background: `#F4F4F4`.
- Surfaces: white, with soft neutral shadows and rare outlines.
- Accent: `#FF5A76` to `#FF3355` gradient, reserved for primary actions,
  selected emphasis, wallet balance, and wavy sheet headers.
- Type: Inter with 700 titles, 600 headers, and 400 body. Avoid 800/900 weight
  except a genuinely dominant numeric value.
- Icons: Phosphor only for newly introduced interface icons.
- Page gutters: approximately 20 logical pixels.
- Spacing follows the existing 4-pixel scale.
- Use full-width lists and restrained grouped surfaces. Do not nest cards.
- Status colors are semantic and never become competing page accents.
- Motion uses short Material easing with subtle fades and 98% press feedback.

## Navigation Component

The bottom navigation is a floating white surface with four icon destinations:
Home, Calls, Friends, and Profile. It uses 12-pixel horizontal margins, a soft
shadow, a large design-system radius, stable height, safe-area spacing, and a
pink active icon/dot. It must not cover scrollable content.

The shell uses an `IndexedStack` so tab state and loaded data survive navigation.
Authentication, lifecycle refresh, realtime setup, and notification navigation
remain owned by the shell rather than being duplicated in each destination.

## Wavy Sheet Contract

One reusable Flutter primitive owns new Chumbucket sheets:

- transparent modal background and approximately 45% dark barrier;
- subtle backdrop blur;
- 12-pixel horizontal inset and bottom safe-area separation;
- large rounded white shell with the established sheet shadow;
- vertical pink-gradient header with a translucent white drag handle;
- exactly one `DetailedWaveClipper` transition into the white body;
- keyboard-aware height and scroll behavior;
- one clear primary action.

Focused actions such as match callers and identity linking may use this sheet.
Long, navigable content such as notifications and public profiles uses a screen.

## Existing Data And Behavior

The redesign composes current providers and services:

- `ArenaProvider`: matchday, activity, following feed, leaderboard, callers,
  claimables, notifications, and profiles.
- `ChallengeStateProvider`: current friend challenge state.
- `MwaAuthProvider` and `MwaWalletProvider`: authority, wallet initialization,
  transaction signing, and balances.
- Existing Friends widgets and create-challenge flow.
- Existing Arena call and claim screens.

The shell does not introduce placeholder financial data. Missing or failed
sections render explicit loading, empty, retry, and offline states while keeping
other destinations usable.

## Accessibility And Responsiveness

- Interactive targets are at least 44 logical pixels.
- Navigation items have semantic labels even when their visible treatment is
  primarily iconic.
- Text uses bounded lines and ellipsis where remote names can be long.
- Lists reserve enough bottom padding for the floating navigation.
- Sheets account for keyboard, system insets, and short Android displays.
- Selected state is communicated by color and shape, not color alone.

## Verification

- Widget tests cover shell navigation and stable tab state.
- Existing Flutter tests must continue to pass.
- Changed files are analyzed and formatted.
- A debug Android build is installed on the connected test phone.
- Home, Calls, Friends, Profile, loading, empty, and at least one sheet are
  visually inspected on the physical device with screenshots.
- Existing MWA login, add friend, challenge, call-too, wallet, and claim entry
  points remain reachable.
