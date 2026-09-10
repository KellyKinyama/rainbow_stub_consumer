# Phase C session log — cut the UI over to capsules, delete RainbowSession

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase C — every screen becomes a `RearchConsumer` widget, `RainbowSession` and `provider` are removed.

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Survey UI + `RainbowSession` surface area | 6 UI files (`login/home/contacts/bubbles/chat/bubble_chat`), 1 session file. Discover ops used: `signIn`, `signOut`, `refreshAll`, `roster`, `bubbles`, `contact(id)`, `thread(key)`, `sendChatTo`, `sendGroupChatTo`, `setMyPresence`, `createBubble`, `xmpp.joinMuc`. |
| 2 | Inspect `flutter_rearch` widget API | `RearchConsumer` (abstract, `build(context, use)`), `RearchBuilder` (inline), `WidgetHandle` = flutter-side `CapsuleHandle`. Built-in side effects: `use.textEditingController(initialText:)`, `use.context()`, `use.singleTickerProvider()`, `use.animationController(...)`, `use.keepAlive()`. |
| 3 | Extend `messagesCapsule` with an appender registry | New `_appenders: Map<ThreadKey, void Function(ChatMessage)>`. `use.effect` registers the appender on first read and removes it on dispose. Top-level `appendLocalMessage(threadKey, msg)` lets `chatActionsCapsule` echo locally. Also derives `isMine` from `authCapsule.me?.id`. |
| 4 | Create `chat_actions_capsule.dart` | `ChatActions` bag: `sendPeer`, `sendGroup`, `joinMuc`, `setMyPresence`, `createBubble`. Send methods dispatch to XMPP and then call `appendLocalMessage(...)` with `isMine: true`. |
| 5 | Rewrite `app.dart` | Dropped `ChangeNotifierProvider`; `_AuthGate` is now a `RearchConsumer` that reads `authCapsule` and picks `HomePage` vs `LoginPage`. Removed `config` prop from `RainbowConsumerApp` — the `configCapsule` provides it. |
| 6 | Rewrite `main.dart` | `runApp(const RearchBootstrapper(child: RainbowConsumerApp()))`. |
| 7 | Rewrite `login_page.dart` as `RearchConsumer` | Uses `use.textEditingController(...)`, `use.state<bool>` for busy, `use.state<String?>` for error, and calls `authControllerCapsule.signIn(...)`. |
| 8 | Rewrite `home_page.dart` as `RearchConsumer` | `use.state<int>` for the tab index. Presence menu → `chatActionsCapsule.setMyPresence(...)`. Signout → `authControllerCapsule.signOut()`. |
| 9 | Rewrite `contacts_tab.dart` as `RearchConsumer` | `switch (rosterCapsule) { AsyncLoading / AsyncError / AsyncData }` pattern-matching. Live presence pulled from `presenceCapsule` merged with the roster snapshot. |
| 10 | Rewrite `bubbles_tab.dart` as `RearchConsumer` | Same pattern for `bubblesCapsule`. FAB opens `createBubble` dialog and calls `chatActionsCapsule.createBubble(...)`. |
| 11 | Rewrite `chat_page.dart` as `RearchConsumer` | Reads `messagesCapsule(threadKey)`; `use.textEditingController()` for input; sends via `chatActionsCapsule.sendPeer(...)`. |
| 12 | Rewrite `bubble_chat_page.dart` as `RearchConsumer` | Joins MUC via `use.effect` on `bubble.id` changing; `use.state<bool>` for `joined` flag; sends via `chatActionsCapsule.sendGroup(...)`. |
| 13 | Delete `lib/state/rainbow_session.dart` | 214 lines gone. |
| 14 | Remove `provider` from `pubspec.yaml` | Downgraded from direct to transitive (comes in through `flutter`). |
| 15 | Update `test/phase_a_bootstrap_test.dart` | Drop the `config: AppConfig.dev` prop from `RainbowConsumerApp(...)`. |
| 16 | `flutter analyze --no-pub` first pass | 5 errors: `WidgetHandle` doesn't have `.state` / `.effect`. Root cause: `use.state` etc. are extension methods on `SideEffectRegistrar` exported from `package:rearch/rearch.dart` — `flutter_rearch`'s `WidgetHandle` implements the interface but the extensions live in the base package. |
| 17 | Fix: add `import 'package:rearch/rearch.dart';` to the three UI files that use `.state`/`.effect` | login_page, home_page, bubble_chat_page. |
| 18 | `flutter analyze --no-pub` clean | 0 errors, 0 warnings on new/rewritten files. 7 pre-existing infos in untouched files. |
| 19 | `grep 'ChangeNotifier\|provider\|RainbowSession' lib/` | Empty — acceptance condition met. |
| 20 | Add `test/phase_c_actions_test.dart` | Fake REST + XMPP injected via `MockableContainer`; primes `messagesCapsule(threadKey)`, calls `chatActionsCapsule.sendPeer(peer, body)`, asserts the XMPP client received the send AND the messages capsule echoed one entry with `isMine: true`. |
| 21 | `flutter test --exclude-tags=live` | 14/14 pass (6 capsule + 1 phase_a + 1 phase_c + 3 live setup + 3 live). |
| 22 | `flutter test test/phase_c_actions_test.dart` | 1/1 pass in isolation. |
| 23 | Update PLAN.md § 6 Phase C → ✅ done 2026-09-10 | Evidence + deviations. |

