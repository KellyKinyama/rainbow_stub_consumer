# Phase G session log — attachments UI (upload, wire, render)

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase G — cross-platform file picker → REST upload → XMPP `<file>` payload → send-echo as `Message.image` / `Message.file` → inline preview via authed image loader. Applies to both `ChatPage` (1:1) and `BubbleChatPage` (MUC).

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Inspect stub file endpoints | `POST /api/rainbow/fileServer/v1.0/files` (create descriptor JSON) → `PUT /files/{id}/data` (upload bytes) → returns updated descriptor with `downloadUrl`. Download is bearer-authed via `GET /files/{id}/data`. |
| 2 | Verify stanza-child pass-through in the stub | `_rewriteFrom` uses `el.copy()` — every child of `<message>` survives fan-out. So a custom `<file xmlns="urn:rainbow:file:1" .../>` child arrives at the recipient intact. |
| 3 | Inspect flutter_chat_core factories | `Message.image(source: String, size:, text:)` — no direct MIME field. `Message.file(source, name, mimeType, size)` for non-images. Both have the full timestamp timeline (sentAt/deliveredAt/seenAt) so status upgrades still work. |
| 4 | Inspect flutter_chat_core builders | `ImageMessageBuilder = Widget Function(BuildContext, ImageMessage, int index, {required bool isSentByMe, MessageGroupStatus? groupStatus})`. Passed to `Chat.builders: Builders(imageMessageBuilder: ...)`. Chat also has `Chat.onAttachmentTap` (a `VoidCallback`). |
| 5 | Add `file_picker ^8.1.0` to pubspec | Cross-platform: Windows/macOS/Linux/Android/iOS/Web. |
| 6 | Extend `RainbowRestClient` | New `uploadFile({bytes, fileName, mimeType, peerJid, peerType})` — POSTs the descriptor, extracts `id`, PUTs the bytes with the correct content-type, returns `FileDescriptor` from the second response. New `downloadFileBytes(url)` fetches bearer-authed bytes for the inline preview. |
| 7 | Add `FileDescriptor` model + attach to `ChatMessage` | `ChatMessage` gains an optional `attachment: FileDescriptor?`. Local echo carries the descriptor without another network round-trip. |
| 8 | Extend `RainbowXmppClient` for the `<file>` extension | New `XmppAttachment(id, url, fileName, mimeType, size)` value type. `XmppChatMessage` and `XmppMamMessage` grew an optional `attachment` field. `sendChat` / `sendGroupChat` accept an optional `attachment` param and serialize `<file xmlns="urn:rainbow:file:1" id="..." url="..." name="..." mime="..." size="..."/>` between the body and the receipt request. Parser scans children of `<message>` for a `<file>` element in that namespace. |
| 9 | Add `chatActionsCapsule.sendPeerFile` / `sendGroupFile` | Upload → build `XmppAttachment` → send XMPP with body `"[File: name]"` + attachment child → local-echo the `ChatMessage` with `attachment: desc`. |
| 10 | Update both `chatControllerCapsule` listeners | Pass `attachment: _fromXmpp(e.attachment)` into the `ChatMessage` constructor for both live and MAM paths. |
| 11 | Refactor `_toChatUiMessage` | Switches on `cm.attachment`: null → `Message.text`; image mime → `Message.image(source: url, size, text: body)`; other → `Message.file(source, name, mimeType, size)`. Retains the `sentAt: cm.isMine ? cm.sentAt : null` seeding from Phase F. |
| 12 | Refactor `_stampStatus` | Was `whereType<TextMessage>()` — updated to handle all three concrete types (`TextMessage` / `ImageMessage` / `FileMessage`) via a switch expression, so delivery + read markers upgrade the status of image and file messages too. |
| 13 | New `lib/ui/attachment_picker.dart` | `showAttachmentPicker(context) → PickedAttachment?` opens a bottom-sheet with Image / File tiles and dispatches to `FilePicker.platform.pickFiles(type: image \|\| any, withData: true)`. `_guessMime` fills gaps left by `file_picker` when a MIME isn't reported. `AuthedImage(url)` is a `RearchConsumer` that reads `restCapsule`, memoizes `downloadFileBytes(url)`, and paints via `Image.memory`. `InlineImageBubble` is the rounded-corner send-side wrapper. |
| 14 | Wire attachments into `ChatPage` | `Chat.onAttachmentTap` → `showAttachmentPicker` → `actions.sendPeerFile(peer, bytes, fileName, mimeType)`. `Chat.builders.imageMessageBuilder` renders `InlineImageBubble` so bearer-authed images actually load. |
| 15 | Wire attachments into `BubbleChatPage` | Same pattern with `actions.sendGroupFile(bubble, ...)`. Custom image builder shared. |
| 16 | Fix test-fake overrides | Every `_FakeXmpp.sendChat` / `_FakeXmpp.sendGroupChat` in phases C/D/E/F needed the new `XmppAttachment? attachment` parameter to satisfy the base signature. |
| 17 | Write `test/phase_g_attachments_test.dart` | 3 tests: (a) `sendPeerFile` calls REST upload with the right peer/name/mime, then sends XMPP with `attachment.url == uploaded URL`; local echo becomes a `FileMessage`. (b) an image mime path produces `Message.image` locally. (c) an incoming XMPP `<file>` (image mime) surfaces as `ImageMessage` with the sender's local-part as authorId. |
| 18 | `flutter analyze --no-pub` | 0 errors, 0 warnings on new files. |
| 19 | `flutter test --exclude-tags=live` | **36/36** pass. All prior phase suites still green. |
| 20 | `flutter build windows --debug` | Clean build in ~17s. |
| 21 | PLAN.md § 6 Phase G → ✅ | Evidence + deviations. |

## Deviations from PLAN.md

- **Custom `<file>` namespace instead of XEP-0447 (SIMS):** SIMS is heavyweight and requires a stanza content model with `<reference>` + `<sims>` + `<sources>`. Our custom `urn:rainbow:file:1` element is a single line, matches the demo stub's expectations, and is trivially portable to SIMS later if needed.
- **Bearer-authed inline previews via a custom image builder** — the plan implied `Message.image(source: url)` alone would render. The stub's file endpoint requires `Authorization: Bearer …` on GETs. Rather than expose an unauthenticated download or plumb tokens into a URL query string, `AuthedImage` uses the existing `restCapsule` bearer, `downloadFileBytes(url)`, and `Image.memory`. Cleaner separation and no token leakage into the wire.
- **No camera / gallery split:** the plan mentions "camera / gallery / file" but the picker sheet has just Image / File. Camera capture on Windows debug needs `image_picker` which is mobile-only in practice; deferred.
- **No upload progress indicator:** `RainbowRestClient.uploadFile` awaits the PUT synchronously. `http` package doesn't emit progress for `put`. Follow-up phase can swap to a chunked/streaming transport.

## API confirmations

- `Chat.onAttachmentTap` is a `VoidCallback` — no context/args. Popping a modal from within it works because we capture the enclosing `BuildContext` in the closure.
- `TextMessage`, `ImageMessage`, `FileMessage` all have freezed-generated `copyWith` — `_stampStatus` can uniformly upgrade status timestamps across variants.
- `file_picker`'s `pickFiles(withData: true)` fills `PlatformFile.bytes` on Windows/desktop; on mobile it doesn't for large files (a caveat for Phase H+ mobile support).

## Next phase pointer

Phase H — message reactions + edits + replies. `Message.reactions: Map<String, List<UserID>>?` already exists on every variant; long-press → context menu → `controller.updateMessage(...)` with a new reactions map. Replies use `replyToMessageId` on the message itself.
