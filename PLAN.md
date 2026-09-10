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

### Phase B — Port state to capsules (M)

- **Do:**
  - New `lib/state/capsules/` directory:
    - `config_capsule.dart` — returns `AppConfig.dev`
    - `rest_capsule.dart` — `use.effect` builds/closes `RainbowRestClient`
    - `xmpp_capsule.dart` — same for `RainbowXmppClient`
    - `auth_capsule.dart` — `use.state<AuthState>` (initial `AuthState.signedOut()`)
    - `roster_capsule.dart` — depends on `restCapsule` + `authCapsule`; fetches on `signedIn`; returns `AsyncValue<List<RosterEntry>>`
    - `bubbles_capsule.dart` — same pattern
    - `presence_capsule.dart` — listens to `xmppEventsCapsule`, maintains `Map<String, Presence>`
    - `messages_capsule.dart` — family/parameterised: `messagesCapsule(threadKey)`; hydrates on demand; appends on XMPP events
    - `xmpp_events_capsule.dart` — wraps `xmppClient.events` as a rearch `Stream`
- **Acceptance:** all capsules compile; a new `test/capsules_test.dart` proves auth capsule transitions, roster capsule populates, messages capsule appends on stream input (using a fake `RainbowXmppClient`).

### Phase C — Rewrite screens as `RearchConsumer` widgets, delete `RainbowSession` (M)

- **Do:**
  - `LoginPage` → uses `authCapsule.setSignedIn(...)`; deletes `context.read<RainbowSession>()`.
  - `HomePage`, `ContactsTab`, `BubblesTab` → read from capsules.
  - Delete `lib/state/rainbow_session.dart` and remove `provider` imports.
  - Remove `ChangeNotifierProvider` from `app.dart`; the `RearchBootstrapper` wraps everything from `main.dart`.
- **Acceptance:**
  - `flutter test test/live_stub_integration_test.dart` still green.
  - Manual login / roster / bubbles walkthrough (same as RUNBOOK § 5) still works.
  - `git grep -R 'ChangeNotifier\|provider' lib/` returns nothing.

### Phase D — Adopt `flutter_chat_ui` for 1:1 chat (M)

- **Do:**
  - New `lib/ui/chat_view.dart` wrapping `Chat(messages, user, onSendPressed, ...)`.
  - Convert `messagesCapsule(threadKey)` output to `List<Message>` in a `RearchConsumer` selector.
  - `ChatPage` becomes a thin wrapper that resolves the peer's JID + user, wires the chat view.
  - Retire `lib/ui/chat_page.dart`'s custom bubbles (delete or replace the body).
- **Acceptance:**
  - Open Bob → chat renders with `flutter_chat_ui` styling (avatars, timestamps, "new" separators).
  - Send + receive round-trip works end-to-end.
  - Screenshot committed for reference.

### Phase E — Adopt `flutter_chat_ui` for group chat (S)

- **Do:**
  - `BubbleChatPage` → same pattern as Phase D but subscribes to the MUC threadKey.
  - MUC join still triggered from `initState`.
  - Include the sender's display name from the roster capsule when converting messages (via `metadata: {senderNick: …}`).
- **Acceptance:** open the seeded "Rainbow Stub Demo" bubble → send + receive works, sender nicks visible.

### Phase F — Wire live receipt / typing / read indicators to `flutter_chat_ui`'s status field (S)

- **Do:**
  - `flutter_chat_core` `Message.status` supports `sending | sent | delivered | seen | error`.
  - On outbound send: local status = `sending`. On XMPP `<received/>` (XEP-0184): `delivered`. On XMPP `<displayed/>` (XEP-0333): `seen`.
  - Chat states (`<composing/>`) drive `Chat(typingIndicatorOptions: ...)`.
- **Acceptance:** closes ROADMAP § 5.6 (delivery/read receipts) and § 5.7 (typing) as visible-in-UI features.

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
