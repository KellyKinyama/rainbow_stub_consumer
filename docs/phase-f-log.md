# Phase F session log — receipts, chat markers, typing indicators

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase F — outbound delivery-receipt request + read-marker request, inbound receipt/marker → `Message.deliveredAt` / `seenAt`, chat-state (`<composing/>` / `<paused/>`) round-trip driving `IsTypingIndicator` in the 1:1 chat page.

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Inspect flutter_chat_core status API | `TextMessage` has `sentAt`, `deliveredAt`, `seenAt`, `failedAt`, `editedAt` timestamps; the `resolvedStatus` getter derives `MessageStatus.sending → sent → delivered → seen → error` from them. `InMemoryChatController.updateMessage(old, new)` matches by id and emits an update op — perfect for status upgrades. `TextMessage` has freezed-generated `copyWith`. |
| 2 | Inspect flutter_chat_ui typing hook | `Chat` widget doesn't wire the composer's text-change events. `IsTypingIndicator` is a standalone widget you place yourself. `Chat.builders.composerBuilder` lets us substitute `Composer(textEditingController: myController)` so we can observe input changes for outbound `<composing/>` / `<paused/>`. Send button still triggers `Chat.onMessageSend` because `Composer` reads the callback from provider. |
| 3 | Verify stub XEP support | `session.dart` already forwards message stanzas whose only children are chat-states / receipts / markers (`body == null && (chatState != null \|\| hasReceipt \|\| hasMarker)`) — the stub is a pass-through for these, so wire-up is client-only. |
| 4 | Add `XmppDeliveryReceipt`, `XmppReadMarker`, `XmppChatState` events | All three carry `fromBare`; receipts/markers carry `stanzaId`; chat states carry `state` ("composing" / "paused" / "active" / "inactive" / "gone"). |
| 5 | Extend `RainbowXmppClient.sendChat` | Body stanza now includes `<request xmlns="urn:xmpp:receipts"/>` and `<markable xmlns="urn:xmpp:chat-markers:0"/>`. `sendGroupChat` unchanged — receipts/markers don't apply to MUC per spec. |
| 6 | Add three new send methods | `sendDeliveryReceipt(toBareJid, stanzaId)`, `sendReadMarker(toBareJid, stanzaId)`, `sendChatState(toBareJid, state)` — each writes one `<message>` stanza with the appropriate child element. |
| 7 | Extend `_handleMessage` parser | Detect `<received>` (XEP-0184 `urn:xmpp:receipts` OR XEP-0333 `urn:xmpp:chat-markers:0`) → `XmppDeliveryReceipt`. Detect `<displayed>` (XEP-0333) → `XmppReadMarker`. Detect any child in `http://jabber.org/protocol/chatstates` → `XmppChatState`. Chat-state and body can coexist on the same stanza — we emit both if present. |
| 8 | Extend `chatControllerCapsule` effect | Two new subscriptions: `XmppDeliveryReceipt` where `fromBare == threadKey` → `_stampStatus(delivered: true)`; `XmppReadMarker` where `fromBare == threadKey` → `_stampStatus(seen: true)`. Both include the generation guard from Phase E. |
| 9 | Auto-send receipt + marker on inbound 1:1 message | In the `XmppChatMessage` listener, after inserting the message, if the message isn't ours AND the thread is 1:1 AND the stanza id is non-empty, fire `xmpp.sendDeliveryReceipt` + `xmpp.sendReadMarker` to the peer. Documented as "aggressive" — no visibility gating. |
| 10 | Add `_stampStatus` helper | Looks up the message by id in the controller, calls `TextMessage.copyWith(deliveredAt:, seenAt:)` with preservation of existing timestamps, then `controller.updateMessage(old, new)`. No-op on unknown ids or when the new state is identical to the old. |
| 11 | Seed `sentAt` on my outbound messages | `_toChatUiMessage` now sets `sentAt: cm.isMine ? cm.sentAt : null`. Without this the resolved status would stay at `sending` forever, since our stub doesn't emit a separate "sent" confirmation. |
| 12 | Add `typingCapsule(threadKey) → Capsule<bool>` | Reduces `XmppChatState` events for the given peer into a bool. `composing` → true + 6 s auto-clear timer; `paused` / `active` / `inactive` / `gone` → false. Generation-guarded. |
| 13 | Extend `chatActionsCapsule` with `sendChatState(peer, state)` | Thin dispatcher onto `xmpp.sendChatState(toBareJid: peer JID, state: state)`. |
| 14 | Rewrite `ChatPage` for outbound typing + inbound indicator | `use.textEditingController()` for our own composer; `use.effect` adds a listener that debounces `<composing/>` (once every 3 s while typing) and fires `<paused/>` after 3 s idle. `Chat.builders.composerBuilder` substitutes `Composer(textEditingController: input)` so the input is ours. Above the `Chat` widget, a small row with `IsTypingIndicator` + "$peer is typing…" text appears when `typingCapsule` is true. |
| 15 | Clear `_typingCache` on `resetMessagesCapsuleCache()` | Otherwise stale typing indicators would survive signout. |
| 16 | Add `test/phase_f_receipts_test.dart` | 6 tests: (a) inbound 1:1 message triggers auto-send of receipt + marker; (b) `XmppDeliveryReceipt` stamps `deliveredAt`; (c) `XmppReadMarker` stamps `seenAt`; (d) `typingCapsule` flips true on composing and back on paused; (e) `typingCapsule` filters by peer (composing from a different JID is ignored); (f) `chatActionsCapsule.sendChatState` dispatches correctly. |
| 17 | `flutter analyze --no-pub` | 0 errors, 0 warnings on new/rewritten files. |
| 18 | `flutter test --exclude-tags=live` | **33/33** pass. Phases B/C/D/E suites all still green. |
| 19 | `flutter build windows --debug` | Clean build in ~16s. |
| 20 | PLAN.md § 6 Phase F → ✅ | Evidence + deviations. |

