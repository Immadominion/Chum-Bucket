# Integration request — Packet H (analytics instrumentation for the validation experiment)

**Raised:** 13 September 2026 · **Packet:** H · **Owner to apply:** integration

Packet H adds `lib/core/analytics/**` and instruments the two files it owns:
`lib/features/calls/providers/calls_provider.dart` and `lib/features/receipts/**`.

**Nothing below is needed for the packet to be correct today.** `lib/core/analytics`
analyses clean, its tests pass, and the events that the provider and the receipt sheet
can observe are already firing. Each patch says exactly which roadmap §9 event is
unmeasurable until it lands.

| # | File | Event(s) it unlocks | Unmeasurable without it |
| --- | --- | --- | --- |
| 1 | `lib/features/calls/presentation/screens/call_feed_screen.dart` | `feed_call_impression` | **the denominator of every §9 go signal** |
| 2 | `lib/features/calls/presentation/screens/call_person_screen.dart` | `feed_call_impression` (person surface) | impressions on a person's record |
| 3 | `lib/features/calls/presentation/screens/call_detail_screen.dart` | `call_opened` surface, receipt surface | where an open came from; one spurious open per response |
| 4 | `lib/features/calls/deeplink/call_deep_link_router.dart` | `share_opened` | the share → open → call funnel |
| 5 | `call_composer_sheet.dart`, `call_response_sheet.dart`, `market_detail_screen.dart` | surface on `call_created` / `call_backed` / `call_faded` | which surface produces calls |
| 6 | `lib/features/arena/providers/arena_provider.dart` | `follow_created` | §9: *"at least five users follow somebody because of a category-specific record"* |
| 7 | `lib/features/authentication/**` (Packet A) | `wallet_link_started`, `wallet_link_succeeded` | the wallet-link funnel |
| 8 | Phase-4 funded UI (does not exist yet) | `fund_quote_viewed`, `fund_order_signed`, `fund_order_confirmed` | the funded funnel, when the flag is turned on |
| 9 | `lib/main.dart` | one shared recorder | nothing — see §9 |

Every patch is additive, compiles against the package as shipped, and adds no dependency.

The one import every patch needs:

```dart
import 'package:chumbucket/core/analytics/analytics.dart';
```

---

## 0. The rule that governs every patch below

**Never pass a wallet address, a signature, a balance, a stake, a token, an email, a
display name, a handle, a market question or a thesis into an analytics call.** You do
not have to remember this: `AnalyticsPrivacyGuard` rejects the event and it never reaches
a sink. But a rejected event is a *silently missing measurement*, so getting it right the
first time is still cheaper. Pass ids and enum wire tokens (`side.wire`, `outcome.wire`).

---

## 1. `lib/features/calls/presentation/screens/call_feed_screen.dart` — impressions (REQUIRED)

This is the one patch the experiment cannot be run without. `feed_call_impression` is the
denominator of all four §9 go signals, and the provider cannot observe what is on screen.

`CallImpressionReporter` adds no box, no padding and no paint — it returns its child
unchanged — and it reports exactly one impression per `(surface, callId)` per session, so
a `Consumer` rebuild or a scroll back to the top cannot inflate it. Proven in
`test/analytics_impression_widget_test.dart`.

In `_content`, replace the `itemBuilder`'s returned `CallCard` (currently at
`call_feed_screen.dart:227-238`) with:

```dart
              final entry = provider.feed[index];
              final surface =
                  provider.feedMode == CallFeedMode.following
                      ? AnalyticsSurface.feedFollowing
                      : AnalyticsSurface.feedGlobal;
              return CallImpressionReporter(
                callId: entry.call.id,
                marketId: entry.market.id,
                authorId: entry.author.id,
                surface: surface,
                position: index,
                side: entry.call.side.wire,
                outcome: entry.outcome.wire,
                venue: entry.market.venue.wire,
                venueIsDemo: entry.market.venue.isDemo,
                thesisPresent: entry.call.thesis != null,
                thesisLengthBucket: ThesisLengthBucket.of(entry.call.thesis),
                viewerIsSignedIn: provider.isSignedIn,
                recorder: provider.analytics,
                child: CallCard(
                  entry: entry,
                  onOpenMarket: () => _openMarket(entry.market.id),
                  onOpenPerson: () => _openPerson(entry.author.id),
                  onRespond:
                      entry.author.id == provider.viewerUserId
                          ? null
                          : () => _respond(entry),
                  onShareReceipt: () => _shareReceipt(entry),
                ),
              );
```

`ThesisLengthBucket.of` takes the text and returns one of four wide buckets; the text
itself is discarded in the same expression and never reaches an event.

`recorder: provider.analytics` matters: it uses the provider's recorder, so the
impressions share one session dedupe store and one treatment with everything the provider
emits. Omitting it falls back to the ambient recorder, which is correct but would diverge
if the shell ever constructs the provider with its own.

Also pass the surface through the two actions on this screen:

