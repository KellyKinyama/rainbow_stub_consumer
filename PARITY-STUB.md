# Parity plan — chatstub-server wire features

Goal: keep `chatstub_consumer` at parity with the server's XMPP wire
surface as the [chatstub-server parity work](../../dart/chatstub-server/PARITY-XMPP-WEB.md)
lands new XEPs. This tracks which server features the client consumes,
how, and what's left.

- **Estimate legend:** S ≈ under a day · M ≈ 1–3 days
- **Status legend:** ✅ done · 🟡 covered via REST · ⬜ open · ➖ N/A

Branch: **`feat/stub-parity`**. Last updated: **2026-09-15**.

---

## 0. Coverage matrix (client vs. server features)

| Server feature (XEP) | Client coverage today | Status |
|---|---|---|
| SASL ANONYMOUS guest (A1) | Registered-login only; guest is an xmpp-web mode | ➖ |
| vcard-temp (A2) | Profile + avatar over **REST**; stub bridges vCard↔avatar | 🟡 |
| HTTP upload `http:upload:0` (A3) | File send over **REST** multipart (`<file xmlns=urn:rainbow:file:1>`) | 🟡 |
| Bookmarks `storage:bookmarks` (B1) | Bubble list persisted **server-side** via REST | 🟡 |
| MUC `muc#owner` + room create (B2) | Create/configure/rename rooms over **REST** | 🟡 |
| **Message moderation `message-moderate:0` (C1)** | **Parse tombstone + owner "Remove" action** | ✅ |
| stanza-id `sid:0` + no-store `hints` (C2) | Dedup on origin `id`; stub keeps `id == stanza-id` | ⬜ (no-op) |

**Reading it:** the 🟡 rows are *functionally covered* — the client already
does these over REST, so re-implementing them over XMPP is redundant, not
parity. Only pursue them if we want to exercise the stub's XMPP path
specifically. The one real gap was C1 (moderation), now closed.

---

## 1. Done

### C1 · XEP-0425 moderation — ✅ (`7d46ce1`)

- Parse `<apply-to xmlns=urn:xmpp:fasten:0><moderated xmlns=message-moderate:0>`
  tombstones → `XmppModeration` event
  ([xmpp_client.dart](lib/rainbow/xmpp_client.dart)).
- Render an in-place "removed by a moderator" tombstone
  ([messages_capsule.dart](lib/state/capsules/messages_capsule.dart)
  `_applyModeration`).
- Owner-only **"Remove (moderator)"** action in the group message sheet
  ([bubble_chat_page.dart](lib/ui/bubble_chat_page.dart),
  [chat_widgets.dart](lib/ui/chat_widgets.dart)); `sendModeration` /
  `moderateGroup` mirror the retract path.
- Tests: [phase_o_moderation_test.dart](test/phase_o_moderation_test.dart)
  (3 cases, green).

### Borrow · XEP-0393 message styling + links — ✅ (`4d…`)

- Bold/italic/strike/inline-code + auto-linked http(s)/mailto URLs in the
  message bubble, ported from xmpp-web's `Message.vue` grammar. Pure
  client, wire-compatible (the stub forwards `<body>` opaquely).
- New [message_styling.dart](lib/ui/message_styling.dart) (testable
  `parseMessageStyle` + `StyledMessageText` widget); wired into
  `PhoneTextBubble` ([chat_widgets.dart](lib/ui/chat_widgets.dart)).
  Boundary/whitespace guards keep `my_file_name` and `a * b` literal.
  Tombstones render muted italic. Tests:
  [message_styling_test.dart](test/message_styling_test.dart) (8 cases).

### P1 · Housekeeping: fix stale test fakes — ✅

- `test/phase_e_bubble_chat_test.dart`'s `_FakeXmpp.sendGroupChat` now
  carries `thread`/`subject` to match the real signature; the file loads
  and passes (5/5). The suite has no remaining load failures.

---

## 2. Remaining — optional, low priority

### P2 · XEP-0359 stanza-id consumption (S) — ⬜

- **What:** Read `<stanza-id xmlns=urn:xmpp:sid:0 id by>` in the incoming
  message parser and prefer it as the canonical id (fallback to origin
  `id`); honor XEP-0334 `<no-store>` locally if we ever add client-side
  persistence.
- **Where:** [xmpp_client.dart](lib/rainbow/xmpp_client.dart) `_handleMessage`
  (`XmppChatMessage` construction) + `_handleMamResult`.
- **Acceptance:** an incoming message with a differing `<stanza-id>` dedupes
  on the server id.
- **Value:** **currently a no-op** — the stub sets `id == stanza-id`, so this
  only matters if the server ever assigns a distinct archive id. Do it for
  forward-compat, not behavior.

### P3 · vcard-temp over XMPP (M) — ⬜

- **What:** Fetch/publish `<vCard xmlns=vcard-temp>` for profile + avatar
  instead of REST. The stub bridges vCard PHOTO ↔ avatar store, so both
  already stay in sync.
- **Where:** new client method + [profile_edit_page.dart](lib/ui/profile_edit_page.dart).
- **Value:** low — REST already round-trips FN/nick/avatar. Only for
  exercising the stub's XMPP vCard path.

### P4 · XEP-0363 upload + `muc#owner` config over XMPP (M each) — ⬜

- **What:** Optionally move file upload to XEP-0363 slots and room config to
  `muc#owner` data forms, matching what xmpp-web drives.
- **Value:** low — REST covers both. Only if we want a single (XMPP) path or
  to drop the REST file/room endpoints.

---

## 3. Recommendation

The parity-critical gap (moderation) is closed. Of what's left, only **P1
(fix the stale `phase_e` fake)** is clearly worth doing — it's a real broken
test unrelated to any XEP. **P2–P4 are no-ops or REST-redundant**; pursue
them only if we deliberately want to shift a feature onto its XMPP path.
