import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/xmpp_client.dart';
import '../messages_mirror.dart';
import 'auth_state_capsule.dart';
import 'messages_mirror_capsule.dart';
import 'xmpp_capsule.dart';

/// Bare-JID of the peer or bubble whose thread we want to watch. For MUC
/// chats this is the bubble's room JID (e.g. `room-xyz@muc.localhost`);
/// for 1:1 chats it's the peer's bare JID.
typedef ThreadKey = String;

final Map<ThreadKey, Capsule<List<ChatMessage>>> _messagesCache = {};
final Map<ThreadKey, Capsule<InMemoryChatController>> _controllersCache = {};
final Map<ThreadKey, Capsule<bool>> _typingCache = {};

// Per-thread appenders registered by each subscribing capsule's [effect].
// A single call to [appendLocalMessage] fans out to all appenders so that
// the reactive list, the flutter_chat_ui controller, and future observers
// stay in sync.
final Map<ThreadKey, List<void Function(ChatMessage)>> _appenders = {};

/// Per-thread updater functions registered by `chatControllerCapsule`'s
/// effect. Actions call [applyReactionsLocally] / [applyEditLocally] to
/// fan out mutations to every live controller for a thread.
final Map<ThreadKey, List<void Function(_ThreadUpdate)>> _threadUpdaters = {};

/// Per-thread MAM pagination state. Populated by the `<fin/>` listener
/// inside `chatControllerCapsule` and consumed by [loadOlderMessages].
final Map<ThreadKey, MamPageState> _mamPageState = {};

/// Snapshot of a thread's MAM pagination cursor. A [ChangeNotifier]
/// so widgets can rebuild via `ListenableBuilder` when the cursor
/// advances or `complete` flips.
class MamPageState extends ChangeNotifier {
  MamPageState({
    String? oldestStanzaId,
    bool complete = false,
    String? loadingQueryId,
    this.mamInsertIndex = 0,
  }) : _oldestStanzaId = oldestStanzaId,
       _complete = complete,
       _loadingQueryId = loadingQueryId;

  String? _oldestStanzaId;
  String? get oldestStanzaId => _oldestStanzaId;
  set oldestStanzaId(String? v) {
    if (v == _oldestStanzaId) return;
    _oldestStanzaId = v;
    notifyListeners();
  }

  bool _complete;
  bool get complete => _complete;
  set complete(bool v) {
    if (v == _complete) return;
    _complete = v;
    notifyListeners();
  }

  String? _loadingQueryId;
  String? get loadingQueryId => _loadingQueryId;
  set loadingQueryId(String? v) {
    if (v == _loadingQueryId) return;
    _loadingQueryId = v;
    notifyListeners();
  }

  /// Insertion index used by the MAM listener when placing an archived
  /// message into the controller. Reset to 0 at the start of every
  /// "load older" cycle by [loadOlderMessages] so an older page piles
  /// on top of the existing hydrated slice. Not observed by UI.
  int mamInsertIndex;

  bool get canLoadMore =>
      !_complete && _loadingQueryId == null && _oldestStanzaId != null;
  bool get isLoading => _loadingQueryId != null;
}

/// Read-only view of the current pagination state for [threadKey].
MamPageState mamPageStateOf(ThreadKey threadKey) =>
    _mamPageState[threadKey] ?? MamPageState();

// Bumped by [resetMessagesCapsuleCache]. Each capsule closure snapshots
// this at creation and its listeners drop events after a mismatch — so
// old rearch-container-managed capsules go dormant on signout instead of
// polluting a subsequent user's chat state.
int _cacheGeneration = 0;

/// Family capsule: reactive `List<ChatMessage>` for [threadKey]. Kept for
/// group chat pages that haven't migrated to [chatControllerCapsule] yet.
Capsule<List<ChatMessage>> messagesCapsule(ThreadKey threadKey) {
  return _messagesCache.putIfAbsent(threadKey, () {
    final myGeneration = _cacheGeneration;
    List<ChatMessage> capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final myUserId = use(authCapsule).me?.id;
      final slot = use.data<List<ChatMessage>>(const <ChatMessage>[]);

      use.effect(() {
        void append(ChatMessage m) {
          if (myGeneration != _cacheGeneration) return;
          if (slot.value.any((existing) => existing.id == m.id)) return;
          slot.value = <ChatMessage>[...slot.value, m];
        }

        _registerAppender(threadKey, append);

        final StreamSubscription<XmppChatMessage> sub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final fromLocal = _localPart(e.from);
              append(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: DateTime.now(),
                  isMine: myUserId != null && fromLocal == myUserId,
                ),
              );
            });

        return () {
          _unregisterAppender(threadKey, append);
          sub.cancel();
        };
      }, [events, threadKey, myUserId]);

      return slot.value;
    }

    return capsule;
  });
}

