import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Row shape persisted by [ConversationsMirror]. Mirrors the fields
/// on [ConversationSummary] so the capsule can rebuild the runtime
/// summary map from disk without loss.
class StoredConversation {
  const StoredConversation({
    required this.peerId,
    required this.peerDisplay,
    required this.lastBody,
    required this.lastAt,
    required this.directionOutgoing,
  });

  final String peerId;
  final String peerDisplay;
  final String lastBody;
  final DateTime lastAt;
  final bool directionOutgoing;

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'peerDisplay': peerDisplay,
    'lastBody': lastBody,
    'lastAt': lastAt.toIso8601String(),
    'directionOutgoing': directionOutgoing,
  };

  static StoredConversation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final peerId = raw['peerId'] as String?;
    final lastAt = raw['lastAt'] as String?;
    if (peerId == null || lastAt == null) return null;
    final at = DateTime.tryParse(lastAt);
    if (at == null) return null;
    return StoredConversation(
      peerId: peerId,
      peerDisplay: (raw['peerDisplay'] as String?) ?? peerId,
      lastBody: (raw['lastBody'] as String?) ?? '',
      lastAt: at,
      directionOutgoing: (raw['directionOutgoing'] as bool?) ?? false,
    );
  }
}

/// Persists the Recent tab's conversation summaries per signed-in
/// user so a cold start (page refresh, app relaunch) shows the last
/// known list before MAM / live traffic arrives.
abstract class ConversationsMirror {
  Future<List<StoredConversation>> read(String userId);
  Future<void> write(String userId, List<StoredConversation> entries);
  Future<void> clear(String userId);
}

class SharedPrefsConversationsMirror implements ConversationsMirror {
  const SharedPrefsConversationsMirror();

  String _key(String userId) => 'conversations.$userId';

  @override
  Future<List<StoredConversation>> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(StoredConversation.fromJson)
          .whereType<StoredConversation>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> write(String userId, List<StoredConversation> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(userId),
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
    } on Object {
      // ignore
    }
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

class NoOpConversationsMirror implements ConversationsMirror {
  const NoOpConversationsMirror();
  @override
  Future<List<StoredConversation>> read(String userId) async => const [];
  @override
  Future<void> write(String userId, List<StoredConversation> entries) async {}
  @override
  Future<void> clear(String userId) async {}
}