```dart
  Future<void> _respond(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      widget.onSignInRequested?.call();
      return;
    }
    await showCallResponseSheet(
      context: context,
      entry: entry,
      surface: _surface(provider),   // see §5
    );
  }

  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      surface: _surface(provider),
      analytics: provider.analytics,
      receipt: CallReceipt.fromEntry(
        entry,
        shareUrl: provider.shareLinkForCall(entry.call.id),
      ),
    );
  }

  AnalyticsSurface _surface(CallsProvider provider) =>
      provider.feedMode == CallFeedMode.following
          ? AnalyticsSurface.feedFollowing
          : AnalyticsSurface.feedGlobal;
```

`showCallReceiptSheet`'s `surface` and `analytics` parameters are optional and already
default sensibly, so this part can land later than the impression block.

**Degraded without it:** `feed_call_impression` never fires. The people-first vs
market-first comparison has no denominator, and §9's "8 of 20 return", "30% of calls from
a Back/Fade card" and "five follows from a record" are all unanswerable as rates.

---

## 2. `lib/features/calls/presentation/screens/call_person_screen.dart` — impressions

Same wrapper, `surface: AnalyticsSurface.personProfile`, around the `CallCard` this screen
builds for each of the person's calls. A card seen on a person's page is a different
impression from the same card in the feed, and the recorder treats it as one — that is
what makes "people follow because of a record" separable from "people scroll a feed".

And for the receipt:

```dart
  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      receipt: _receiptFor(provider, entry),
      surface: AnalyticsSurface.personProfile,
      analytics: provider.analytics,
    );
  }
```

**Degraded without it:** impressions on a person's page are invisible, so a follow that
came from reading a record looks like it came from nowhere.

---

## 3. `lib/features/calls/presentation/screens/call_detail_screen.dart` — surface, and one over-count

Two changes, both one line.

`initState` (`call_detail_screen.dart:43-47`) — a call opened from a shared link is not
the same fact as one opened from the feed:

```dart
      if (mounted) {
        context.read<CallsProvider>().loadCall(
          widget.callId,
          surface:
              widget.sharedByHandle != null
                  ? AnalyticsSurface.deepLink
                  : AnalyticsSurface.callDetail,
        );
      }
```

`_respond` (`call_detail_screen.dart:58`) — the refresh after a response is a cache
refill, not a person opening a call. Left as is it double counts every response as an
extra open:

```dart
      await provider.loadCall(widget.callId, force: true, reportOpen: false);
```

`_shareReceipt` — add `surface: AnalyticsSurface.callDetail` and
`analytics: provider.analytics` as in §1.

The identical `loadCall(..., force: true)` refresh in
`call_person_screen.dart:_respond` is `loadPerson`, which reports nothing, so it needs no
change.

**Degraded without it:** every open looks like a feed open, and `call_opened` is inflated
by roughly one per Back/Fade/Challenge.

---

## 4. `lib/features/calls/deeplink/call_deep_link_router.dart` — `share_opened`

Add to `handle`, inside each resolved branch, before the `navigator.push`:

```dart
      case ResolvedCallLink(:final detail, :final sharedByHandle):
        provider.analytics.record(
          AnalyticsEvents.shareOpened(
            linkKind: AnalyticsLinkKind.call,
            hasReferrer: sharedByHandle != null,
            callId: detail.entry.call.id,
            viewerIsSignedIn: provider.viewerUserId != null,
          ),
        );
```

```dart
      case ResolvedPersonLink(:final detail, :final sharedByHandle):
        provider.analytics.record(
          AnalyticsEvents.shareOpened(
            linkKind: AnalyticsLinkKind.person,
            hasReferrer: sharedByHandle != null,
            personId: detail.person.id,
            viewerIsSignedIn: provider.viewerUserId != null,
          ),
        );
```

`hasReferrer` records only *that* the link named a sharer. **Do not pass
`sharedByHandle` itself** — a handle is user-authored and the guard drops the event.

`ResolvedMarketLink` has no `share_opened` in the §9 list and is deliberately left alone.

**Degraded without it:** `share_started` has no matching `share_opened`, so the share loop
— the only organic acquisition path in the MVP — cannot be measured end to end.

---

## 5. Passing the surface into the two write sheets

`showCallResponseSheet` and `showCallComposerSheet` call `provider.respondToCall` and
`provider.createCall`, both of which now take an optional `surface`. Neither packet-H
event is lost without this; only the `surface` dimension is.

`call_response_sheet.dart` — add a `surface` field to the sheet widget and the
`showCallResponseSheet` function, then at `call_response_sheet.dart:80`:

```dart
      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: widget.entry.call.id,
          kind: _kind,
          confidence: /* unchanged */,
          thesis: note.isEmpty ? null : note,
        ),
        surface: widget.surface,
      );
```

`call_composer_sheet.dart` — the same, at `call_composer_sheet.dart:91`:

```dart
      final entry = await provider.createCall(
        CreateCallInput(/* unchanged */),
        surface: widget.surface,
      );
```

`market_detail_screen.dart` passes `AnalyticsSurface.marketDetail`; the feed passes its
mode-derived surface from §1.

**Degraded without it:** `call_created`, `call_backed` and `call_faded` still fire with
every other dimension; the `surface` property is simply absent.

---

## 6. `lib/features/arena/providers/arena_provider.dart` — `follow_created`

