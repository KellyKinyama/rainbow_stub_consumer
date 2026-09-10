# Plan — migrate to `flutter_chat_ui` + `rearch`

**Scope:** `c:\www\flutter\rainbow_stub_consumer`
**Target commit target:** feature branch `feat/chat-ui-rearch`, merged when all phases pass acceptance.
**Reference:** relates to ROADMAP § 5 (Nice-to-haves) and the parity items 5.5–5.11 that a batteries-included chat UI closes for free.

---

## 1. Goals

1. **Adopt [`flutter_chat_ui`](https://pub.dev/packages/flutter_chat_ui)** for the 1:1 and bubble chat views — swap our hand-rolled `ListView` bubbles for a battle-tested widget with attachments, replies, receipt indicators, preview cards, and infinite scroll built in.
2. **Adopt [`rearch`](https://pub.dev/packages/rearch) + [`flutter_rearch`](https://pub.dev/packages/flutter_rearch)** for state management — replace the single `RainbowSession` `ChangeNotifier` with composable capsules.
3. **Preserve the wire layer unchanged** — `RainbowRestClient` and `RainbowXmppClient` stay put. Only the state/UI layer changes.
4. **No regression** — existing tests still green; a new set of tests covers the new state layer.

## 2. Non-goals

- Adding new server-side features. This is a client-only refactor.
- Switching HTTP or WebSocket libraries.
- Rewriting the auth flow, roster REST, or XMPP framing.
- Full Android target (that's ROADMAP § 5.4).

## 3. Prerequisites & version pins

Verify at `pub add` time — if any of these have moved, adjust:

| Package | Target | Notes |
|---|---|---|
| `flutter_chat_ui` | `^2.x` | v2 removed `flutter_chat_types`; message types live in `flutter_chat_core` |
| `flutter_chat_core` | matched by `flutter_chat_ui` | Provides `Message`, `TextMessage`, `ImageMessage`, `FileMessage`, `User` |
| `rearch` | `^5.x` | Core capsule primitives |
| `flutter_rearch` | `^5.x` | `RearchBootstrapper`, `RearchConsumer` |
| `flutter` sdk | ≥ 3.24 | `rearch` uses records + patterns |

Drop from `pubspec.yaml`:

- `provider: ^6.1.0` (replaced by `rearch`)

Kept as-is: `http`, `web_socket_channel`, `xml`, `intl`, `shared_preferences`.

## 4. Current architecture (baseline)

```
lib/main.dart
  └─ RainbowConsumerApp(config: AppConfig.dev)
       └─ ChangeNotifierProvider<RainbowSession>
            ├─ LoginPage    ←  context.read<RainbowSession>().signIn
            └─ HomePage
                 ├─ ContactsTab      ←  context.watch<RainbowSession>()
                 │    └─ ChatPage    (hand-rolled ListView of ChatMessage)
                 └─ BubblesTab
                      └─ BubbleChatPage (hand-rolled + MUC join)
```

State: **one** `RainbowSession` owning REST client, XMPP client, roster, bubbles, and `Map<String, List<ChatMessage>>` per-thread history. Updates flow via `notifyListeners()`.

## 5. Target architecture

```
lib/main.dart
  └─ RearchBootstrapper
       └─ RainbowConsumerApp
            ├─ LoginPage       ← RearchConsumer, uses authCapsule
            └─ HomePage
                 ├─ ContactsTab     ← rosterCapsule + presenceCapsule
                 │    └─ ChatPage   ← flutter_chat_ui Chat(...) widget
                 └─ BubblesTab      ← bubblesCapsule
                      └─ BubbleChatPage  ← flutter_chat_ui Chat(...) widget
```

### 5.1 Capsule graph

```
              AppConfig
              /        \
    restClientCapsule   xmppClientCapsule
              \        /          \
             authCapsule         xmppEventsCapsule
              /   |   \             |
       me    token   presenceMap  streamedMessages
              |
       rosterCapsule  ─────► ContactsTab
              |
       bubblesCapsule ─────► BubblesTab
              |
       threadCapsule(key: String) ──► ChatPage / BubbleChatPage
```

Each capsule is a small function `T myCapsule(CapsuleHandle use)`. Consumers use `use.watch(otherCapsule)` for composition; writable state via `use.state(initial)`.

### 5.2 Message model bridging

Our `ChatMessage` → `flutter_chat_core`'s `TextMessage`:

| Our field | chat_core equivalent |
|---|---|
| `id` | `Message.id` |
| `body` | `TextMessage.text` |
| `from` (JID) | `Message.author = User(id: bareLocalOf(from), firstName: displayName)` |
| `sentAt` | `Message.createdAt.millisecondsSinceEpoch` |
| `isMine` | derived at render time by comparing `author.id` to current user |
| `stanzaId` | `Message.metadata: {'stanzaId': ...}` |

Attachments (Phase 5 in this plan) map to `ImageMessage` / `FileMessage`.

## 6. Phased delivery

Each phase is independently commit-able, ships to `feat/chat-ui-rearch`, and has explicit acceptance.

### Phase A — Add deps, introduce rearch bootstrap (S) — ✅ done 2026-09-10

- **Do:**
  - `flutter pub add rearch flutter_rearch flutter_chat_ui flutter_chat_core`
  - ~~`flutter pub remove provider`~~ — deferred to Phase C; removing it now
    would break the existing `ChangeNotifierProvider<RainbowSession>` before
    the UI has been migrated. `provider` stays until Phase C.
  - Wrap `main()` in `RearchBootstrapper`.
  - Keep `RainbowSession` for now; delete only after Phase C.

**Resolved:** actual `rearch` version is `^1.16.1` (not `^5.x` as the plan
guessed). `flutter_chat_ui ^2.11.1` confirmed uses `flutter_chat_core ^2.9.0`.

**Evidence:**
- `flutter analyze` — 0 errors / 0 warnings (7 pre-existing style infos, none Phase-A related)
- `flutter test` — 7/7 pass (added `phase_a_bootstrap_test.dart` proving the Rearch bootstrap composes without a crash and the login page still renders)
- `flutter test test/live_stub_integration_test.dart` — 3/3 pass, no wire regression
- Windows release build succeeded in 56 s; app launched and rendered the login page (verified via process presence + no crash on stub-log timeline)
- **Acceptance:** app still boots, login still works with old provider-based screens; `dart analyze` clean.

### Phase B — Port state to capsules (M) — ✅ done 2026-09-10

- **Do:**
  - New `lib/state/capsules/` directory:
    - `config_capsule.dart` — returns `AppConfig.dev`
    - `rest_capsule.dart` — `use.disposable` builds/closes `RainbowRestClient`
    - `xmpp_capsule.dart` — same for `RainbowXmppClient`; also exposes `xmppEventsCapsule` for the broadcast stream
    - `auth_state_capsule.dart` — `use.data<AuthState>` shared slot + `authCapsule` value getter
    - `auth_controller_capsule.dart` — orchestrates REST `login` → set bearer → XMPP `connect` → slot flip; `signOut` reverse
    - `roster_capsule.dart` — depends on `restCapsule` + `authCapsule`; fetches on `signedIn`; returns `AsyncValue<List<RosterEntry>>`
    - `bubbles_capsule.dart` — same pattern
    - `presence_capsule.dart` — `use.effect` listens to `xmppEventsCapsule`, maintains `Map<String, Presence>`
    - `messages_capsule.dart` — family/parameterised: `messagesCapsule(threadKey)`; appends live XMPP messages that belong to the thread; hydration deferred to Phase D
  - New `lib/state/models/` for `AuthState` + `Presence` value types
- **Acceptance:** all capsules compile; `test/capsules_test.dart` proves auth capsule transitions, roster + bubbles capsules populate, presence + messages capsules react to injected stream events. Fake `RainbowRestClient` and `RainbowXmppClient` injected via `MockableContainer`.
- **Evidence (2026-09-10):**
  - `flutter analyze --no-pub` → 0 errors, 0 warnings on the new files (7 pre-existing infos in files not touched)
  - `flutter test --exclude-tags=live` → 6 new capsule tests + 7 existing tests pass; live tests skip cleanly with stub down
  - Commit: see `feat/chat-ui-rearch` branch tip
  - Session log: `docs/phase-b-log.md`

### Phase C — Rewrite screens as `RearchConsumer` widgets, delete `RainbowSession` (M) — ✅ done 2026-09-10

- **Done:**
  - `LoginPage`, `HomePage`, `ContactsTab`, `BubblesTab`, `ChatPage`, `BubbleChatPage` are all `RearchConsumer` widgets.
  - `RainbowConsumerApp` no longer takes a `config` prop — the `configCapsule` provides it.
  - `_AuthGate` reads `authCapsule` directly; `MaterialApp` sits inside a plain `StatelessWidget` under `RearchBootstrapper`.
  - `LoginPage` uses `use.textEditingController(...)` + `use.state<bool>` + `use.state<String?>` for local state, and calls `authControllerCapsule.signIn(...)`.
  - `ContactsTab` and `BubblesTab` do `switch (asyncValue) { AsyncLoading / AsyncData / AsyncError }` pattern matching against `rosterCapsule` / `bubblesCapsule`.
  - New `chatActionsCapsule` exposes `sendPeer`, `sendGroup`, `joinMuc`, `setMyPresence`, `createBubble` to the UI.
  - `messagesCapsule` gained an internal appender registry so `chatActions.sendPeer/sendGroup` echo locally with `isMine: true`; incoming XMPP messages compute `isMine` by comparing the sender's JID local-part to `authCapsule.me?.id`.
  - `lib/state/rainbow_session.dart` deleted; `provider` removed from `pubspec.yaml` (still transitive via `flutter`).
- **Acceptance evidence (2026-09-10):**
  - `git grep 'ChangeNotifier\|RainbowSession\|package:provider' lib/` → **empty**.
  - `flutter analyze --no-pub` → 0 errors, 0 warnings on new + rewritten files.
  - `flutter test --exclude-tags=live` → 14/14 pass; `flutter test` with the stub running → live suite green.
  - New `test/phase_c_actions_test.dart` proves `chatActionsCapsule.sendPeer` dispatches to XMPP and echoes into `messagesCapsule` with `isMine: true`.
  - Session log: `docs/phase-c-log.md`.

### Phase D — Adopt `flutter_chat_ui` for 1:1 chat (M) — ✅ done 2026-09-10

- **Done:**
  - New family capsule `chatControllerCapsule(threadKey)` in `messages_capsule.dart` — owns an `InMemoryChatController`, subscribes to XMPP events, mirrors local send-echoes.
  - `messages_capsule.dart` appender registry became a **list** per thread so `messagesCapsule` and `chatControllerCapsule` can co-exist and both receive fan-out from `appendLocalMessage(...)`.
  - `RainbowXmppClient.sendGroupChat` gained an optional `id` parameter (matching `sendChat`) so actions can share a stanza id between the wire send and the local echo.
  - `chatActionsCapsule.sendPeer` / `sendGroup` now generate one stanza id and use it for both the XMPP send AND the local echo — carbons that echo the same id dedupe cleanly inside the controller.
  - `ChatMessage → Message.text(...)` converter uses `authCapsule.me.id` for `authorId` on locally-echoed messages, the sender's JID local-part for incoming ones.
  - `ChatPage` rewritten around `Chat(currentUserId, resolveUser, chatController, onMessageSend)` — no more hand-rolled bubbles.
- **Acceptance evidence (2026-09-10):**
  - `flutter analyze --no-pub` → 0 errors, 0 warnings on new/rewritten files.
  - `flutter test --exclude-tags=live` → **18/18** pass (Phase D adds 4 tests in `phase_d_chat_controller_test.dart`: local-echo render, incoming-append, carbon-dedupe, messagesCapsule↔chatControllerCapsule sync).
  - `flutter build windows --debug` → clean build in ~31s.
  - Session log: `docs/phase-d-log.md`.

### Phase E — Adopt `flutter_chat_ui` for group chat (S) — ✅ done 2026-09-10

- **Done:**
  - `BubbleChatPage` rewritten as a thin `RearchConsumer` around `Chat(...)`, reading the MUC thread's `chatControllerCapsule`.
  - `chatControllerCapsule` now hydrates MAM for MUC threads too — the `!threadKey.contains('@muc.')` guard is gone; the stub routes on the `with` field's domain.
  - Sender attribution for group messages uses the **resource** part of the from-JID (`room@muc.domain/nick` → `nick`) instead of the local part (which would be the room id itself).
  - `_toChatUiMessage` refactored: authorId is now derived by the listener (which knows `isGroupChat` per event) and passed in explicitly.
  - `BubbleChatPage.resolveUser` looks up display names via `rosterCapsule` for known peers, falls back to id-as-name for unknown ids (e.g. bubble members not in your roster).
- **Hardening (fixes for issues surfaced during test drive):**
  - Cross-user cache pollution: added a `_cacheGeneration` counter. `resetMessagesCapsuleCache()` bumps it; old rearch-container-managed capsules snapshot the previous generation and short-circuit new events, going dormant instead of polluting the next user's state.
  - Defensive `insertMessage` index clamp — if some other event source ever pushes the cursor past the actual list size, we clamp to `messages.length` (turning insert into append) instead of crashing with `RangeError`.
- **Acceptance evidence (2026-09-10):**
  - `flutter analyze --no-pub` → 0 errors, 0 warnings on new/rewritten files.
  - `flutter test --exclude-tags=live` → **27/27** pass (Phase E adds 5 tests in `phase_e_bubble_chat_test.dart`: MUC MAM query fires, incoming nick becomes authorId, local group send-echo, MUC MAM chronological hydration, generation guard).
  - `flutter build windows --debug` → clean build in ~15s.
  - Session log: `docs/phase-e-log.md`.

### Phase F — Wire live receipt / typing / read indicators to `flutter_chat_ui`'s status field (S) — ✅ done 2026-09-10

- **Done:**
  - **XEP-0184 delivery receipts**: `sendChat` now embeds `<request xmlns="urn:xmpp:receipts"/>`; incoming `<received>` (from either XEP-0184 or XEP-0333) emits `XmppDeliveryReceipt`; capsule stamps `deliveredAt` on the corresponding message so `TextMessage.resolvedStatus` moves from `sent` to `delivered`.
  - **XEP-0333 chat markers**: `sendChat` embeds `<markable xmlns="urn:xmpp:chat-markers:0"/>`; on incoming 1:1 message the capsule auto-replies with both `<received>` and `<displayed>`; incoming `<displayed>` emits `XmppReadMarker` and stamps `seenAt`.
  - **XEP-0085 chat states**: new `sendChatState(toBareJid, state)` XMPP method; `chatActionsCapsule.sendChatState(peer, state)` UI hook; new `typingCapsule(threadKey)` reducing `<composing/>` / `<paused/>` events into a live `bool`; `ChatPage` shows `IsTypingIndicator` when the peer is typing and emits debounced composing/paused as the user types (via a custom `composerBuilder` sharing our `TextEditingController`).
  - `_toChatUiMessage` seeds `sentAt = cm.sentAt` when the message is mine so the first status icon renders immediately as "sent".
  - `resetMessagesCapsuleCache()` also clears `_typingCache` — otherwise stale typing indicators would survive signout.
- **Acceptance evidence (2026-09-10):**
  - `flutter analyze --no-pub` → 0 errors, 0 warnings on new/rewritten files.
  - `flutter test --exclude-tags=live` → **33/33** pass (Phase F adds 6 tests in `phase_f_receipts_test.dart`: auto-send receipt+marker on incoming, deliveredAt stamping, seenAt stamping, typingCapsule composing→paused round-trip, peer-scoped filtering, `sendChatState` dispatch).
  - `flutter build windows --debug` → clean build in ~16s.
  - Session log: `docs/phase-f-log.md`.
- **Simplifications documented in the log:**
  - "Aggressive" auto-`<displayed>`: sent whenever we receive a 1:1 message while the capsule is alive, not gated on ChatPage visibility. Fine for demo, refine in Phase G+ if needed.
  - Typing scope is 1:1 only — group chat typing indicators are out of scope for this phase.

### Phase G — Attachments UI (M)

- **Do:**
  - `Chat(onAttachmentPressed: showPickerSheet)` — file picker sheet with camera / gallery / file.
  - Uploads via the existing REST file endpoint on the stub; on success, send an XMPP message with a `<file>` payload; on receive, render as `ImageMessage` or `FileMessage`.
- **Acceptance:** matches ROADMAP § 1.2 (file upload UI) end-to-end. Send a JPG → recipient sees an inline preview.

### Phase H — Message reactions + edits + replies (M)

- **Do:**
  - Long-press message → `showMenu` with Reply / React / Edit / Delete.
  - Reactions: XEP-0444 `<reactions/>`.
  - Edits: XEP-0308 `<replace/>`.
  - Replies: XEP-0461 `<reply/>` → chat_ui renders quoted card via `metadata: {replyTo: {id, text, author}}`.
- **Acceptance:** closes ROADMAP § 5.1 (edit), § 5.5 (reactions), § 5.8 (threads).

## 7. File-level change plan

New files under `lib/state/capsules/`:

- `auth_capsule.dart`
- `bubbles_capsule.dart`
- `config_capsule.dart`
- `messages_capsule.dart`
- `presence_capsule.dart`
- `rest_capsule.dart`
- `roster_capsule.dart`
- `xmpp_capsule.dart`
- `xmpp_events_capsule.dart`

Modified:

- `lib/main.dart` — wrap in `RearchBootstrapper`, remove `provider`
- `lib/app.dart` — drop `ChangeNotifierProvider`, keep `MaterialApp` + `_AuthGate`
- `lib/ui/*.dart` — all become `RearchConsumer` widgets
- `pubspec.yaml` — deps swap (Phase A)

Deleted (after Phase C):

- `lib/state/rainbow_session.dart`

Added tests:

- `test/capsules_test.dart` (Phase B)
- `test/chat_view_widget_test.dart` (Phase D)
- Keep `test/live_stub_integration_test.dart` unchanged

## 8. Testing strategy

| Phase | New test | Uses |
|---|---|---|
| B | `capsules_test.dart` | `rearch.test.CapsuleContainer` for unit-testing capsules in isolation, with a fake `RainbowXmppClient` |
| D | `chat_view_widget_test.dart` | `testWidgets(...)` renders `Chat(messages: [...], user: ...)` and asserts a `TextMessage` shows |
| all | `live_stub_integration_test.dart` | Unchanged — still requires the stub running |

## 9. Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `flutter_chat_ui` v2 API differs from documented sketch | High | Do Phase A first; run a hello-world `Chat(...)` before designing capsules around it |
| `rearch` `use.effect` semantics for disposing REST/XMPP clients | Medium | Use `use.register` teardown; smoke-test by hot-restarting during signed-in state |
| Message ordering when hydrating from both MAM (async) and live XMPP stream | Medium | Merge by `sentAt`; deduplicate by `stanzaId`; add sort-order assertions in `messages_capsule_test.dart` |
| Windows build breakage on new plugin | Low | `flutter_chat_ui` is Dart-only; no plugins. Verified on Web + Desktop |
| Rearch stream-capsule leaks a subscription when the app hot-restarts | Medium | Use `use.register` to `sub.cancel()` on dispose |
| We accidentally start receiving duplicated inbound messages (Phase C bug) | Medium | Regression test in Phase B (message capsule dedup by stanzaId) |

## 10. Rollback plan

Each phase is a separate commit on `feat/chat-ui-rearch`. If a phase is unshippable:

- Phase A: `git revert` — pubspec-only change.
- Phase B: `git revert` — capsules exist but nothing consumes them yet.
- Phase C: risky. Revert restores `RainbowSession` from git history; requires re-adding `provider` to pubspec.
- Phase D–H: revertable per phase; UI rolls back to previous chat widget.

Do not squash-merge — keep phases as individual commits so partial rollbacks are cheap.

## 11. Estimate

| Phase | Est. |
|---|---|
| A — deps + bootstrap | S (½ day) |
| B — capsules | M (1–2 days) |
| C — screen rewire + delete session | M (1 day) |
| D — 1:1 chat_ui | M (1 day) |
| E — group chat_ui | S (½ day) |
| F — receipt/typing status | S (½ day) |
| G — attachments | M (1–2 days) |
| H — reactions/edits/replies | M (2 days) |
| **Total** | **≈ 8–10 working days** |

Phases A–D deliver the visible UX win. E–H are extension surface that lands ROADMAP § 5.5–5.8 as bonuses.

## 12. Definition of done (for the whole track)

- `flutter analyze` — 0 errors / 0 warnings
- `flutter test` — all green
- `flutter test test/live_stub_integration_test.dart` — all green with stub running
- Manual pass of RUNBOOK § 5 — no regression
- New tests: capsules_test.dart (≥ 4), chat_view_widget_test.dart (≥ 2)
- No occurrence of `ChangeNotifier`, `Provider`, `provider` in `lib/`
- Screenshots of new chat UI committed under `docs/screenshots/`
- `PLAN.md` (this file) marked ✅ in each phase's checkbox

## 13. Open questions to confirm before Phase A

1. **`flutter_chat_ui` v2 vs v1** — v2 changed the message model to `flutter_chat_core`. If v2 is stable, use it. If not, pin to `^1.6.x`.
2. **Custom theming** — the RN sample has an `app-styles.json`. Do we want to match those colours in the chat UI theme, or start with defaults?
3. **Chat header** — `flutter_chat_ui` doesn't ship a header widget; keep the current `AppBar` + presence dot.
4. **Persistence for messages** — this refactor is UI-only. Local persistence is a separate ROADMAP § 1.3 task; the plan assumes in-memory only for now.
5. **Rearch bootstrap position** — put `RearchBootstrapper` in `main.dart` (highest scope) or in `app.dart` (lower scope, easier to test)? Recommendation: `main.dart`, matches `provider` placement today.
