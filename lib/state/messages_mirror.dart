import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One archived stanza persisted locally so a chat page can render
/// history immediately on mount, before MAM comes back. Only text
/// bodies are mirrored — attachments still need a fresh MAM hydrate
/// to resolve the download URL.
class StoredThreadMessage {
  const StoredThreadMessage({
    required this.id,
    required this.body,
    required this.from,
    required this.to,
    required this.sentAt,
    required this.isMine,
    this.replyToStanzaId,
    this.thread,
    this.subject,
  });

  final String id;
  final String body;
  final String from;
  final String to;
  final DateTime sentAt;
  final bool isMine;
  final String? replyToStanzaId;
  final String? thread;
  final String? subject;

  Map<String, dynamic> toJson() => {
    'id': id,
    'body': body,
    'from': from,
    'to': to,
    'sentAt': sentAt.toIso8601String(),
    'isMine': isMine,
    if (replyToStanzaId != null) 'replyToStanzaId': replyToStanzaId,
    if (thread != null) 'thread': thread,
    if (subject != null) 'subject': subject,
  };

  static StoredThreadMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final sentAt = raw['sentAt'] as String?;
    if (id == null || sentAt == null) return null;
    final at = DateTime.tryParse(sentAt);
    if (at == null) return null;
    return StoredThreadMessage(
      id: id,
      body: (raw['body'] as String?) ?? '',
      from: (raw['from'] as String?) ?? '',
      to: (raw['to'] as String?) ?? '',
      sentAt: at,
      isMine: (raw['isMine'] as bool?) ?? false,
      replyToStanzaId: raw['replyToStanzaId'] as String?,
      thread: raw['thread'] as String?,
      subject: raw['subject'] as String?,
    );
  }
}

abstract class MessagesMirror {
  Future<List<StoredThreadMessage>> read(String userId, String threadKey);
  Future<void> saveThread(
    String userId,
    String threadKey,
    List<StoredThreadMessage> messages,
  );
  Future<void> clearUser(String userId);
}

class SharedPrefsMessagesMirror implements MessagesMirror {
  const SharedPrefsMessagesMirror();

  static const int maxPerThread = 100;

  // v2: added group topic (thread/subject). Bumping the key prefix
  // orphans older thread-less caches so history re-hydrates from MAM.
  String _threadKey(String userId, String threadKey) =>
      'msgs2.$userId.$threadKey';
  String _indexKey(String userId) => 'msg_threads2.$userId';

  @override
  Future<List<StoredThreadMessage>> read(
    String userId,
    String threadKey,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_threadKey(userId, threadKey));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(StoredThreadMessage.fromJson)
          .whereType<StoredThreadMessage>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> saveThread(
    String userId,
    String threadKey,
    List<StoredThreadMessage> messages,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final capped = messages.length > maxPerThread
          ? messages.sublist(messages.length - maxPerThread)
          : messages;
      await prefs.setString(
        _threadKey(userId, threadKey),
        jsonEncode(capped.map((m) => m.toJson()).toList()),
      );
      // Track thread keys under an index so clearUser can iterate.
      final indexJson = prefs.getString(_indexKey(userId));
      final set = <String>{
        if (indexJson != null && jsonDecode(indexJson) is List)
          ...(jsonDecode(indexJson) as List).cast<String>(),
      }..add(threadKey);
      await prefs.setString(_indexKey(userId), jsonEncode(set.toList()));
    } on Object {
      // ignore
    }
  }

  @override
  Future<void> clearUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final indexJson = prefs.getString(_indexKey(userId));
      if (indexJson != null && jsonDecode(indexJson) is List) {
        for (final t in (jsonDecode(indexJson) as List).cast<String>()) {
          await prefs.remove(_threadKey(userId, t));
        }
      }
      await prefs.remove(_indexKey(userId));
    } on Object {
      // ignore
    }
  }
}

class NoOpMessagesMirror implements MessagesMirror {
  const NoOpMessagesMirror();
  @override
  Future<List<StoredThreadMessage>> read(
    String userId,
    String threadKey,
  ) async => const [];
  @override
  Future<void> saveThread(
    String userId,
    String threadKey,
    List<StoredThreadMessage> messages,
  ) async {}
  @override
  Future<void> clearUser(String userId) async {}
}