§9 go signal: *"at least five users follow somebody because of a category-specific
record."* Follow lives in `ArenaProvider.toggleFollow` (`arena_provider.dart:732`), which
Packet H does not own.

In the `else` branch, after `_followedWallets.add(targetWallet)`:

```dart
        AnalyticsRecorder.instance.record(
          AnalyticsEvents.followCreated(
            personId: /* the canonical public.users.id — see the warning */,
            surface: AnalyticsSurface.personProfile,
          ),
        );
```

**Warning, and the reason this is a request rather than a patch to apply blindly.**
`toggleFollow` is keyed by `targetWallet`. Contract §0.3: identity is `public.users.id`
and **nothing authorises on a wallet string**. Passing `targetWallet` as `personId` would
be recording a wallet address in analytics — the guard drops the event (base58 shape), so
the failure mode is silent under-counting rather than a leak, but it is still a failure.

So this patch should land **after** Packet A's `auth_user_id` mapping gives the follow
path a canonical user id, or alongside a follow action in the calls slice keyed by
`public.users.id`. `unfollow` is deliberately not instrumented: §9 asks for
`follow_created` only.

**Degraded without it:** the follow go signal is counted by hand.

---

## 7. Packet A — `wallet_link_started` / `wallet_link_succeeded`

Owned by `lib/features/authentication/**`. Two lines, at the two moments the roadmap's
§4 flow names:

```dart
// When the person taps "Connect wallet" or "Fund this call", before the MWA
// authorize() call:
AnalyticsRecorder.instance.record(
  AnalyticsEvents.walletLinkStarted(surface: AnalyticsSurface.callDetail),
);

// After the server has verified the SIWS proof and consumed the nonce:
AnalyticsRecorder.instance.record(
  AnalyticsEvents.walletLinkSucceeded(surface: AnalyticsSurface.callDetail),
);
```

**Neither constructor accepts an address, a nonce, a signature or a chain.** That is
deliberate and not an oversight: none of them is needed to count funnel steps, and every
one of them is on the guard's denylist. Do not add them.

**Degraded without it:** the wallet-link funnel is unmeasured. The free loop is
unaffected, which is the point — §7's `funded_positions` flag defaults off.

---

## 8. Phase 4 — the three `fund_*` events

No funded UI exists (contract §7: `funded_positions` is off, server-enforced), so there is
nothing to patch. When Phase 4 lands, the three constructors are already written and
tested:

```dart
AnalyticsEvents.fundQuoteViewed(callId: …, marketId: …, side: side.wire);
AnalyticsEvents.fundOrderSigned(orderId: …, callId: …);      // records SUBMITTED
AnalyticsEvents.fundOrderConfirmed(orderId: …, callId: …, fundingState: state.wire);
```

`fundOrderSigned` hard-codes `fundingState: 'SUBMITTED'` because contract §3 says a
signature is not a fill. `fundOrderConfirmed` passes the venue's state through verbatim
and keys its dedupe on `(orderId, fundingState)`, so a `PARTIAL` cannot swallow a later
`FILLED` and a `FILLED` cannot be reported twice.

**No money-shaped parameter exists on any of the three** — no price, no maximum spend, no
fee, no size. The funnel question is how many people reached each step.

---

## 9. `lib/main.dart` — optional: one shared recorder

**Not required.** `CallsProvider` and the receipt sheet default to
`AnalyticsRecorder.instance`, a process-wide recorder over a bounded in-memory sink, so
instrumentation works with no bootstrap change at all.

Apply this only if you want one explicit recorder, or want to replace the sink later:

```dart
        ChangeNotifierProvider<CallsProvider>(
          create:
              (_) => CallsProvider(
                repository: MockCallsRepository(...),
                analytics: AnalyticsRecorder.instance,
              ),
        ),
```

And wherever `CallsProvider.setViewer(userId)` is called on sign-in, nothing else is
needed: `setViewer` already calls `AnalyticsRecorder.setUnit`, which assigns the
experiment arm and clears the impression dedupe for the new account.

**Degraded without it:** nothing.

---

## 10. What this packet deliberately did not do

* **No destination.** `AnalyticsSink` has exactly two implementations here:
  `InMemoryAnalyticsSink` (bounded ring, default) and `NoopAnalyticsSink`. No HTTP, no
  Supabase function, no third-party SDK. Choosing a destination is a separate, explicitly
  approved decision; when it is taken, it is one class implementing `AnalyticsSink` and
  one line in §9 above. **Put it behind `AnalyticsRecorder`, never beside it** — the
  recorder is where the privacy guard runs.
* **No route through `lib/core/services/analytics_service.dart`.** That service posts to
  a Supabase Edge Function on every call and its payloads carry `wallet_address`,
  `creator_wallet`, `winner_wallet`, `amount_sol` and `fee_sol` — precisely what Packet
  I's acceptance forbids. It was read and left untouched; the reasoning is in the library
  comment at the top of `lib/core/analytics/analytics_sink.dart`. If the two are ever
  unified, the direction is to put the guard in front of that service.
* **No metric computation.** This packet makes the seven-day test measurable. Reading the
  result is a later job.