/// Family capsule: `InMemoryChatController` for [threadKey], backing the
/// `flutter_chat_ui` `Chat` widget. Feeds identical messages to
/// [messagesCapsule] via the shared appender registry.
Capsule<InMemoryChatController> chatControllerCapsule(ThreadKey threadKey) {
  return _controllersCache.putIfAbsent(threadKey, () {
    final myGeneration = _cacheGeneration;
    InMemoryChatController capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final xmpp = use(xmppCapsule);
      final myUserId = use(authCapsule).me?.id;
      final mirror = use(messagesMirrorCapsule);
      final controller = use.disposable<InMemoryChatController>(
        InMemoryChatController.new,
        (c) => c.dispose(),
        [threadKey],
      );
      final isMuc = threadKey.contains('@muc.');

      // One-shot MAM hydration when the capsule is first built. Works for
      // both 1:1 (peer bare JID) and MUC (room bare JID) — the stub routes
      // on the `with` field's domain.
      use.callonce(() {
        if (myUserId != null && myGeneration == _cacheGeneration) {
          // Hydrate from the on-disk mirror first so the chat shows
          // history immediately; MAM below fills any gaps.
          unawaited(
            _hydrateFromMirror(
              mirror: mirror,
              userId: myUserId,
              threadKey: threadKey,
              controller: controller,
              generation: myGeneration,
              isMuc: isMuc,
            ),
          );
          Timer.run(() => xmpp.queryMamWith(threadKey, max: 50));
        }
        return null;
      });

      use.effect(() {
        Future<void> insertOnce(Message m, {int? index}) async {
          if (myGeneration != _cacheGeneration) return;
          if (controller.messages.any((existing) => existing.id == m.id)) {
            return;
          }
          // Defensive clamp — if some other event source pushed our cursor
          // past the actual list size we'd otherwise blow up in
          // List.insert. Cap at length so insert becomes an append.
          final safeIndex = index == null
              ? null
              : (index > controller.messages.length
                    ? controller.messages.length
                    : index);
          await controller.insertMessage(m, index: safeIndex);
        }

        String senderIdFor(String fromJid, {required bool isGroupChat}) {
          if (isGroupChat) return _resourcePart(fromJid);
          return _localPart(fromJid);
        }

        void insertFromChatMessage(
          ChatMessage cm, {
          required bool isGroupChat,
          int? index,
        }) {
          final senderId = cm.isMine
              ? (myUserId ?? 'me')
              : senderIdFor(cm.from, isGroupChat: isGroupChat);
          insertOnce(_toChatUiMessage(cm, senderId), index: index);
          // Persist text bodies only; attachments still need a fresh
          // MAM hydrate to re-issue the download URL.
          if (myUserId != null && cm.body.isNotEmpty) {
            _bufferForMirror(threadKey: threadKey, cm: cm);
            _saveThreadDebounced(
              mirror: mirror,
              userId: myUserId,
              threadKey: threadKey,
            );
          }
        }

        void append(ChatMessage cm) {
          insertFromChatMessage(cm, isGroupChat: isMuc);
        }

        _registerAppender(threadKey, append);

        final StreamSubscription<XmppChatMessage> liveSub = events
            .where((e) => e is XmppChatMessage)
            .cast<XmppChatMessage>()
            .where((e) => _belongsToThread(e, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final senderId = senderIdFor(e.from, isGroupChat: e.isGroupChat);
              final isMine = myUserId != null && senderId == myUserId;
              insertFromChatMessage(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: DateTime.now(),
                  isMine: isMine,
                  attachment: _fromXmpp(e.attachment),
                  replyToStanzaId: e.replyToStanzaId,
                  thread: e.thread,
                  subject: e.subject,
                ),
                isGroupChat: e.isGroupChat,
              );
              // For a 1:1 message from the peer, auto-send delivery
              // receipt (XEP-0184 / XEP-0333 received) + read marker
              // (XEP-0333 displayed). We're intentionally "aggressive" on
              // displayed for the demo — the capsule is only alive while
              // the chat surface was recently visible.
              if (!isMuc && !isMine && e.stanzaId.isNotEmpty) {
                final peerBare = _bareJid(e.from);
                xmpp.sendDeliveryReceipt(
                  toBareJid: peerBare,
                  stanzaId: e.stanzaId,
                );
                xmpp.sendReadMarker(toBareJid: peerBare, stanzaId: e.stanzaId);
              }
            });

        // MAM stream: preserve chronological (oldest-first) order by
        // inserting at a monotonically-increasing top cursor tracked in
        // [_mamPageState[threadKey].mamInsertIndex]. Both the initial
        // hydration and every subsequent "load older" cycle share the
        // same cursor; [loadOlderMessages] resets it to 0 before each
        // page so the older slice piles ABOVE the existing top.
        final StreamSubscription<XmppMamMessage> mamSub = events
            .where((e) => e is XmppMamMessage)
            .cast<XmppMamMessage>()
            .where((e) => _belongsToMamThread(e, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final state = _mamPageState.putIfAbsent(
                threadKey,
                MamPageState.new,
              );
              final senderId = senderIdFor(e.from, isGroupChat: e.isGroupChat);
              final isMine = myUserId != null && senderId == myUserId;
              insertFromChatMessage(
                ChatMessage(
                  id: e.stanzaId,
                  body: e.body,
                  from: e.from,
                  to: e.to,
                  sentAt: e.sentAt,
                  isMine: isMine,
                  attachment: _fromXmpp(e.attachment),
                  replyToStanzaId: e.replyToStanzaId,
                  thread: e.thread,
                  subject: e.subject,
                ),
                isGroupChat: e.isGroupChat,
                index: state.mamInsertIndex,
              );
              state.mamInsertIndex = state.mamInsertIndex + 1;
              // Offline catch-up: a 1:1 message pulled from the archive
              // still needs a delivery receipt + read marker, otherwise
              // the sender's ticks never advance past "sent" — they saw
              // no live receipt while we were offline.
              if (!isMuc && !isMine && e.stanzaId.isNotEmpty) {
                final peerBare = _bareJid(e.from);
                xmpp.sendDeliveryReceipt(
                  toBareJid: peerBare,
                  stanzaId: e.stanzaId,
                );
                xmpp.sendReadMarker(toBareJid: peerBare, stanzaId: e.stanzaId);
              }
            });

        // XEP-0313 <fin/> — terminates a MAM page. Updates the
        // pagination cursor for [loadOlderMessages].
        final finSub = events
            .where((e) => e is XmppMamFin)
            .cast<XmppMamFin>()
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              final state = _mamPageState.putIfAbsent(
                threadKey,
                MamPageState.new,
              );
              // Only touch state for pages we're expecting on this thread.
              // Initial hydration doesn't set loadingQueryId, so we let its
              // fin populate oldestId / complete when we see a non-empty
              // `first`.
              if (state.loadingQueryId != null &&
                  state.loadingQueryId != e.queryId) {
                return;
              }
              if (e.first.isNotEmpty) {
                state.oldestStanzaId = e.first;
              }
              state.complete = e.complete;
              state.loadingQueryId = null;
            });

        // Delivery receipts (XEP-0184 / XEP-0333 received) — stamp
        // deliveredAt on my messages so the Chat widget upgrades the
        // status icon from "sent" to "delivered".
        final receiptSub = events
            .where((e) => e is XmppDeliveryReceipt)
            .cast<XmppDeliveryReceipt>()
            .where((e) => _matchesThread(e.fromBare, threadKey))
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _stampStatus(
                controller,
                stanzaId: e.stanzaId,
                delivered: true,
              );
            });

        // Read markers (XEP-0333 displayed) — stamp seenAt.
        final markerSub = events
            .where((e) => e is XmppReadMarker)
            .cast<XmppReadMarker>()
            .where((e) => _matchesThread(e.fromBare, threadKey))
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _stampStatus(controller, stanzaId: e.stanzaId, seen: true);
            });

        // XEP-0444 reactions from the peer — same reducer as local
        // reactions but keyed on the sender's local-part.
        final reactionsSub = events
            .where((e) => e is XmppReactions)
            .cast<XmppReactions>()
            .where((e) => _matchesThread(e.fromBare, threadKey))
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _applyReactions(
                controller,
                targetStanzaId: e.targetStanzaId,
                fromUserId: _localPart(e.fromBare),
                emojis: e.emojis,
              );
            });

        // XEP-0308 corrections from the peer — replace the original
        // message's body in-place and stamp editedAt.
        final correctionSub = events
            .where((e) => e is XmppMessageCorrection)
            .cast<XmppMessageCorrection>()
            .where((e) => _matchesThread(e.fromBare, threadKey))
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _applyEdit(
                controller,
                originalStanzaId: e.originalStanzaId,
                newBody: e.newBody,
              );
            });

        // XEP-0424 retract — remove the target message from the
        // controller. Also fires for my own retracts (fanned out by the
        // stub back to me for cross-session symmetry).
        final retractSub = events
            .where((e) => e is XmppRetract)
            .cast<XmppRetract>()
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              final fromLocal = _localPart(e.fromBare);
              final fromMatchesMe = myUserId != null && fromLocal == myUserId;
              // For 1:1 accept retracts either from the peer OR my
              // own outgoing echo. For MUC accept anything on the thread.
              final belongs = e.isGroupChat
                  ? e.fromBare.contains('@muc.') &&
                        _bareJid(e.fromBare) == threadKey
                  : (_matchesThread(e.fromBare, threadKey) || fromMatchesMe);
              if (!belongs) return;
              await _applyRetract(controller, e.targetStanzaId);
            });

        // Server-issued sent-ack — flip our locally-echoed message
        // from MessageStatus.sending → sent.
        final sentAckSub = events
            .where((e) => e is XmppSentAck)
            .cast<XmppSentAck>()
            .listen((e) async {
              if (myGeneration != _cacheGeneration) return;
              await _stampSent(controller, stanzaId: e.stanzaId);
            });

        // Register a thread updater so [applyReactionsLocally] and
        // [applyEditLocally] fan out to us.
        void handleUpdate(_ThreadUpdate u) async {
          if (myGeneration != _cacheGeneration) return;
          switch (u) {
            case _ReactionUpdate(
              :final targetStanzaId,
              :final fromUserId,
              :final emojis,
            ):
              await _applyReactions(
                controller,
                targetStanzaId: targetStanzaId,
                fromUserId: fromUserId,
                emojis: emojis,
              );
            case _EditUpdate(:final originalStanzaId, :final newBody):
              await _applyEdit(
                controller,
                originalStanzaId: originalStanzaId,
                newBody: newBody,
              );
            case _RetractUpdate(:final targetStanzaId):
              await _applyRetract(controller, targetStanzaId);
          }
        }

        _threadUpdaters.putIfAbsent(threadKey, () => []).add(handleUpdate);

        return () {
          _unregisterAppender(threadKey, append);
          liveSub.cancel();
          mamSub.cancel();
          finSub.cancel();
          receiptSub.cancel();
          markerSub.cancel();
          reactionsSub.cancel();
          correctionSub.cancel();
          retractSub.cancel();
          sentAckSub.cancel();
          _threadUpdaters[threadKey]?.remove(handleUpdate);
        };
      }, [events, threadKey, myUserId]);

      return controller;
    }

    return capsule;
  });
}

