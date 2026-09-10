# Phase D session log — adopt flutter_chat_ui for 1:1 chat

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase D — `ChatPage` migrates from hand-rolled bubbles to `flutter_chat_ui`'s `Chat` widget backed by a new `chatControllerCapsule` family.

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Inspect `flutter_chat_core` 2.9.0 | `Chat(currentUserId, resolveUser, chatController, onMessageSend, ...)`. `ChatController` interface with `messages`, `insertMessage`, `operationsStream`; concrete `InMemoryChatController` ships in the package. `Message.text(id, authorId, createdAt, text)` sealed union with `TextMessage` / `ImageMessage` / `FileMessage` / etc. `User(id, name, imageSource)` via freezed. `UserID = String`, `MessageID = String`. |
| 2 | Confirm `flutter_chat_ui` 2.11.1 widget surface | `Chat` is a `StatefulWidget` that wraps `ChatAnimatedList` + `Composer`; `ResolveUserCallback = Future<User?> Function(UserID)`. |
| 3 | Design integration | Two options: (a) diff-sync `List<ChatMessage>` into an ephemeral controller each rebuild, (b) new capsule owning the controller. Chose (b) — cleaner, controller identity stable, no diff logic. |
| 4 | Extend `RainbowXmppClient.sendGroupChat` with an optional `id` param | Symmetric with `sendChat`; needed so actions can pass one stanza id for both wire send and local echo (dedupe). |
| 5 | Rewrite `messages_capsule.dart` | Global `_appenders` map went from `Map<K, Function>` to `Map<K, List<Function>>` — multiple subscribers can register per thread. New `chatControllerCapsule(threadKey)`: `use.disposable(InMemoryChatController.new, (c) => c.dispose(), [threadKey])` for controller lifetime; `use.effect` registers an appender that inserts via `Message.text(...)` and also subscribes to XMPP stream events. |
| 6 | Add `_toChatUiMessage` converter | `TextMessage(id: cm.id, authorId: isMine ? me.id : localPart(from), createdAt: cm.sentAt, text: cm.body)`. Author is set to the peer's user-id local-part for incoming, current user id for local-echo. |
| 7 | Dedup guard on `insertMessage` | `if (controller.messages.any((m) => m.id == m.id)) return;` — `InMemoryChatController` also asserts unique IDs internally, so this prevents a debug-mode throw when the stub carbons back a message we already echoed locally. |
| 8 | Update `chat_actions_capsule.dart` | Both `sendPeer` and `sendGroup` now generate one stanza id (`microsecondsSinceEpoch.toRadixString(16)`), pass it to `xmpp.sendChat(id: ...)` / `sendGroupChat(id: ...)`, and use the same id for `appendLocalMessage(...)`. |
| 9 | Rewrite `chat_page.dart` | Now a `RearchConsumer` that just wires `Chat(currentUserId, resolveUser, chatController, onMessageSend)`. `resolveUser(id)` returns `User(id, name)` — self from `authCapsule.me`, peer from the passed `RainbowUser`, unknown ids fall back to id-as-name. |
| 10 | `flutter analyze --no-pub` | 0 errors, 0 warnings on new files. 8 total infos — 7 pre-existing (untouched files) + 1 stale `_fakeConfig` in `phase_c_actions_test.dart` (deleted). |
| 11 | Clean up `phase_c_actions_test.dart` | Remove dead `_fakeConfig` helper left from the earlier Phase C refactor. |
| 12 | Write `test/phase_d_chat_controller_test.dart` | Four tests: (a) `chatControllerCapsule` renders local echo as `TextMessage` with correct authorId; (b) incoming XMPP `XmppChatMessage` inserts with author = peer local-part; (c) same-stanza-id carbon dedupes against the local echo; (d) `messagesCapsule` and `chatControllerCapsule` for the same thread stay in sync when both are read. |
| 13 | `flutter test --exclude-tags=live` | **18/18** pass. Breakdown: 6 capsule tests + 1 phase-a bootstrap + 1 phase-c action + 4 phase-d + 3 live setup + 3 live. |
| 14 | `flutter build windows --debug` | Clean build in 31.3s → `build\windows\x64\runner\Debug\rainbow_stub_consumer.exe`. |
| 15 | Update PLAN.md → Phase D ✅. | Evidence + deviations. |

## Deviations from PLAN.md

- **`messagesCapsule` kept alive:** the plan implied removing it. Kept because `bubble_chat_page.dart` still consumes it (Phase E migrates it). Both capsules share the `_appenders` registry so state stays consistent.
- **`resolveUser` returns id-as-name for unknown ids:** the plan implied avatar/name via roster lookup. That works for the peer we already hold but not for group members (Phase E). Group name resolution deferred.
- **No avatar images yet:** the stub exposes `/api/rainbow/enduser/v1.0/users/:id/avatar` behind a bearer token; `User.imageSource` is a plain URL that Flutter would fetch un-authed. Wiring the bearer through the image cache is a Phase G-adjacent task.
- **No `chat_view.dart` split:** the plan proposed a separate widget file for the chat body. `chat_page.dart` is already small enough to hold both the Scaffold and the `Chat(...)` call; splitting would add indirection without payoff.

## API confirmations (recorded for Phase E+)

- **`InMemoryChatController.insertMessage(Message)`** is async but returns before the animation completes — subsequent inserts back-to-back are safe.
- **`Message.text(...)` uses `createdAt`** for ordering; `sentAt` / `seenAt` / `deliveredAt` drive the built-in status indicator via `Message.resolvedStatus`. Phase F will populate those.
- **`Chat(onMessageSend:)`** is a `void Function(String text)` — no `Future`. Actions must be fire-and-forget from the widget's perspective.
- **`ResolveUserCallback`** is invoked lazily for each unique `authorId`; results are memoized by `UserCache`.

## Next phase pointer

Phase E — same treatment for `BubbleChatPage`. Needs a MUC-nick resolver (build a `User(id: nick)` from `<message from='room@muc/nick'>`), plus join-on-first-build (already in the current page via `chatActionsCapsule.joinMuc`).
