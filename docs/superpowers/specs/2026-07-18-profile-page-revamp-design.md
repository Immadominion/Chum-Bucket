# Compact Profile Page Revamp

## Goal

Reduce the Profile page's unused vertical space while preserving Chumbucket's light, friendly card language. The page should present identity, wallet, and prediction credibility as one coherent profile surface instead of two large stacked cards.

## Direction

- **Archetype:** compact social prediction profile
- **Density:** comfortable-compact
- **Surface:** one rounded neutral base with one same-width white upper panel
- **Type mood:** friendly, direct, numeric where appropriate
- **Accent:** existing Chumbucket pink and cool neutral palette

The supplied profile-card references inform the composition and density only. Chumbucket keeps its own avatars, Basil icons, colors, typography, radii, and wallet behavior.

## Page Hierarchy

1. A compact page header displays `Profile` on the left and the existing settings icon on the right. A standalone pushed Profile route may also show its close icon.
2. One unified profile card contains identity, wallet, and prediction statistics.
3. `Your activity` follows after a 20px-equivalent gap and retains the prediction-history and challenge-history rows.
4. The version label remains a quiet footer.

## Unified Profile Card

### Identity Section

- Use `assets/images/image.png` as a compact cover field behind the identity
  content, with the circular Chumbucket avatar placed over it.
- Keep the cover and identity treatment inside the white upper panel; it does
  not become a separate floating card.
- Use a 72px-equivalent circular Chumbucket avatar on the left.
- Place the name and a maximum two-line bio to its right.
- Place a containerless pen icon immediately after the name. The name yields
  space and ellipsizes before the icon when display names are long.
- Pressing the pen opens the existing full Edit Profile screen.
- Pressing the avatar retains the existing profile-picture selector behavior.
- Remove the full-width `Edit Profile` button.

### Wallet Section

- Separate the wallet section from identity with an inset divider.
- Start with the current SOL balance as the strongest number; do not show a
  wallet label or decorative wallet icon.
- Place the resolved domain/address and copy action directly below the balance.
- Replace the persistent refresh button with a small progress indicator that is
  visible only while the provider is refreshing. Pull-to-refresh remains the
  manual refresh gesture.
- Present `Add SOL` as a compact, solid-primary command aligned with the balance
  rather than a full-width or translucent CTA.
- Do not reintroduce Withdraw or custodial-wallet wording.

### Prediction Summary Footer

- The whole card is a rounded neutral base. Place one same-width white upper
  panel over that base containing identity and wallet information.
- Give the white upper panel rounded corners on all four sides, including the
  two bottom corners exposed above the stats area.
- Place Calls, Win rate, and PnL directly in the visible neutral base beneath
  the upper panel. The stats area has no separate container, translation,
  shadow, or elevation.
- Preserve one continuous outer silhouette: the stats region ends at the base's
  rounded bottom corners.
- Use three equal columns with slim vertical dividers.
- Keep success/error coloring only for positive/negative PnL.
- Preserve all existing Arena profile data and zero-value fallbacks.

## Visual Rules

- Keep the existing scaffold background, white surface, pink accent, Basil outline icons, and Chumbucket avatar assets.
- Match the Figma geometry: the neutral base and white upper panel use the same
  proportional corner radius and neither layer has a shadow effect.
- Internal content does not become nested cards. Contrast between the white
  upper panel and neutral base creates the hierarchy.
- Use no decorative gradients beyond the existing small wallet icon treatment.
- Keep touch targets at least 40px-equivalent and provide tooltips/semantics for icon-only actions.
- Text must remain readable at the Infinix width without clipping or overlapping.

## Component Boundaries

- Replace the separate `ProfileHeader` and `ProfileWalletCard` page composition with a focused unified profile-card widget.
- The unified widget receives identity text and edit callback, and reads the existing profile, authentication, and wallet providers for avatar and wallet state.
- Prediction history and challenge history remain page-level navigation concerns.
- Existing edit-profile, profile-picture, wallet modal, copy, refresh, and settings flows remain unchanged.

## States And Errors

- Wallet loading uses a stable inline placeholder that does not resize the card.
- Missing profile names continue to fall back to the shortened wallet address.
- Missing bios do not reserve a large empty block; the identity section compacts naturally.
- Missing social prediction statistics display zero values.
- Existing snackbars continue to report copy and wallet errors.

## Verification

- Add widget coverage for the pen action, compact Add SOL action, and integrated stat labels.
- Run focused analysis and the full Flutter test suite.
- Build and install the debug APK.
- Inspect the initial and scrolled Profile states on the connected Infinix for density, clipping, bottom-navigation clearance, and functional icon targets.
