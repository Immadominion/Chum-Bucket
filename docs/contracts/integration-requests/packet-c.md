# Integration request — Packet C (mobile call / feed / receipt slice)

**Raised:** 13 September 2026 · **Packet:** C · **Owner to apply:** integration

Packet C owns `lib/features/calls/**` and `lib/features/receipts/**`. Everything below
is in an integration-owned or platform-owned file, so it is written here rather than
applied. **The slice compiles, analyses clean and passes its tests today without any of
these patches** — each one says exactly what is degraded until it lands.

---

## 1. `lib/main.dart` — register `CallsProvider` (REQUIRED to reach any of the new UI)

The provider is deliberately registered nowhere. Until it is, no screen in the slice can
be opened from the running app (they all read `CallsProvider` from the tree).

Add the imports:

```dart
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
```

Add one entry to the existing `MultiProvider` list at `lib/main.dart:91-100`, after
`ChangeNotifierProvider(create: (_) => ArenaProvider()),`:

```dart
        // Packet C. Swap MockCallsRepository for the BFF-backed
        // implementation when Packet B's routes land — nothing above the
        // CallsRepository interface changes.
        ChangeNotifierProvider<CallsProvider>(
          create:
              (_) => CallsProvider(
                repository: MockCallsRepository(
                  latency: const Duration(milliseconds: 350),
                ),
              ),
        ),
```

`MockCallsRepository` implements `CallsRepository`; the `latency` argument only exists so
the loading state is visible in the running app (tests construct it with
`Duration.zero`).

**Session wiring.** `CallsProvider.setViewer(String? userId)` takes the canonical
`public.users.id` and **never a wallet**. Until Packet A's `auth_user_id` mapping exists,
call it with `MockCallsRepository.demoViewerUserId` to demo the signed-in path, or leave
it unset to demo the signed-out path. Both are fully supported: reading never requires a
session, only writing does.

**Degraded without it:** the entire slice is unreachable from the app. Tests still pass.

---

## 2. `lib/shared/screens/home/home.dart` — surface the feed

`CallFeedScreen` is built to drop into the existing 4-slot `IndexedStack`
(`home.dart:224`). It is self-contained: its own `Scaffold`, its own header, its own
`AutomaticKeepAliveClientMixin`.

Replace slot 1 (`const CallsScreen()`) with:

```dart
                CallFeedScreen(
                  onSignInRequested: () => _selectDestination(3),
                ),
```

`onSignInRequested` is called when a signed-out person taps something that needs an
account; the shell decides what "sign in" means. Passing `null` simply makes those taps
no-ops, which is safe.

Do **not** change `ChumbucketBottomNavigation` — the slot count stays at four.

**Degraded without it:** the feed can only be reached by pushing `CallFeedScreen`
manually. The market, call, person and receipt screens are reachable from it either way.

---

## 3. `pubspec.yaml` — promote `app_links` to a direct dependency (deep links)

Deep linking is new work (contract §2: no router, no named routes, no deep-link package).
Packet C has implemented all of the routing logic without a package:

- `lib/features/calls/deeplink/call_deep_link.dart` — pure-Dart parsing and resolution,
  unit-tested in `test/calls_deep_link_test.dart` (26 tests).
- `lib/features/calls/deeplink/call_deep_link_router.dart` —
  `CallDeepLinkRouter.handle(Uri, NavigatorState)`.

What is missing is only the thing that *delivers* a `Uri` to the app while it is running.

**`app_links` is already resolved in `pubspec.lock` at `6.4.1`** as a transitive
dependency of `supabase_flutter`, so this adds no new package to the resolution — it only
makes the existing one directly importable.

```diff
   connectivity_plus: ^7.0.0
   qr_flutter: ^4.1.0
+  # Already resolved transitively via supabase_flutter (locked at 6.4.1).
+  # Promoted to a direct dependency so the call slice may import it.
+  app_links: ^6.4.1
```

Then, in `main.dart`. This sketch assumes a `GlobalKey<NavigatorState> navigatorKey`
handed to `MaterialApp.navigatorKey` — there is none today, so adding it is part of this
patch:

```dart
  StreamSubscription<Uri>? _linkSub;
  final AppLinks _appLinks = AppLinks();

  Future<void> _initDeepLinks() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) await _handleLink(initial);
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
  }

  Future<void> _handleLink(Uri uri) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    // Returns false for anything it does not own — including the Supabase
    // OAuth callback, which must keep reaching its existing handler.
    await CallDeepLinkRouter(
      navigatorKey.currentContext!.read<CallsProvider>(),
    ).handle(uri, navigator);
  }
```

`CallDeepLinkRouter.owns(uri)` is a static, side-effect-free check if the caller wants to
decide before routing. `dev.cleva.chumbucket://login-callback` is explicitly tested to
return `false`.

**Degraded without it:** links do not open the app. Everything downstream of the `Uri`
works and is tested; a paste-a-link field or any other source can call
`CallDeepLinkRouter.handle` today.

