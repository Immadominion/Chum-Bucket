# Integration request — Packet Deposits (Add funds with Crossmint)

**Raised:** 2 October 2026 · **Packet:** fleet/deposits · **Owner to apply:** integration

Add funds lets a signed-in person buy USDC on Solana with a card, Apple Pay or
Google Pay (Crossmint Onramp) and have it delivered to their own,
server-verified wallet. Research, API and owner checklist:
`chumbucket-social-calls-api` → `docs/crossmint-deposits.md` (branch
`fleet/deposits`). The BFF procedures are `deposits.status | balance | quote |
create | order | verifyWallet`.

New mobile code is additive under `lib/features/deposits/` and `test/deposits_*`.
`lib/main.dart` is **not** touched: `DepositsDependencies.of(context)` resolves
the BFF base URL, the `ChumbucketSession` token and the MWA wallet from
providers that already exist.

## 1. `pubspec.yaml` (integration-owned) — applied on the branch, please keep

```diff
   webview_flutter: ^4.13.0 # For in-app web browser
+  # Already resolved transitively (pubspec.lock pins both). Promoted so the
+  # Crossmint checkout can enable Android's Payment Request API (Google Pay)
+  # and iOS inline media, as Crossmint's WebView guide requires.
+  webview_flutter_android: ^4.10.2
+  webview_flutter_wkwebview: ^3.23.1
```

`pubspec.lock` only changes both entries from `transitive` to `direct main`;
versions and hashes are unchanged, and `flutter pub get --offline` resolves.

- **Why unavoidable:** `AndroidWebViewController.setPaymentRequestEnabled` and
  `WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: …)` live in
  the platform packages. Importing them without declaring them trips
  `depend_on_referenced_packages`.
- **If not applied:** analyzer infos, and if the imports were removed instead,
  Google Pay never appears in the Android checkout and identity checks can't
  play inline media on iOS. Card entry still works.

## 2. After fleet/identity merges — plug in the device wallet

> **Applied in fleet/wallets** (`depositWalletSourceOf` and the on-phone
> wallet sheet's **Add funds**). See `packet-wallets.md`.

fleet/identity adds `EmbeddedWalletController` (provided above the app in its
`main.dart`) whose `signer` is an `EmbeddedWalletKey` (`address`,
`Future<Uint8List> sign(List<int>)`), non-null only once the server has linked
it. Add funds already takes any `DepositWalletSource`; this wires the device
one. File: `lib/features/deposits/presentation/deposits_dependencies.dart`.

```diff
+import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
@@ DepositWalletSource? depositWalletSourceOf(BuildContext context) {
   final auth = context.read<MwaAuthProvider?>();
   if (auth != null && auth.isAuthenticated && auth.walletAddress != null) {
     return MwaDepositWalletSource(auth);
   }
+  final onPhone = context.read<EmbeddedWalletController?>();
+  final key = onPhone?.signer;
+  if (onPhone != null && key != null) {
+    return DeviceDepositWalletSource(
+      address: key.address,
+      currentAddress: () => onPhone.signer?.address,
+      sign: (message) async {
+        final signer = onPhone.signer;
+        if (signer == null || signer.address != key.address) {
+          throw const DepositWalletDeclined();
+        }
+        return signer.sign(message);
+      },
+    );
+  }
   return null;
 }
```

- **Why it can't land now:** `embedded_wallet_controller.dart` does not exist
  on this branch's base (`37c0a10`).
- **If not applied:** device-wallet people can still add funds. The server
  funds the account's own verified wallet with no help from the phone. The one
  thing they can't do is sign Crossmint's ownership message, which Crossmint
  only asks for above US$1,000 (single order or 30-day volume). Our per-order
  cap is $500. The sheet tells them which wallet to open.

Also in fleet/identity's `embedded_wallet_sheet.dart` ("make, **fund**, back
up or export it"), add the same entry the MWA wallet sheet now has:

```dart
FilledButton.icon(
  key: const ValueKey('embedded-add-funds'),
  onPressed: () => showAddFundsSheet(context, fundWallet: controller.address),
  icon: const BasilIcon('add-outline'),
  label: const Text('Add funds'),
)
```

(import `package:chumbucket/features/deposits/presentation/add_funds_sheet.dart`).

## 3. Files both fleet/deposits and fleet/identity touch

| File | fleet/deposits | fleet/identity | Expected merge |
| --- | --- | --- | --- |
| `lib/features/profile/presentation/screens/widgets/profile_wallet_card.dart` | In the MWA sheet (`_PrivateWalletDetails`), "Add SOL" becomes **Add funds** (opens the sheet, refreshes the SOL balance when funds land) plus **Receive from another wallet** (the existing QR `WalletModal`). One import added. | Adds an embedded-wallet branch at the top of `ProfileWalletCard.build`, plus imports. | Different hunks. If git conflicts on the import block, keep all imports. |
| `lib/features/panta_trading/presentation/panta_trade_sheet.dart` | Inserts `TradeFundsCheck(controller: controller)` after the review block, plus one import. | Adds `PantaSigner` and changes copy inside `_notice`, `_walletContext`, `_review` and `_primaryAction`. | Different hunks. `TradeFundsCheck` reads `controller.wallet`, which is right for both signers. |

## 4. Not needed

- No Supabase migration: nothing is stored server-side. Crossmint holds the
  order; the phone remembers only the order id (SharedPreferences, 2-day TTL).
- No `main.dart` change, no new provider.
- `src/api/router.ts` (integration-owned, API repo) mounts `deposits:
  depositsRouter` and was committed on the API branch in `53b5924`. The diff
  is 7 lines (import plus mount with a comment) and needs no other wiring.

## 5. Tests

`test/deposits_models_client_test.dart` (14), `test/deposits_controller_test.dart`
(23), `test/deposits_sheet_test.dart` (15), `test/deposits_wiring_test.dart` (7),
plus the opt-in captures in `test/deposits_visual_capture_test.dart`.
`test/ui_people_layout_continuity_test.dart` was updated: the receive modal now
opens from "Receive from another wallet" instead of "Add SOL".