/// Family capsule: `true` while the peer at [threadKey] is currently
/// typing (last `<composing/>` was recent), otherwise `false`. Auto-clears
/// on `<paused/>`, `<active/>`, `<inactive/>` or after a 6s inactivity
/// timeout so a stray composing without a paused doesn't leave the
/// indicator stuck on.
Capsule<bool> typingCapsule(ThreadKey threadKey) {
  return _typingCache.putIfAbsent(threadKey, () {
    final myGeneration = _cacheGeneration;
    bool capsule(CapsuleHandle use) {
      final events = use(xmppEventsCapsule);
      final slot = use.data<bool>(false);

      use.effect(() {
        Timer? clearTimer;
        final sub = events
            .where((e) => e is XmppChatState)
            .cast<XmppChatState>()
            .where((e) => _matchesThread(e.fromBare, threadKey))
            .listen((e) {
              if (myGeneration != _cacheGeneration) return;
              clearTimer?.cancel();
              if (e.state == 'composing') {
                slot.value = true;
                clearTimer = Timer(const Duration(seconds: 6), () {
                  if (myGeneration == _cacheGeneration) slot.value = false;
                });
              } else {
                slot.value = false;
              }
            });
        return () {
          clearTimer?.cancel();
          sub.cancel();
        };
      }, [events, threadKey]);

      return slot.value;
    }

    return capsule;
  });
}

