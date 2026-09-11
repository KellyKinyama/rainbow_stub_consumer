import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A message the user composed while offline (or during a brief
/// XMPP outage) that couldn't hit the wire. [OutgoingQueue.drain] on
/// [XmppConnected] replays these in FIFO order.
class QueuedSend {
  const QueuedSend({
    required this.id,
    required this.threadKey,
    required this.isGroupChat,
    required this.body,
    required this.queuedAt,
    this.replyToStanzaId,
  });

  final String id;
  final String threadKey;
  final bool isGroupChat;
  final String body;
  final DateTime queuedAt;
  final String? replyToStanzaId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'threadKey': threadKey,
        'isGroupChat': isGroupChat,
        'body': body,
        'queuedAt': queuedAt.toIso8601String(),
        if (replyToStanzaId != null) 'replyToStanzaId': replyToStanzaId,
      };

  static QueuedSend? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final threadKey = raw['threadKey'] as String?;
    final body = raw['body'] as String?;
    final queuedAt = raw['queuedAt'] as String?;
    if (id == null || threadKey == null || body == null || queuedAt == null) {
      return null;
    }
    final at = DateTime.tryParse(queuedAt);
    if (at == null) return null;
    return QueuedSend(
      id: id,
      threadKey: threadKey,
      isGroupChat: (raw['isGroupChat'] as bool?) ?? false,
      body: body,
      queuedAt: at,
      replyToStanzaId: raw['replyToStanzaId'] as String?,
    );
  }
}

abstract class OutgoingQueue {
  Future<List<QueuedSend>> readAll(String userId);
  Future<void> add(String userId, QueuedSend send);
  Future<void> remove(String userId, String id);
  Future<void> clear(String userId);
}

class SharedPrefsOutgoingQueue implements OutgoingQueue {
  const SharedPrefsOutgoingQueue();

  String _key(String userId) => 'outbox.$userId';

  @override
  Future<List<QueuedSend>> readAll(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(QueuedSend.fromJson)
          .whereType<QueuedSend>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> _writeAll(String userId, List<QueuedSend> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(userId),
        jsonEncode(list.map((q) => q.toJson()).toList()),
      );
    } on Object {
      // ignore
    }
  }

  @override
  Future<void> add(String userId, QueuedSend send) async {
    final list = List<QueuedSend>.of(await readAll(userId))..add(send);
    await _writeAll(userId, list);
  }

  @override
  Future<void> remove(String userId, String id) async {
    final list = (await readAll(userId)).where((q) => q.id != id).toList();
    await _writeAll(userId, list);
  }

  @override
  Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } on Object {
      // ignore
    }
  }
}

class NoOpOutgoingQueue implements OutgoingQueue {
  const NoOpOutgoingQueue();
  @override
  Future<List<QueuedSend>> readAll(String userId) async => const [];
  @override
  Future<void> add(String userId, QueuedSend send) async {}
  @override
  Future<void> remove(String userId, String id) async {}
  @override
  Future<void> clear(String userId) async {}
}