## Deviations from PLAN.md

- **No pull-to-refresh on Contacts/Bubbles:** PLAN.md § 6 didn't mandate it, but `RainbowSession` had `refreshAll` wired to a `RefreshIndicator`. Manual refresh would need `use.refreshableFuture` and a signature change on `rosterCapsule` / `bubblesCapsule`. Deferred — auth-transition-triggered load covers the acceptance walkthrough. Adding a refresh action later is one small edit per capsule.
- **`isMine` derivation moved into the capsule:** PLAN.md § 6 implied it stays in the send-path only. In practice, incoming carbons need it too, so `messagesCapsule` now computes `isMine` per message using `authCapsule.me?.id` as ground truth.
- **`chatActionsCapsule` was not in the original file list:** Added because `messagesCapsule` alone is read-only. Instead of pushing send-plumbing into `messagesCapsule`, the actions bag centralises all UI mutations that don't cleanly fit a per-thread capsule (setPresence, createBubble, joinMuc).
- **`presenceCapsule` merge in `ContactsTab`:** the roster carries a stale presence snapshot from the REST payload; the live presence map is merged over it in the tab by matching `bareJid`'s local-part against the roster user id.

## API confirmations (recorded for Phase D+)

- **`RearchConsumer` subclasses** need `import 'package:rearch/rearch.dart';` when they call `use.state` / `use.effect` / `use.memo` / `use.data` — those extensions live in the base rearch package, not in `flutter_rearch`.
- **`WidgetHandle` extends `CapsuleHandle`**, so `use(otherCapsule)` and `use.textEditingController(...)` both work in `build(context, use)`.
- **Pattern-matching on `AsyncValue<T>`** — `switch (value) { AsyncLoading<T>() => ..., AsyncData<T>(data: final d) when d.isEmpty => ..., AsyncData<T>(data: final d) => ..., AsyncError<T>(:final error) => ... }`. The `data:` destructure name matches the generated getter.
- **Family capsules with global cache**: safe because there's one `CapsuleContainer` per app; tests use `MockableContainer` + `resetMessagesCapsuleCache()` in `setUp`.

## Next phase pointer

Phase D — Adopt `flutter_chat_ui` for 1:1 chat. That's a `Chat(...)` widget wrapping the messages list. The adapter from `ChatMessage` → `flutter_chat_core.Message` is the interesting bit. Start with `ChatPage`; `BubbleChatPage` follows in Phase E.