/// Echoes an outbound (local) [msg] into every appender registered for
/// [threadKey]. Both [messagesCapsule] and [chatControllerCapsule] register
/// their own appenders on first read, so this fans out to whichever
/// consumer(s) are live.
void appendLocalMessage(ThreadKey threadKey, ChatMessage msg) {
  final list = _appenders[threadKey];
  if (list == null) return;
  for (final fn in List.of(list)) {
    fn(msg);
  }
}

/// Updates the `reactions` map on the message with [targetStanzaId] in
/// [threadKey]. Semantics match XEP-0444: [emojis] is the *full* set of
/// reactions from [fromUserId] on the target — an empty list clears them.
void applyReactionsLocally({
  required ThreadKey threadKey,
  required String targetStanzaId,
  required String fromUserId,
  required List<String> emojis,
}) {
  _dispatchUpdate(
    threadKey,
    _ReactionUpdate(
      targetStanzaId: targetStanzaId,
      fromUserId: fromUserId,
      emojis: emojis,
    ),
  );
}

/// XEP-0308-style edit: replaces the `body` of [originalStanzaId] in
/// [threadKey] and stamps `editedAt`.
void applyEditLocally({
  required ThreadKey threadKey,
  required String originalStanzaId,
  required String newBody,
}) {
  _dispatchUpdate(
    threadKey,
    _EditUpdate(originalStanzaId: originalStanzaId, newBody: newBody),
  );
}

