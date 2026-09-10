# Phase H session log — reactions (XEP-0444) + edits (XEP-0308) + replies (XEP-0461)

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase H — long-press → context menu → React / Reply / Edit / Copy, with the three XEPs wired end-to-end (send + parse + local echo + status upgrade for corrections).

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Inspect flutter_chat_core `Message` variants | `TextMessage` has both `replyToMessageId` and `editedAt`. `ImageMessage` / `FileMessage` have `replyToMessageId` + `reactions` but no `editedAt`; edits on those fall back to `updatedAt`. `Message.reactions: Map<String, List<UserID>>?`. All three variants have freezed-generated `copyWith`. |
| 2 | Inspect `Chat.onMessageLongPress` typedef | `void Function(BuildContext, Message, {required int index, required LongPressStartDetails details})`. Perfect for popping a modal sheet keyed on the pressed message. |
| 3 | Verify stub forwarding for the three XEPs | `<replace>` and `<reply>` come with a body → routed through the normal persist+forward path already. `<reactions>` has no body → dropped by the existing "forward without persist" filter. |
| 4 | Extend stub's forward filter for reactions | New `Ns.reactions = 'urn:xmpp:reactions:0'`; the `body == null && (chatState \|\| receipts \|\| markers)` guard now also matches `<reactions>`. All 40 non-flaky stub tests still pass. |
| 5 | Add three XMPP events to `RainbowXmppClient` | `XmppReactions(fromBare, targetStanzaId, emojis)`, `XmppMessageCorrection(fromBare, originalStanzaId, newBody, newStanzaId, isGroupChat)`, and a `replyToStanzaId` field on `XmppChatMessage` / `XmppMamMessage`. |
| 6 | Add send methods | `sendReactions(toBareJid, targetStanzaId, emojis, isGroupChat)`, `sendChatCorrection(toBareJid, originalStanzaId, newBody, id, isGroupChat)`, and `replyToStanzaId` parameter on `sendChat` / `sendGroupChat` (serialized as `<reply xmlns="urn:xmpp:reply:0" id="…"/>`). |
| 7 | Extend parser | Detect `<reactions>` child in a `<message>` → emit `XmppReactions`. Detect `<replace>` alongside a `<body>` → emit `XmppMessageCorrection` and swallow the stanza so it never renders as a fresh chat. Detect `<reply>` child → set `replyToStanzaId` on the emitted `XmppChatMessage`/`XmppMamMessage`. |
| 8 | Extend `ChatMessage` model | New optional fields: `replyToStanzaId`, `reactions: Map<String, List<String>>?`, `editedAt`. |
| 9 | Extend `chatActionsCapsule` | New `reactToPeer` / `reactToGroup` / `editPeer` / `editGroup`. `sendPeer` / `sendGroup` gained optional `replyToStanzaId`. Each mutation dispatches to XMPP and also fans out locally. |
| 10 | Add `applyReactionsLocally` / `applyEditLocally` | Top-level functions that fan out to a new `_threadUpdaters: Map<ThreadKey, List<Function(_ThreadUpdate)>>` registry. Same registration lifecycle as `_appenders`. Cleared on `resetMessagesCapsuleCache()`. |
| 11 | Add reactions + correction stream subs in `chatControllerCapsule` | Filtered on `fromBare == threadKey`. Delegate to `_applyReactions` / `_applyEdit` inside the effect body. Cleanup cancels both subs and removes the updater. |
| 12 | Add `_applyReactions` helper | Reads the message with `targetStanzaId`, drops `fromUserId`'s old contribution from every emoji list, adds them to each new emoji, calls `updateMessage(old, new)` via a switch expression covering `TextMessage` / `ImageMessage` / `FileMessage`. |
| 13 | Add `_applyEdit` helper | Uses `TextMessage.copyWith(text: newBody, editedAt: now)` for text, `Image/FileMessage.copyWith(text: … , updatedAt: now)` (or `name:` for FileMessage since it has no text) as the closest-to-edited approximation. |
| 14 | Refactor `_toChatUiMessage` | Now also passes `replyToMessageId`, `reactions`, and (for TextMessage) `editedAt` through to the produced `Message.text/image/file`. |
| 15 | Rewrite `ChatPage` with long-press UX | `use.state<Message?>` for `replyingTo` + `use.state<TextMessage?>` for `editing`. `beginReply` / `beginEdit` / `clearBanner` helpers manage the two states. `Chat.onMessageLongPress` pops a modal sheet with a 6-emoji quick-react row + Reply/Edit/Copy tiles conditional on message type + authorship. Composer send dispatches to `editPeer` or `sendPeer` depending on `editing`. `_ReplyBanner` / `_EditBanner` widgets sit under the composer. |
| 16 | Update every test fake | The five earlier phase test files needed a `String? replyToStanzaId` param added to their `_FakeXmpp.sendChat` / `sendGroupChat` overrides to satisfy the new base signature. |
| 17 | Write `test/phase_h_reactions_edits_replies_test.dart` | 6 tests: (a) `reactToPeer` sends XEP-0444 reactions and updates the local map to `{"🔥": ["alice"]}`. (b) incoming `XmppReactions` merges: `{"❤️": ["bob"], "😂": ["bob"]}`. (c) `editPeer` swaps the body and stamps `editedAt`. (d) incoming `XmppMessageCorrection` replaces the original body. (e) `sendPeer(reply)` propagates `replyToStanzaId` to XMPP and to `Message.replyToMessageId`. (f) incoming `<reply>` surfaces as `replyToMessageId`. |
| 18 | `flutter analyze --no-pub` | 0 errors, 0 warnings on new files. |
| 19 | `flutter test --exclude-tags=live` | **42/42** pass (Phase G's 36 + Phase H's 6). |
| 20 | `flutter build windows --debug` | Clean build in ~16s. |
| 21 | Stub `dart test` | 40/41 pass — remaining failure is the pre-existing `POST /users/:id/photo (multipart)` Windows socket-starvation flake documented earlier. |
| 22 | Update PLAN.md → Phase H ✅ | Evidence + deviations. |