## Deviations from PLAN.md

- **Not using `Chat.typingIndicatorOptions`:** The `Chat` widget doesn't expose that parameter in this version (2.11.1). Placed `IsTypingIndicator` in a `Column` above the `Chat` widget — same UX, simpler wiring. Behind the scenes we still have a clean `typingCapsule(threadKey)` for anyone who wants to render differently.
- **Read markers are "aggressive":** The plan implied gating `<displayed/>` on visibility. We send it whenever a 1:1 message arrives while the capsule is alive. In our app the capsule stays alive after the chat page is popped (rearch keeps non-idempotent capsules), so this could report "read" for a message the user didn't actually see. Two escape hatches for a future phase: (a) tie the capsule's lifetime to the ChatPage widget lifetime via a per-thread ref-count, or (b) queue candidate `<displayed/>` sends and flush from `ChatPage`'s `use.effect` mount hook.
- **1:1 only:** Typing and read markers aren't wired in `BubbleChatPage`. Group typing needs per-nick state and richer UI; deferred to Phase E+/F+ follow-up.
- **No `sending` state indicator:** we skip straight from local echo to `sent` (via `sentAt = cm.sentAt` at echo time). Adding a true `sending → sent` transition needs a positive ack from the stub (e.g. an `<iq>` result). The current stub doesn't emit one; adding it is small but out of scope here.

## API confirmations (recorded for Phase G+)

- `TextMessage.copyWith` returns a new `TextMessage` with the updated fields — freezed magic. Preserves the union tag correctly.
- `InMemoryChatController.updateMessage(old, new)` matches by `Message.id`; a no-op update (equal object) is not emitted, so idempotent status upgrades are cheap.
- `Composer` widget reads `OnMessageSendCallback` from provider — so `builders.composerBuilder` returning `Composer(textEditingController: input)` still triggers our `Chat.onMessageSend` closure. Clean composition.
- `XEP-0333 <received>` overlaps with XEP-0184 `<received>` on the localName but the xmlns differs. We accept both and emit the same `XmppDeliveryReceipt` event.

## Next phase pointer

Phase G — attachments UI. Uploads via the stub's file endpoint, XMPP payload with a `<file>` extension, receive-side renders `ImageMessage` / `FileMessage`. Adds `Chat.onAttachmentTap`.