/// XEP-0424 retract — drops the target message from all live views of
/// [threadKey].
void applyRetractLocally({
  required ThreadKey threadKey,
  required String targetStanzaId,
}) {
  _dispatchUpdate(threadKey, _RetractUpdate(targetStanzaId: targetStanzaId));
}

/// XEP-0313 "load older" — fires a MAM query anchored `<before>` the
/// current oldest message we have for [threadKey], and resets the
/// insertion cursor so the returned page piles on top of the existing
/// hydrated slice. Returns `false` when the archive is already
/// exhausted, a page is in flight, or we don't yet know an anchor
/// (i.e. the initial hydration hasn't completed). Returns `true` when
/// a request was actually dispatched.
bool loadOlderMessages(
  RainbowXmppClient xmpp,
  ThreadKey threadKey, {
  int max = 50,
}) {
  final state = _mamPageState.putIfAbsent(threadKey, MamPageState.new);
  if (!state.canLoadMore) return false;
  state.mamInsertIndex = 0;
  final qid = xmpp.queryMamWith(
    threadKey,
    max: max,
    beforeStanzaId: state.oldestStanzaId,
  );
  state.loadingQueryId = qid;
  return true;
}

void _dispatchUpdate(ThreadKey threadKey, _ThreadUpdate update) {
  final list = _threadUpdaters[threadKey];
  if (list == null) return;
  for (final fn in List.of(list)) {
    fn(update);
  }
}

sealed class _ThreadUpdate {}

class _ReactionUpdate extends _ThreadUpdate {
  _ReactionUpdate({
    required this.targetStanzaId,
    required this.fromUserId,
    required this.emojis,
  });
  final String targetStanzaId;
  final String fromUserId;
  final List<String> emojis;
}

class _EditUpdate extends _ThreadUpdate {
  _EditUpdate({required this.originalStanzaId, required this.newBody});
  final String originalStanzaId;
  final String newBody;
}

class _RetractUpdate extends _ThreadUpdate {
  _RetractUpdate({required this.targetStanzaId});
  final String targetStanzaId;
}

/// Clears family caches, the appender registry, and bumps the cache
/// generation counter — old rearch-container-managed capsules that
/// snapshot the previous generation will drop future events instead of
/// polluting the new user's chat state.
void resetMessagesCapsuleCache() {
  _messagesCache.clear();
  _controllersCache.clear();
  _typingCache.clear();
  _appenders.clear();
  _threadUpdaters.clear();
  _mamPageState.clear();
  for (final t in _mirrorFlush.values) {
    t.cancel();
  }
  _mirrorFlush.clear();
  _mirrorBuffer.clear();
  _cacheGeneration++;
}

