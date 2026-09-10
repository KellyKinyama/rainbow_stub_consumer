class RainbowUser {
  RainbowUser({
    required this.id,
    required this.loginEmail,
    this.firstName,
    this.lastName,
    this.displayName,
    this.jobTitle,
    this.presenceShow,
    this.presenceStatus,
    this.hasAvatar = false,
  });

  final String id;
  final String loginEmail;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String? jobTitle;
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
    jobTitle: j['jobTitle'] as String?,
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
  });

  final String id;
  final String body;
  final String from;
  final String to;
  final DateTime sentAt;
  final bool isMine;
  final FileDescriptor? attachment;
}

/// Metadata for an attached file returned by the stub's file endpoint.
class FileDescriptor {
  const FileDescriptor({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.downloadUrl,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int size;
  final String downloadUrl;

  bool get isImage => mimeType.startsWith('image/');

  factory FileDescriptor.fromJson(Map<String, dynamic> j) => FileDescriptor(
    id: j['id'] as String,
    fileName: (j['fileName'] ?? 'file') as String,
    mimeType: (j['mime'] ?? 'application/octet-stream') as String,
    size: (j['size'] as int?) ?? 0,
    downloadUrl: (j['downloadUrl'] ?? '') as String,
  );
}
