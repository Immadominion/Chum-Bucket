# Chumbucket sheets and typography

Updated 2026-10-01. Presentation only; account identity, wallet operations,
Panta trading and receipt outcomes remain owned by their existing features.

## Reference and diagnosis

The local brand kit is `/Users/mac/Downloads/Chumbucket/`, specifically
`ui_kits/app/components.jsx` (`Sheet`, `WaveHeader`, `wavePath`). It establishes
the floating white card, pink gradient and repeating white scalloped edge.
Its older Inter/Phosphor notes do **not** override the current app's bundled
PP Neue Machina/Montserrat/Basil fonts and icons.

The previous Flutter wave used a control-point amplitude of 2% of its height.
A quadratic curve reaches only half that amplitude: typical headers showed
less than one pixel of curvature. Independent sheet frames and title-size
overrides compounded the inconsistency. Market questions were 16dp while
prediction-feed questions were 20dp.

## Typography roles

| Role | Font | Size / line height | Use |
| --- | --- | --- | --- |
| `AppTextStyles.pageTitle` | PP Neue Machina Ultrabold | 28 / 1.2 | Shared tab header |
| `AppTextStyles.questionTitle` | PP Neue Machina Ultrabold | 18 / 1.3 | Market and prediction-feed questions |
| `AppTextStyles.sheetTitle` | PP Neue Machina Ultrabold | 22 / 1.25 | Every modal title |
| Existing body theme | Montserrat | 14 / 1.5 in sheet bodies | Supporting prose |

These roles use logical pixels, not viewport-width scaling. Android/iOS text
scaling still applies. Do not add a second local question/title size or shrink
text with a `FittedBox` to force it onto one line.

## Ownership

- `showChumbucketWavySheet<T>` is the only app-owned modal entry point.
- `ChumbucketWavySheet` owns the floating frame, safe-area/keyboard clearance,
  backdrop, dismissal guard, body region and optional footer region.
- `ChumbucketSheetHeader` owns the title, optional subtitle/leading image,
  48dp close target and pink gradient. Titles wrap, without ellipsis.
- `ChumbucketSheetWave` owns the 24dp white edge. `DetailedWaveClipper` is shared
  with receipt cards, with 14–16dp visible crest-to-trough depth.
- `CallJourneySheet` is a thin feature wrapper, not another modal design.

```dart
showChumbucketWavySheet<void>(
  context: context,
  builder: (_) => ChumbucketWavySheet(
    title: 'Add a friend',
    canDismiss: !busy,
    body: ListView(children: formFields),
    // footer: optionalContentSizedActions,
  ),
);
```

The default height is 72% of the screen, clamped to the available viewport.
Callers can request a different height. Body content must be scrollable when
it can exceed that space. On short viewports/large text, the header can scroll
within half the sheet; a footer can scroll within 30%. This leaves a usable
body area rather than covering form fields with an absolute-positioned wave.
Do not double-apply keyboard offsets inside callers. Use minimum button
heights and wrapping text, not fixed heights that clip enlarged labels.
The shared route uses `useSafeArea: true`: Flutter otherwise removes the top
inset from the child's MediaQuery, allowing keyboard-raised sheets behind the
status bar. The frame adds its 12dp clearance inside that safe area.

`canDismiss: false` disables the common close control, backdrop and system back. The
route has drag dismissal disabled because Flutter's drag-pop path bypasses
`PopScope`. The floating frame owns backdrop taps because its full-height route
otherwise covers the route barrier. Custom `onClose` callbacks retain feature-specific cancellation
and return values; they must not execute a save or submit implicitly.

## Migrated surfaces

Account/settings, Google linking, wallet details/address/export notices,
Send SOL, avatar selection, Add Friend, friend selector, witness challenge
resolution, challenge receipt, social receipt, call composer/response,
market picker, rematch, Panta trade review/status, notifications, match callers
and caller profiles all inherit the same frame/header. Historical routes
remain reachable through their existing navigation, not a second app shell.

The old receipt/resolve header classes are compatibility wrappers around the
shared header; they no longer carry their own gradient, wave or close action.
Challenge receipt content grows with its data rather than using a clipped
550dp internal scroll viewport. Friend-picker row height follows text scaling.

## Regression checks

`test/chumbucket_sheet_system_test.dart` checks the common entry point, wave
geometry, shared typography, single close control, busy dismissal, viewport
clearance and 11 existing sheet variants at 390dp/1x and 320dp/2x.
`test/add_friend_sheet_test.dart` additionally proves that the submit button
is hit-testable with a 300dp keyboard and 2x text; writes use an in-memory fake.
`test/ui_sheet_system_visual_test.dart` captures the real bundled fonts in
12 scenes at both sizes. Captures are opt-in and use synthetic data only.

Device checks should open and dismiss sheets without signing, sending funds,
changing a profile or submitting a call. The backend is outside this refactor.