// Per-thread in-memory copy of what should land on disk, keyed by
// stanza id. Flushed to `messagesMirrorCapsule` on a short debounce
// so bursts (MAM hydration, group-chat backlogs) collapse into one
// write.
final Map<String, Map<String, StoredThreadMessage>> _mirrorBuffer = {};
final Map<String, Timer> _mirrorFlush = {};

void _saveThreadDebounced({
  required MessagesMirror mirror,
  required String userId,
  required String threadKey,
}) {
  _mirrorFlush[threadKey]?.cancel();
  _mirrorFlush[threadKey] = Timer(const Duration(milliseconds: 400), () {
    final buffer = _mirrorBuffer[threadKey];
    if (buffer == null || buffer.isEmpty) return;
    final list = buffer.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    unawaited(mirror.saveThread(userId, threadKey, list));
  });
}

/// Registers a stanza in the per-thread buffer. Called from the
/// live/MAM/local insert paths so the debounced flush can persist
/// whatever the controller currently shows.
void _bufferForMirror({required String threadKey, required ChatMessage cm}) {
  final buf = _mirrorBuffer.putIfAbsent(
    threadKey,
    () => <String, StoredThreadMessage>{},
  );
  buf[cm.id] = StoredThreadMessage(
    id: cm.id,
    body: cm.body,
    from: cm.from,
    to: cm.to,
    sentAt: cm.sentAt,
    isMine: cm.isMine,
    replyToStanzaId: cm.replyToStanzaId,
    thread: cm.thread,
    subject: cm.subject,
  );
}

Future<void> _hydrateFromMirror({
  required MessagesMirror mirror,
  required String userId,
  required String threadKey,
  required InMemoryChatController controller,
  required int generation,
  required bool isMuc,
}) async {
  final stored = await mirror.read(userId, threadKey);
  if (stored.isEmpty) return;
  if (generation != _cacheGeneration) return;
  // Feed stored messages back through the appender registry so both
  // messagesCapsule and chatControllerCapsule stay in sync. Order
  // ascending so the chat shows in chronological order.
  final sorted = List<StoredThreadMessage>.from(stored)
    ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  for (final s in sorted) {
    if (controller.messages.any((existing) => existing.id == s.id)) continue;
    final senderId = isMuc ? _resourcePart(s.from) : _localPart(s.from);
    final authorId = s.isMine ? userId : senderId;
    final msg = _toChatUiMessage(
      ChatMessage(
        id: s.id,
        body: s.body,
        from: s.from,
        to: s.to,
        sentAt: s.sentAt,
        isMine: s.isMine,
        replyToStanzaId: s.replyToStanzaId,
        thread: s.thread,
        subject: s.subject,
      ),
      authorId,
    );
    await controller.insertMessage(msg);
  }
  // Seed the buffer so subsequent saves have the full picture.
  final buf = _mirrorBuffer.putIfAbsent(
    threadKey,
    () => <String, StoredThreadMessage>{},
  );
  for (final s in sorted) {
    buf[s.id] = s;
  }
}

Message _toChatUiMessage(ChatMessage cm, String authorId) {
  final a = cm.attachment;
  final MessageStatus? status = cm.isMine && cm.pendingAck
      ? MessageStatus.sending
      : null;
  // Stash the group topic so the bubble UI can group messages by thread.
  final Map<String, dynamic>? metadata =
      (cm.thread != null || cm.subject != null)
      ? {
          if (cm.thread != null) 'thread': cm.thread,
          if (cm.subject != null) 'subject': cm.subject,
        }
      : null;
  if (a != null && a.isImage) {
    return Message.image(
      id: cm.id,
      authorId: authorId,
      createdAt: cm.sentAt,
      sentAt: cm.isMine && !cm.pendingAck ? cm.sentAt : null,
      status: status,
      source: a.downloadUrl,
      text: cm.body,
      size: a.size,
      replyToMessageId: cm.replyToStanzaId,
      reactions: cm.reactions,
      metadata: metadata,
    );
  }
  if (a != null) {
    return Message.file(
      id: cm.id,
      authorId: authorId,
      createdAt: cm.sentAt,
      sentAt: cm.isMine && !cm.pendingAck ? cm.sentAt : null,
      status: status,
      source: a.downloadUrl,
      name: a.fileName,
      mimeType: a.mimeType,
      size: a.size,
      replyToMessageId: cm.replyToStanzaId,
      reactions: cm.reactions,
      metadata: metadata,
    );
  }
  return Message.text(
    id: cm.id,
    authorId: authorId,
    createdAt: cm.sentAt,
    sentAt: cm.isMine && !cm.pendingAck ? cm.sentAt : null,
    status: status,
    text: cm.body,
    replyToMessageId: cm.replyToStanzaId,
    reactions: cm.reactions,
    editedAt: cm.editedAt,
    metadata: metadata,
  );
}

