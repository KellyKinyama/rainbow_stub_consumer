class RainbowUser {
  RainbowUser({
    required this.id,
    required this.loginEmail,
    this.firstName,
    this.lastName,
    this.displayName,
    this.nickName,
    this.title,
    this.jobTitle,
    this.language,
    this.presenceShow,
    this.presenceStatus,
    this.hasAvatar = false,
  });

  final String id;
  final String loginEmail;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String? nickName;
  final String? title;
  final String? jobTitle;
  final String? language;
  final String? presenceShow;
  final String? presenceStatus;
  final bool hasAvatar;

  String get display => (displayName?.isNotEmpty ?? false)
      ? displayName!
      : '${firstName ?? ''} ${lastName ?? ''}'.trim().isNotEmpty
      ? '${firstName ?? ''} ${lastName ?? ''}'.trim()
      : loginEmail;

  factory RainbowUser.fromJson(Map<String, dynamic> j) => RainbowUser(
    id: j['id'] as String,
    loginEmail: j['loginEmail'] as String? ?? '',
    firstName: j['firstName'] as String?,
    lastName: j['lastName'] as String?,
    displayName: j['displayName'] as String?,
    nickName: j['nickName'] as String?,
    title: j['title'] as String?,
    jobTitle: j['jobTitle'] as String?,
    language: j['language'] as String?,
    presenceShow: (j['presence'] as Map?)?['show'] as String?,
    presenceStatus: (j['presence'] as Map?)?['status'] as String?,
    hasAvatar: j['lastAvatarUpdateDate'] != null,
  );
}

class RosterEntry {
  RosterEntry({required this.userId, required this.peer, required this.status});
  final String userId;
  final RainbowUser peer;
  final String status;

  factory RosterEntry.fromJson(Map<String, dynamic> j) => RosterEntry(
    userId: j['userId'] as String? ?? '',
    peer: RainbowUser.fromJson(j['peerUser'] as Map<String, dynamic>),
    status: j['status'] as String? ?? 'accepted',
  );
}

class RainbowBubble {
  RainbowBubble({
    required this.id,
    required this.name,
    this.topic,
    required this.members,
  });

  final String id;
  final String name;
  final String? topic;
  final List<BubbleMember> members;

  factory RainbowBubble.fromJson(Map<String, dynamic> j) => RainbowBubble(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    topic: j['topic'] as String?,
    members: ((j['users'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => BubbleMember.fromJson(m.cast<String, dynamic>()))
        .toList(),
  );
}

class BubbleMember {
  BubbleMember({
    required this.userId,
    required this.role,
    required this.status,
  });
  final String userId;
  final String role;
  final String status;

  factory BubbleMember.fromJson(Map<String, dynamic> j) => BubbleMember(
    userId: j['userId'] as String,
    role: (j['privilege'] ?? 'user') as String,
    status: (j['status'] ?? 'accepted') as String,
  );
}

/// One entry from `GET /users/:id/calllogs`.
class CallLogEntry {
  CallLogEntry({
    required this.id,
    required this.peerJid,
    required this.peerDisplayName,
    required this.direction,
    required this.state,
    required this.media,
    required this.startedAt,
    required this.durationMs,
    required this.isRead,
    this.readAt,
  });

  final String id;
  final String peerJid;
  final String? peerDisplayName;

  /// `outgoing | incoming`.
  final String direction;

  /// `answered | missed | declined | failed`.
  final String state;

  /// `audio | video`.
  final String media;
  final DateTime startedAt;
  final int durationMs;
  final bool isRead;
  final DateTime? readAt;

  bool get isMissed => state == 'missed';
  bool get isOutgoing => direction == 'outgoing';

  factory CallLogEntry.fromJson(Map<String, dynamic> j) => CallLogEntry(
    id: j['id'] as String,
    peerJid: (j['peer'] ?? '') as String,
    peerDisplayName: j['peerDisplayName'] as String?,
    direction: (j['direction'] ?? 'outgoing') as String,
    state: (j['state'] ?? 'answered') as String,
    media: (j['media'] ?? 'audio') as String,
    startedAt: DateTime.parse(j['startDate'] as String),
    durationMs: (j['duration'] as num?)?.toInt() ?? 0,
    isRead: (j['isRead'] as bool?) ?? false,
    readAt: j['readDate'] == null
        ? null
        : DateTime.parse(j['readDate'] as String),
  );
}

/// In-memory chat message — populated by REST (history) and by XMPP (live).
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.body,
    required this.from,
    required this.to,
    required this.sentAt,
    this.isMine = false,
    this.attachment,
    this.replyToStanzaId,
    this.reactions,
    this.editedAt,
    this.pendingAck = false,
  });

  final String id;
  final String body;
  final String from;
  final String to;
  final DateTime sentAt;
  final bool isMine;
  final FileDescriptor? attachment;
  final String? replyToStanzaId;
  final Map<String, List<String>>? reactions;
  final DateTime? editedAt;

  /// `true` while a locally-echoed message is awaiting the server
  /// sent-ack; consumed by `_toChatUiMessage` to render the "sending"
  /// status.
  final bool pendingAck;
}

/// Metadata for an attached file returned by the stub's file endpoint.
class FileDescriptor {
  const FileDescriptor({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.downloadUrl,
    this.ownerId,
    this.peer,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int size;
  final String downloadUrl;
  final String? ownerId;
  final String? peer;
  final DateTime? createdAt;

  bool get isImage => mimeType.startsWith('image/');

  factory FileDescriptor.fromJson(Map<String, dynamic> j) => FileDescriptor(
    id: j['id'] as String,
    fileName: (j['fileName'] ?? 'file') as String,
    mimeType: (j['mime'] ?? 'application/octet-stream') as String,
    size: (j['size'] as int?) ?? 0,
    downloadUrl: (j['downloadUrl'] ?? '') as String,
    ownerId: j['ownerId'] as String?,
    peer: j['peer'] as String?,
    createdAt: switch (j['creationDate']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );
}