---

## 4. `android/app/src/main/AndroidManifest.xml` — intent filters

Two additions to the existing `<activity android:name=".MainActivity">`, alongside the
current Supabase OAuth callback filter. **Do not modify the existing filter.**

```xml
        <!-- Packet C: custom scheme for shared call/person/market links. -->
        <intent-filter>
            <action android:name="android.intent.action.VIEW" />
            <category android:name="android.intent.category.DEFAULT" />
            <category android:name="android.intent.category.BROWSABLE" />
            <data android:scheme="chumbucket" />
        </intent-filter>

        <!-- Packet C: https links. autoVerify needs assetlinks.json hosted at
             https://chumbucket.app/.well-known/assetlinks.json before it
             actually verifies; without it these open the chooser, which still
             works. -->
        <intent-filter android:autoVerify="true">
            <action android:name="android.intent.action.VIEW" />
            <category android:name="android.intent.category.DEFAULT" />
            <category android:name="android.intent.category.BROWSABLE" />
            <data android:scheme="https" android:host="chumbucket.app" android:pathPrefix="/c/" />
            <data android:scheme="https" android:host="chumbucket.app" android:pathPrefix="/u/" />
            <data android:scheme="https" android:host="chumbucket.app" android:pathPrefix="/m/" />
        </intent-filter>
```

iOS equivalent, in `ios/Runner/Info.plist`:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>app.chumbucket.links</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>chumbucket</string>
			</array>
		</dict>
	</array>
```

plus `com.apple.developer.associated-domains` = `applinks:chumbucket.app` in the
entitlements, which needs the matching `apple-app-site-association` file hosted.

The parser already accepts the **existing** `dev.cleva.chumbucket` scheme as well as
`chumbucket`. The current filter at `AndroidManifest.xml:37-42` is pinned to
`android:host="login-callback"`, so it delivers only the OAuth callback. If the team
prefers not to register a second scheme, add `<data android:scheme="dev.cleva.chumbucket"
android:host="c" />` (and `u`, `m`) instead of the `chumbucket` filter — nothing in the
Dart changes either way.

**Degraded without it:** as §3.

---

## 5. Packet B — the BFF procedures this slice will call

Not a patch; a statement of what `CallsRepository`
(`lib/features/calls/data/calls_repository.dart`) expects, so the tRPC surface and the
Dart implementation meet. Every payload is the FROZEN §3 shape, verbatim.

| Repository method | Suggested procedure | Input | Output |
| --- | --- | --- | --- |
| `fetchFeed` | `calls.feed` | `{ mode: 'global'\|'following', cursor?, limit }` | `{ entries: [{ call, author, market, result? , backCount, fadeCount, viewerHasCalled }], nextCursor?, servedAt }` |
| `fetchOpenMarkets` | `markets.open` | `{ category? }` | `VenueMarket[]` |
| `fetchMarketDetail` | `markets.detail` | `{ marketId }` | `{ market, snapshot?, viewerCall?, crowdSplit?, servedAt }` |
| `fetchCall` | `calls.get` | `{ callId }` | `{ entry, parent?, responses[] }` |
| `fetchPerson` | `people.get` | `{ personRef }` | `{ person, calls[], servedAt }` |
| `createCall` | `calls.create` | `CreateCallInput.toJson()` | one feed entry |
| `respondToCall` | `calls.respond` | `RespondToCallInput.toJson()` | `{ response, resultingCall?, invitation? }` |
| `fetchInvitations` | `calls.invitations` | `{}` | `ChallengeInvitation[]` |

Three behaviours the client relies on and cannot enforce alone:

1. **`crowdSplit` must be `null` until the caller has a locked call on that market.** The
   mobile client never renders it early, but the rule belongs server-side — the client
   simply cannot show what it was not sent.
2. **`back` and `fade` must create the actor's own `Call` and return it**; `challenge`
   must create no call and must carry no amount, no escrow and no transaction.
3. **`CallResult` is service-derived only**, by the §3 rule and nothing else. The client
   has `deriveCallOutcome` for local display, and it must agree exactly.

Error mapping the client already distinguishes: a transport/network failure →
`CallsOfflineException`; a 401/unauthenticated → `CallsSignedOutException`; a
validation/business refusal → `CallsRejectedException`; anything else → `CallsFailure`.

---

## 6. Not requested

- No new package beyond §3, and §3 is already in `pubspec.lock`.
- No migration. `*_social_calls_*.sql` (contract §5) is not written: the slice runs on
  `MockCallsRepository` and the real tables are owned by whoever lands the BFF.
- No change to `ChumbucketBottomNavigation`, `ArenaProvider`, or anything under
  `lib/features/authentication/**`.
- The one file outside Packet C's tree that **was** edited is
  `lib/features/arena/data/arena_models.dart` — the `YES`/`NO` cases in
  `ArenaBucketIndex`, which the contract (§2) assigns to Packet C explicitly. The change
  is purely additive: no existing label, index or throw behaviour moved.