FileDescriptor? _fromXmpp(XmppAttachment? a) {
  if (a == null) return null;
  return FileDescriptor(
    id: a.id,
    fileName: a.fileName,
    mimeType: a.mimeType,
    size: a.size,
    downloadUrl: a.url,
  );
}

/// Finds the message with [stanzaId] and calls `updateMessage` with an
/// upgraded status timeline. No-op if the id isn't in the controller.
///
/// Also collapses any lingering `MessageStatus.sending` state and stamps
/// [Message.sentAt], because a delivery receipt implies the server
/// accepted the message (i.e. it is at least "sent").
Future<void> _stampStatus(
  InMemoryChatController controller, {
  required String stanzaId,
  bool delivered = false,
  bool seen = false,
}) async {
  final old = controller.messages.where((m) => m.id == stanzaId).firstOrNull;
  if (old == null) return;
  final now = DateTime.now();
  final Message updated;
  switch (old) {
    case TextMessage m:
      updated = m.copyWith(
        status: m.status == MessageStatus.sending ? null : m.status,
        sentAt: m.sentAt ?? now,
        deliveredAt: delivered || seen ? (m.deliveredAt ?? now) : m.deliveredAt,
        seenAt: seen ? (m.seenAt ?? now) : m.seenAt,
      );
    case ImageMessage m:
      updated = m.copyWith(
        status: m.status == MessageStatus.sending ? null : m.status,
        sentAt: m.sentAt ?? now,
        deliveredAt: delivered || seen ? (m.deliveredAt ?? now) : m.deliveredAt,
        seenAt: seen ? (m.seenAt ?? now) : m.seenAt,
      );
    case FileMessage m:
      updated = m.copyWith(
        status: m.status == MessageStatus.sending ? null : m.status,
        sentAt: m.sentAt ?? now,
        deliveredAt: delivered || seen ? (m.deliveredAt ?? now) : m.deliveredAt,
        seenAt: seen ? (m.seenAt ?? now) : m.seenAt,
      );
    default:
      return;
  }
  if (identical(updated, old)) return;
  await controller.updateMessage(old, updated);
}

/// Applies a XEP-0444 reactions snapshot to the message with
/// [targetStanzaId]. Replaces [fromUserId]'s reactions on the target.
Future<void> _applyReactions(
  InMemoryChatController controller, {
  required String targetStanzaId,
  required String fromUserId,
  required List<String> emojis,
}) async {
  final old = controller.messages
      .where((m) => m.id == targetStanzaId)
      .firstOrNull;
  if (old == null) return;
  final oldMap = _reactionsOf(old);
  final next = <String, List<String>>{};
  oldMap.forEach((emoji, users) {
    final filtered = users.where((u) => u != fromUserId).toList();
    if (filtered.isNotEmpty) next[emoji] = filtered;
  });
  for (final e in emojis) {
    final list = next.putIfAbsent(e, () => <String>[]);
    if (!list.contains(fromUserId)) list.add(fromUserId);
  }
  final Message updated;
  switch (old) {
    case TextMessage m:
      updated = m.copyWith(reactions: next);
    case ImageMessage m:
      updated = m.copyWith(reactions: next);
    case FileMessage m:
      updated = m.copyWith(reactions: next);
    default:
      return;
  }
  await controller.updateMessage(old, updated);
}

/// XEP-0308-style body replacement + editedAt stamp.
Future<void> _applyEdit(
  InMemoryChatController controller, {
  required String originalStanzaId,
  required String newBody,
}) async {
  final old = controller.messages
      .where((m) => m.id == originalStanzaId)
      .firstOrNull;
  if (old == null) return;
  final now = DateTime.now();
  final Message updated;
  switch (old) {
    case TextMessage m:
      updated = m.copyWith(text: newBody, editedAt: now);
    case ImageMessage m:
      // ImageMessage has no editedAt; use updatedAt to signal a change.
      updated = m.copyWith(text: newBody, updatedAt: now);
    case FileMessage m:
      // FileMessage has no text; only the file description body — swap
      // the display name.
      updated = m.copyWith(name: newBody, updatedAt: now);
    default:
      return;
  }
  await controller.updateMessage(old, updated);
}

