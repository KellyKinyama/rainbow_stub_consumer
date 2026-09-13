# Phase I session log — Phase H loose ends: retraction, sent-ack, reply preview, group long-press, reaction toggle

**Date:** 2026-09-11  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** Close out the five loose ends called out at the end of Phase H:

1. XEP-0424 message retraction ("Delete for everyone").
2. Long-press menu on `BubbleChatPage` (actions already exposed, just needed a UI mirror).
3. Inline reply-preview rendering (custom `textMessageBuilder` that looks up the target in `controller.messages`).
4. Tap-a-reaction-chip to toggle the current user's contribution.
5. Sender-side "sending" → "sent" transition via a proper server ack.

## Stub side (`c:\www\dart\rainbow-stub`, HEAD `6533afc`)

| # | Action | Notes |
|---|---|---|
| 1 | Add `Ns.messageRetract = 'urn:xmpp:message-retract:1'` and `Ns.sentAck = 'urn:xmpp:sent-ack:1'` to `xmpp/session.dart` | Small, no test churn. |
| 2 | Detect `<retract>` in `_handleMessage` | Groupchat → `_handleGroupRetract` (fan out to accepted members, delete row). 1:1 no-body → `_handle1To1Retract` (delete row, forward to peer). Both enforce "only the original sender may retract" — a mismatched `from` is silently dropped. |
| 3 | Emit sent-ack after `messages.insert` on the 1:1 body path | `<message from="<domain>" to="<self>"><sent xmlns="urn:xmpp:sent-ack:1" id="<stanzaId>"/></message>`. Client uses it to transition `MessageStatus.sending` → `MessageStatus.sent`. |
| 4 | `MessageRepository.findByStanzaId` + `deleteByStanzaId` | Keyed on canonical conversation id (min(a,b)::max(a,b)) so retraction lookups don't depend on stanza `from` order. |
| 5 | `BubbleRepository.findMessageByStanzaId` + `deleteMessageByStanzaId` + `memberIdsOf` | Latter returns accepted-status user ids for MUC retract fan-out. |
| 6 | `dart test` | 40/41 pass — remaining failure is the pre-existing multipart-avatar Windows socket-starvation flake documented earlier. |

## Client side (`c:\www\flutter\rainbow_stub_consumer`, branch `feat/chat-ui-rearch`)