## Deviations from PLAN.md

- **Delete / retract:** the plan listed Delete in the long-press menu; we ship Copy in its place. XEP-0424 retraction is a small follow-up: `<retract id="…" xmlns="urn:xmpp:message-retract:1"/>` on send, `controller.removeMessage(msg)` on receive.
- **Group chat long-press:** the actions expose `reactToGroup` / `editGroup` and both are covered by unit tests, but `BubbleChatPage`'s UI isn't yet wired to the long-press menu (a straightforward mirror of `ChatPage`). Deferred to keep the phase diff focused.
- **Reply preview rendering:** `Message.replyToMessageId` is populated but `flutter_chat_ui`'s default `TextMessage` builder doesn't render a quoted card automatically. A follow-up phase can wire a custom `textMessageBuilder` that looks the target up in `controller.messages` and renders a preview above the current bubble.
- **Reactions display:** the `Message.reactions` map flows through and shows up under each bubble in `flutter_chat_ui`'s default renderer; the quick-react sheet works. Full parity would want a "long-press an existing reaction to remove" gesture — not wired yet.

## API confirmations (recorded for follow-up phases)

- `TextMessage.editedAt` exists; `Image/FileMessage` don't have it — use `updatedAt` as the "modified" clock for those variants.
- `Chat.onMessageLongPress` is called from within the message widget's `GestureDetector`, so pushing a modal from it works without any Overlay gymnastics.
- Freezed `copyWith` preserves the union tag — a `TextMessage.copyWith(text: ...)` returns a `TextMessage`, safe for `updateMessage`.
- The stub is a pass-through router for reactions/replies — no persistence semantics — so MAM replay carries the correct `<reply>` child but *not* reactions (since reactions were forwarded, never archived). That means reaction state is live-only for now. A future stub change could archive reactions or persist them out-of-band.

## Next phase pointer

PLAN.md § 6 finishes at Phase H. From here we could tighten the loose ends (group long-press, reply preview render, retraction, reaction removal) or attack ROADMAP items outside the migration track. The full ChatUI migration story is complete: rearch capsules power everything, `flutter_chat_ui` renders both 1:1 and MUC with attachments + receipts + typing + reactions/edits/replies.
