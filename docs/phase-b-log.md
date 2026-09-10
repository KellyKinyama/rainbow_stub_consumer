# Phase B session log — port state to rearch capsules

**Date:** 2026-09-10  
**Branch:** `feat/chat-ui-rearch`  
**Scope:** PLAN.md § 6 Phase B — introduce capsule graph alongside the existing `RainbowSession` provider (no UI cutover; that's Phase C).

## Actions

| # | Action | Notes |
|---|---|---|
| 1 | Inspect rearch v1.16.1 sources at `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\rearch-1.16.1\lib\src\` | Confirmed real API: `use.state`, `use.data`, `use.callonce`, `use.memo`, `use.effect`, `use.disposable`, `use.reducer`, `use.stream`, `use.future`, `use.rebuilder`. Container = `CapsuleContainer`; tests use `MockableContainer.mock(cap).apply(replacement)`. |
| 2 | Design capsule graph on paper | Config → REST/XMPP (disposable) → AuthState slot (data) → AuthController + Roster + Bubbles + Presence + Messages(threadKey). Messages is a family capsule cached by key. |
| 3 | Create `lib/state/models/auth_state.dart` | Sealed `AuthState` with `SignedOut` / `SignedIn({me, token})`. |
| 4 | Create `lib/state/models/presence.dart` | Value type with `show` + optional `status`. |
| 5 | Create `lib/state/capsules/config_capsule.dart` | Trivial — returns `AppConfig.dev`. Deps for downstream. |
| 6 | Create `lib/state/capsules/rest_capsule.dart` | `use.disposable(() => RainbowRestClient(config), (c) => c.close(), [config])`. |
| 7 | Create `lib/state/capsules/xmpp_capsule.dart` | Two capsules: `xmppCapsule` (disposable client) + `xmppEventsCapsule` (broadcast stream). |
| 8 | Create `lib/state/capsules/auth_state_capsule.dart` | Uses `use.data<AuthState>` for a shared mutable slot. Exposes both the `ValueWrapper` and a plain `authCapsule` value getter. |
| 9 | Create `lib/state/capsules/auth_controller_capsule.dart` | `AuthController` with `signIn` (REST login → setBearer → XMPP connect → slot flip) and `signOut` (best-effort teardown). |
| 10 | Create `lib/state/capsules/roster_capsule.dart` | `use.memo` builds a `Future<List<RosterEntry>>` conditional on `auth.isSignedIn`; `use.future` subscribes → `AsyncValue`. |
| 11 | Create `lib/state/capsules/bubbles_capsule.dart` | Same pattern as roster, for `RainbowBubble`. |
| 12 | Create `lib/state/capsules/presence_capsule.dart` | `use.effect` subscribes to `XmppPresenceUpdate` events and mutates a `ValueWrapper<Map<String, Presence>>`. |
| 13 | Create `lib/state/capsules/messages_capsule.dart` | Family: `messagesCapsule(threadKey)` returns a cached `Capsule<List<ChatMessage>>` — cache is keyed on `threadKey` so identity is preserved across reads. `_belongsToThread` matches on `from` OR `to` bare JID. Test-only `resetMessagesCapsuleCache()` for isolation. |
| 14 | Create `test/capsules_test.dart` | 6 acceptance tests using `MockableContainer` + `FakeRestClient` + `FakeXmppClient` (both extend the concrete client so they satisfy the capsule return type). Covers: signed-out → signed-in transition, sign-out reverses, roster populates, bubbles populates, presence accumulates on stream, messages appends only for matching thread. |
| 15 | `flutter analyze --no-pub` | 0 errors, 0 warnings on new files. 7 pre-existing `info` lints in files not touched (`rest_client.dart`, `xmpp_client.dart`, `live_stub_integration_test.dart`). |
| 16 | `flutter test --exclude-tags=live` | 6/6 new capsule tests pass. All 7 pre-existing tests still pass. Live tests skip cleanly with the stub down. |
| 17 | Update PLAN.md § 6 Phase B → ✅ done 2026-09-10 | Also expanded the file list (auth split into state + controller). |

## Deviations from PLAN.md

- **Auth split:** PLAN.md § 6 listed a single `auth_capsule.dart`. Split into `auth_state_capsule.dart` (data slot) + `auth_controller_capsule.dart` (orchestrator) because the controller depends on both the slot and REST/XMPP; keeping them separate avoids re-entrancy and makes the slot cheap to read from other capsules.
- **`xmppEventsCapsule` co-located:** Merged into `xmpp_capsule.dart` rather than its own file — it's a two-line derived getter and doesn't justify a separate file.
- **Message hydration deferred:** PLAN.md § 6 said "hydrates on demand". Deferred to Phase D because REST doesn't yet expose a `messages(threadKey)` endpoint; MAM-over-XMPP is available but plumbing it through the capsule needs a `MessageArchiveQuery` type. Live-append works today.

## API confirmations

Recorded here for future phases:

- `Capsule<T> = T Function(CapsuleHandle)`; `CapsuleHandle` implements both `CapsuleReader` (`use(otherCapsule)`) and `SideEffectRegistrar` (`use.state(...)`).
- `use.disposable<T>(init, dispose, [deps])` is the idiomatic way to hold a resource across rebuilds. Deps drive recreation.
- `use.data<T>(initial)` returns a `ValueWrapper<T>` — settable from anywhere; use it for shared mutable state that outlives a single build.
- `use.future` / `use.stream` return `AsyncValue<T>` = `AsyncLoading | AsyncData | AsyncError`. Use the `is AsyncData<T>` pattern-match check.
- `MockableContainer.mock(cap).apply(replacement)` MUST be called before the capsule is read for the first time — otherwise throws `StateError('capsule already initialized before call to mock()')`.
- Fakes for capsules that return concrete types (e.g. `RainbowRestClient`) must `extends` the concrete class, not implement an interface — the capsule signature nails the exact type.

## Next phase pointer

Phase C (Rewrite screens as `RearchConsumer` widgets, delete `RainbowSession`) — big diff in `lib/app.dart`, `login_page.dart`, `home_page.dart`. Provider is still on the dep list; remove after Phase C tests are green.