Map<String, List<String>> _reactionsOf(Message m) => switch (m) {
  TextMessage m => Map.of(m.reactions ?? const {}),
  ImageMessage m => Map.of(m.reactions ?? const {}),
  FileMessage m => Map.of(m.reactions ?? const {}),
  _ => <String, List<String>>{},
};

/// XEP-0424 retract handler — drops the target message.
Future<void> _applyRetract(
  InMemoryChatController controller,
  String targetStanzaId,
) async {
  final target = controller.messages
      .where((m) => m.id == targetStanzaId)
      .firstOrNull;
  if (target == null) return;
  await controller.removeMessage(target);
}

/// Server sent-ack — clears the "sending" status and stamps sentAt.
Future<void> _stampSent(
  InMemoryChatController controller, {
  required String stanzaId,
}) async {
  final old = controller.messages.where((m) => m.id == stanzaId).firstOrNull;
  if (old == null) return;
  final now = DateTime.now();
  final Message updated;
  switch (old) {
    case TextMessage m when m.status == MessageStatus.sending:
      updated = m.copyWith(status: null, sentAt: m.sentAt ?? now);
    case ImageMessage m when m.status == MessageStatus.sending:
      updated = m.copyWith(status: null, sentAt: m.sentAt ?? now);
    case FileMessage m when m.status == MessageStatus.sending:
      updated = m.copyWith(status: null, sentAt: m.sentAt ?? now);
    default:
      return;
  }
  await controller.updateMessage(old, updated);
}

void _registerAppender(ThreadKey threadKey, void Function(ChatMessage) fn) {
  _appenders.putIfAbsent(threadKey, () => []).add(fn);
}

void _unregisterAppender(ThreadKey threadKey, void Function(ChatMessage) fn) {
  final list = _appenders[threadKey];
  if (list == null) return;
  list.remove(fn);
  if (list.isEmpty) _appenders.remove(threadKey);
}

bool _belongsToThread(XmppChatMessage e, ThreadKey threadKey) {
  // Thread keys are `<userId>@<localDomain>` but the server stamps its
  // OWN domain on incoming `from=`, and clients on different builds
  // may hold different `xmppDomain` values (e.g. an Android emulator
  // using `10.0.2.2` vs. web using `localhost`). Compare on local-part
  // (== user id) for 1:1 and on the full bare JID for MUC rooms.
  if (e.isGroupChat || threadKey.contains('@muc.')) {
    return _bareJid(e.from) == threadKey || _bareJid(e.to) == threadKey;
  }
  final threadLocal = _localPart(threadKey);
  return _localPart(e.from) == threadLocal || _localPart(e.to) == threadLocal;
}

bool _belongsToMamThread(XmppMamMessage e, ThreadKey threadKey) {
  if (e.isGroupChat || threadKey.contains('@muc.')) {
    return _bareJid(e.from) == threadKey || _bareJid(e.to) == threadKey;
  }
  final threadLocal = _localPart(threadKey);
  return _localPart(e.from) == threadLocal || _localPart(e.to) == threadLocal;
}

/// Domain-tolerant equivalent of `fromBare == threadKey`. See
/// [_belongsToThread] for rationale.
bool _matchesThread(String fromBare, ThreadKey threadKey) {
  if (threadKey.contains('@muc.')) return fromBare == threadKey;
  return _localPart(fromBare) == _localPart(threadKey);
}

String _bareJid(String jid) =>
    jid.contains('/') ? jid.substring(0, jid.indexOf('/')) : jid;

String _localPart(String jid) {
  final bare = _bareJid(jid);
  final at = bare.indexOf('@');
  return at >= 0 ? bare.substring(0, at) : bare;
}

/// Returns the resource part of a full JID (the segment after `/`), which
/// for MUC messages is the sender's nick — set by our client to the
/// sender's user id.
String _resourcePart(String jid) {
  final slash = jid.indexOf('/');
  return slash >= 0 ? jid.substring(slash + 1) : jid;
}
