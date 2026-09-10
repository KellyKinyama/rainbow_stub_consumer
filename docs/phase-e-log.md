# Phase E session log — adopt flutter_chat_ui for group chat

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase E — `BubbleChatPage` migrates to `flutter_chat_ui`'s `Chat` widget. `chatControllerCapsule` gains MUC MAM hydration + correct nick-based author attribution. Cross-user pollution bugs surfaced by the previous test drive get fixed here.

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Enable MUC MAM in `chatControllerCapsule` | Dropped the `!threadKey.contains('@muc.')` guard around `queryMamWith`. The stub's `_handleMamQuery` already routes on the `with` field's domain (`@muc.…` → bubble path). |
| 2 | Fix sender-id extraction for MUC | `_localPart('room@muc.domain/nick')` returned `'room'` — wrong. New `_resourcePart(...)` returns the segment after `/`, i.e. the nick, which our client sets to the sender's user id when joining. |
| 3 | Refactor `_toChatUiMessage` | Was `(cm, myUserId)` and derived authorId internally. Now takes an explicit `authorId` — listeners compute it once (using `senderIdFor(fromJid, isGroupChat:)` which switches between `_resourcePart` and `_localPart`). |
| 4 | Rewrite `bubble_chat_page.dart` | Now a thin `RearchConsumer` wrapping `Chat(currentUserId, resolveUser, chatController, onMessageSend)`. `use.effect` on `bubble.id` fires `actions.joinMuc(bubble)` once per bubble. `resolveUser` looks up display names from `rosterCapsule`; falls back to id-as-name for bubble members not in your roster. |
| 5 | Deep-dive on the earlier `RangeError: index 44 not in 0..15` crash | Traced to cross-capsule pollution: after signout, rearch-container-managed capsules from the previous session stay alive (non-idempotent because of the stream subscription). Their listeners keep processing MAM events for *someone else's* query, driving the stale mamCursor past their own list length. |
| 6 | Add cache-generation guard | New module-level `int _cacheGeneration`. Each closure snapshots it at creation. Every event handler (`append`, `insertOnce`, `liveSub.listen`, `mamSub.listen`) checks `myGeneration == _cacheGeneration` before doing work. `resetMessagesCapsuleCache()` bumps the counter. Result: after signout, old capsules go dormant on the same tick. |
| 7 | Defensive index clamp in `insertOnce` | `if (index > messages.length) index = messages.length`. Turns any out-of-range insert into an append; production code will never `RangeError` from `List.insert` again. |
| 8 | Write `test/phase_e_bubble_chat_test.dart` | 5 tests: (a) MUC MAM query fires with the room JID; (b) incoming groupchat uses the resource part as authorId; (c) local group send-echo attributes authorship to the signed-in user; (d) MAM MUC hydration inserts oldest-first with nick authors; (e) `resetMessagesCapsuleCache` makes stale capsules ignore subsequent events. |
| 9 | `flutter analyze --no-pub` | 0 errors, 0 warnings on new/rewritten files. |
| 10 | `flutter test --exclude-tags=live` | **27/27** pass. Phase-D suite unaffected. |
| 11 | `flutter build windows --debug` | Clean build in ~15s. |
| 12 | Update PLAN.md → Phase E ✅ | Evidence + hardening notes. |

## Deviations from PLAN.md

- **Sender display name via `metadata: {senderNick: …}`:** the PLAN suggested threading nicks through message metadata. Not needed — `Chat.resolveUser` is the intended flutter_chat_ui hook and gives us richer results (name + optional imageSource) without polluting `Message.metadata`.
- **No `initState` for MUC join:** `RearchConsumer` widgets don't have `initState`. Used `use.effect(() => joinMuc(); return null;, [bubble.id])` — same guarantee, cleaner shape.
- **No "joining…" progress indicator:** the raw `Chat` widget shows an empty state until messages arrive; the old placeholder wasn't adding much and it's one less state slot.

## Bugs surfaced by the previous test drive (fixed here)

### Cross-user cache pollution

**Symptom:** After signout + signin as a different user, opening a chat could crash with `RangeError: 44 not in 0..15` at `List.insert` inside `InMemoryChatController.insertMessage`.

**Root cause:** `_controllersCache.clear()` removed the family entry, but the underlying rearch capsule (stored in `CapsuleContainer` by identity) survives. Because it registered a stream subscription in `use.effect`, it's non-idempotent and rearch never GCs it. Its listener kept processing MAM events for later queries, incrementing a stale `mamCursor` past its own controller's list size.

**Fix:** generation counter. Each closure snapshots `_cacheGeneration` at creation; listeners drop events when `myGeneration != _cacheGeneration`. `resetMessagesCapsuleCache()` bumps the counter. Old capsules go dormant without needing rearch-level disposal.

**Belt-and-suspenders:** defensive clamp `min(index, messages.length)` on the MAM insert path.

## API confirmations (recorded for Phase F+)

- `Chat.resolveUser` is called lazily per unique `authorId`; results are cached by the built-in `UserCache`. Roster lookups inside `resolveUser` are cheap even if repeated.
- MUC MAM query format matches 1:1 exactly — same `queryMamWith(peerBareJid)` call with a room JID.
- The stub sets the archived stanza's `from` to `roomJid/nick` (which we use as authorId) and `to` to the room JID.

## Next phase pointer

Phase F — live receipt (XEP-0184) + typing (`<composing/>`) + read markers (XEP-0333) driving `Message.status` and `Chat.typingIndicatorOptions`. First lightweight phase after E.