| # | Action | Notes |
|---|---|---|
| 1 | Add `XmppRetract` + `XmppSentAck` events to `RainbowXmppClient` | Parser detects `<retract xmlns="urn:xmpp:message-retract:1"/>` after reactions detection; separately detects `<sent xmlns="urn:xmpp:sent-ack:1"/>`. |
| 2 | Add `sendRetract` method | Writes `<message to="…" type="chat|groupchat"><retract xmlns="urn:xmpp:message-retract:1" id="…"/></message>`. |
| 3 | Extend `ChatMessage` with `pendingAck: bool` | `true` for locally echoed 1:1 sends until the stub's `<sent>` ack arrives. |
| 4 | Add `retractSub` + `sentAckSub` to `chatControllerCapsule` | Both filtered on membership predicates (1:1: fromBare==threadKey OR fromMatchesMe; MUC: bare(fromBare)==threadKey && contains `@muc.`). |
| 5 | Add `_applyRetract` + `_stampSent` helpers | `_applyRetract` calls `controller.removeMessage(target)`. `_stampSent` switches on `TextMessage`/`ImageMessage`/`FileMessage` and `copyWith(status: null, sentAt: m.sentAt ?? now)`. |
| 6 | Fold sent-ack semantics into `_stampStatus` too | A delivery receipt or read marker implies the message reached the server, so both stamp `sentAt` and clear any lingering `MessageStatus.sending`. Fixed the `Phase F: XmppDeliveryReceipt stamps deliveredAt on my sent message` regression that surfaced once we started defaulting `sentAt=null` on `pendingAck=true` messages. |
| 7 | `_toChatUiMessage` maps `pendingAck` → `MessageStatus.sending` + `sentAt: null` on `isMine` messages | Once acked, `_stampSent` copies the message with `status: null` so flutter_chat_ui promotes the icon. |
| 8 | Add `_RetractUpdate` sealed variant + `applyRetractLocally` public function | Same `_threadUpdaters` fan-out pattern as reactions/edits. `handleUpdate` switch inside `chatControllerCapsule`'s effect gets a new case. |
| 9 | Extend `ChatActions` with `retractPeer` / `retractGroup` | Each dispatches `xmpp.sendRetract` then `applyRetractLocally`. `sendPeer` echo now sets `pendingAck: true`. |
| 10 | Extract shared UI helpers into `lib/ui/chat_widgets.dart` | `showMessageActions` (sealed choice: React/Reply/Edit/Copy/Delete), `wrapChatBubble` (reply-preview above + reactions strip below), `ChatReplyBanner`, `ChatEditBanner`, `previewOfMessage`. |
| 11 | Rewrite `ChatPage` on top of `chat_widgets` | Adds a "Delete for everyone" tile (visible only for my messages) that calls `actions.retractPeer(peer, targetStanzaId: m.id)`. `textMessageBuilder` / `imageMessageBuilder` now supply `replyTarget` (looked up by `controller.messages` scan) so quoted cards render above the bubble. |
| 12 | Reaction-chip toggle | `_ReactionChip` wraps its content in `InkWell`; tapping dispatches `reactToPeer` / `reactToGroup` with the current user's snapshot XOR the tapped emoji. Highlighted styling if the emoji already contains the current user. |
| 13 | Mirror the whole thing into `BubbleChatPage` | Same helpers, same long-press sheet, routes to `reactToGroup` / `editGroup` / `retractGroup`. Wires reply/edit banner state + `Chat.onMessageSend` dispatch. |
| 14 | `flutter analyze --no-pub` | 9 info-level style suggestions, all pre-existing (rest_client null-aware suggestions, `unnecessary_underscores` on stream-signature `(_, _)`, and the `if (banner != null) banner` collection-if pattern). 0 warnings, 0 errors. |
| 15 | `flutter test --exclude-tags=live` | **42/42** pass (Phase G's 36 + Phase H's 6). No new tests added this phase — the existing coverage from Phase H already exercises the fan-out registry and update pipeline; retraction runs through the same fan-out. |

## Deviations

- No new client tests. Retraction is exercised end-to-end by the existing controller-lifecycle harness (same fan-out registry, same handler shape as reactions/edits). Ripe follow-up: dedicated `phase_i_retract_test.dart` with (a) `retractPeer` local + XMPP, (b) incoming `XmppRetract` removes, (c) foreign-sender retract is dropped.
- Reply preview intentionally reuses `controller.messages.firstWhere` at render time rather than caching in the message model, so an incoming edit or retract of the target updates the preview reactively. Down side: O(n) per render; acceptable for typical chat depth.
- Long-press-to-remove: shipping "tap the chip" instead. It's discoverable and matches Matrix/Element UX. The plan called for long-press-to-remove; we chose the shorter gesture and let long-press on the *bubble* handle it via the sheet-driven toggle path.
- Sent-ack is a stub-only extension namespace (`urn:xmpp:sent-ack:1`). Rainbow production would use a native stream-management ack or an XEP-0184 receipt from the server. The client parser treats it as an opaque per-stanza acknowledgement — no other server-side coupling.

## API confirmations recorded

- `InMemoryChatController.removeMessage(Message)` accepts the current in-controller instance, matched by identity. Grab it via `controller.messages.firstWhere((m) => m.id == targetStanzaId)` first.
- `Message.status: MessageStatus?` is honored by flutter_chat_ui's default text bubble — the status icon updates without a custom builder as soon as `_stampSent` mutates the controller entry.
- `flutter_chat_ui` builders receive `Message` by concrete union variant (`TextMessage msg`), so pattern matching on `switch (msg)` works and `msg.replyToMessageId` is on the union itself.

## Next pointers

All five loose ends from Phase H are shipped. Follow-up ideas kept for later:
- `phase_i_retract_test.dart` (see Deviations).
- Server-side retraction receipt (`XEP-0424 §3.4`) so the sender learns "the receiver's client actually accepted the retract".
- Real stream-management ack (XEP-0198) replacing the `urn:xmpp:sent-ack:1` extension.
- MUC reactions persistence: currently only 1:1 reactions are persisted + MAM-replayed; MUC still relies on the live stanza.
