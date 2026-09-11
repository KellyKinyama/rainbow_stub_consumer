import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config.dart';
import 'models.dart';

class RainbowRestException implements Exception {
  RainbowRestException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'RainbowRestException($status): $body';
}

class LoginResult {
  LoginResult({
    required this.token,
    required this.expiresIn,
    required this.loggedInUser,
  });
  final String token;
  final int expiresIn;
  final RainbowUser loggedInUser;
}

class RainbowRestClient {
  RainbowRestClient(this.config) : _http = _buildClient();

  final AppConfig config;
  final http.Client _http;

  String? _bearer;
  String? get token => _bearer;
  void setBearer(String? t) => _bearer = t;

  static http.Client _buildClient() {
    // In dev the rainbow-stub uses a self-signed TLS certificate; accept it.
    try {
      final io = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      return IOClient(io);
    } on UnsupportedError {
      // Web platform — falls through to default which handles TLS via browser.
      return http.Client();
    }
  }

  Uri _u(String path, [Map<String, String>? qs]) =>
      config.baseUrl.replace(path: path, queryParameters: qs);

  Map<String, String> _authed({
    String? contentType,
    bool includeAppAuth = false,
  }) => {
    if (contentType != null) 'content-type': contentType,
    if (_bearer != null) 'authorization': 'Bearer $_bearer',
    if (includeAppAuth) 'x-rainbow-app-auth': config.appAuth,
  };

  Future<LoginResult> login(String email, String password) async {
    final basic = base64Encode(utf8.encode('$email:$password'));
    final r = await _http.get(
      _u('/api/rainbow/authentication/v1.0/login'),
      headers: {
        'authorization': 'Basic $basic',
        'x-rainbow-app-auth': config.appAuth,
      },
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final tok = j['token'] as String;
    _bearer = tok;
    return LoginResult(
      token: tok,
      expiresIn: (j['expiresIn'] as num).toInt(),
      loggedInUser: RainbowUser.fromJson(
        j['loggedInUser'] as Map<String, dynamic>,
      ),
    );
  }

  Future<void> logout() async {
    if (_bearer == null) return;
    await _http.post(
      _u('/api/rainbow/authentication/v1.0/logout'),
      headers: _authed(),
    );
    _bearer = null;
  }

  /// Self-register step 1: ask the server to email a confirmation
  /// token. The stub returns the token in the response body under
  /// `data.devToken` so demos can skip a real mailbox.
  Future<String> selfRegisterSendEmail(String email) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/self-register/send-email'),
      headers: _authed(contentType: 'application/json', includeAppAuth: true),
      body: jsonEncode({'email': email}),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['data'] as Map<String, dynamic>)['devToken'] as String);
  }

  /// Self-register step 2: complete registration with the confirmation
  /// token from [selfRegisterSendEmail] plus the new password.
  Future<RainbowUser> selfRegister({
    required String token,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/self-register'),
      headers: _authed(contentType: 'application/json', includeAppAuth: true),
      body: jsonEncode({
        'token': token,
        'password': password,
        if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
        if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
      }),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowUser.fromJson(j['data'] as Map<String, dynamic>);
  }

  /// Reset-password step 1: request an email with a reset token.
  /// Same devToken-in-response trick as [selfRegisterSendEmail].
  Future<String> resetPasswordSendEmail(String email) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/reset-password/send-email'),
      headers: _authed(contentType: 'application/json', includeAppAuth: true),
      body: jsonEncode({'email': email}),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['data'] as Map<String, dynamic>)['devToken'] as String);
  }

  /// Reset-password step 2: apply the new password given the token.
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/reset-password'),
      headers: _authed(contentType: 'application/json', includeAppAuth: true),
      body: jsonEncode({'token': token, 'password': password}),
    );
    _check(r);
  }

  /// Updates mutable profile fields on the signed-in user. Any null
  /// field is left unchanged server-side (COALESCE semantics).
  Future<RainbowUser> updateMe({
    required String userId,
    String? firstName,
    String? lastName,
    String? nickName,
    String? title,
    String? jobTitle,
    String? language,
  }) async {
    final r = await _http.put(
      _u('/api/rainbow/enduser/v1.0/users/$userId'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (nickName != null) 'nickName': nickName,
        if (title != null) 'title': title,
        if (jobTitle != null) 'jobTitle': jobTitle,
        if (language != null) 'language': language,
      }),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowUser.fromJson(j['data'] as Map<String, dynamic>);
  }

  Future<List<RosterEntry>> networks() async {
    final r = await _http.get(
      _u('/api/rainbow/enduser/v1.0/users/networks'),
      headers: _authed(),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['data'] as List)
        .cast<Map<String, dynamic>>()
        .map(RosterEntry.fromJson)
        .toList();
  }

  Future<List<RainbowUser>> searchUsers(String query, {int limit = 20}) async {
    final r = await _http.get(
      _u('/api/rainbow/enduser/v1.0/users', {
        'search': query,
        'limit': '$limit',
      }),
      headers: _authed(),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['data'] as List)
        .cast<Map<String, dynamic>>()
        .map(RainbowUser.fromJson)
        .toList(growable: false);
  }

  Future<RosterEntry> addContact(String userId) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/networks/$userId'),
      headers: _authed(contentType: 'application/json'),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RosterEntry.fromJson(j['data'] as Map<String, dynamic>);
  }

  Future<void> removeContact(String userId) async {
    final r = await _http.delete(
      _u('/api/rainbow/enduser/v1.0/users/networks/$userId'),
      headers: _authed(),
    );
    _check(r);
  }

  Future<RainbowUser> getUser(String id) async {
    final r = await _http.get(
      _u('/api/rainbow/enduser/v1.0/users/$id'),
      headers: _authed(),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowUser.fromJson(j['data'] as Map<String, dynamic>);
  }

  Future<List<RainbowBubble>> rooms() async {
    final r = await _http.get(
      _u('/api/rainbow/enduser/v1.0/rooms'),
      headers: _authed(),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['data'] as List)
        .cast<Map<String, dynamic>>()
        .map(RainbowBubble.fromJson)
        .toList();
  }

  Future<RainbowBubble> createRoom(String name, {String? topic}) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/rooms'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({'name': name, if (topic != null) 'topic': topic}),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowBubble.fromJson(j['data'] as Map<String, dynamic>);
  }

  /// Fetches bubbles the signed-in user has been invited to but not
  /// yet accepted — the server returns `status='invited'` rows.
  Future<List<RainbowBubble>> roomInvitations() async {
    final r = await _http.get(
      _u('/api/rainbow/enduser/v1.0/rooms/invitations'),
      headers: _authed(),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['data'] as List)
        .cast<Map<String, dynamic>>()
        .map(RainbowBubble.fromJson)
        .toList();
  }

  Future<RainbowBubble> updateRoom(
    String id, {
    String? name,
    String? topic,
    bool? isArchived,
  }) async {
    final r = await _http.put(
      _u('/api/rainbow/enduser/v1.0/rooms/$id'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (topic != null) 'topic': topic,
        if (isArchived != null) 'isArchived': isArchived,
      }),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowBubble.fromJson(j['data'] as Map<String, dynamic>);
  }

  Future<void> deleteRoom(String id) async {
    final r = await _http.delete(
      _u('/api/rainbow/enduser/v1.0/rooms/$id'),
      headers: _authed(),
    );
    _check(r);
  }

  /// Invites a user into a room by user id (preferred) or login email.
  /// Server accepts either; supplying both is allowed but user id wins.
  Future<RainbowBubble> inviteToRoom(
    String id, {
    String? userId,
    String? loginEmail,
  }) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/rooms/$id/users'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({
        if (userId != null) 'userId': userId,
        if (loginEmail != null) 'loginEmail': loginEmail,
      }),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowBubble.fromJson(j['data'] as Map<String, dynamic>);
  }

  /// Updates a member's status inside a room. Used for
  /// accept / decline invitation, leave, and moderator-side kicks.
  Future<RainbowBubble> setRoomMemberStatus({
    required String bubbleId,
    required String userId,
    required String status,
  }) async {
    final r = await _http.put(
      _u('/api/rainbow/enduser/v1.0/rooms/$bubbleId/users/$userId'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({'status': status}),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return RainbowBubble.fromJson(j['data'] as Map<String, dynamic>);
  }

  Future<void> setPresence(String userId, String show, {String? status}) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/$userId/presences'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({'show': show, if (status != null) 'status': status}),
    );
    _check(r);
  }

  /// Registers a push notification device token with the server. The
  /// [platform] must be one of `ios | android | web | debug`.
  Future<void> registerPushToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/$userId/push-tokens'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({'token': token, 'platform': platform}),
    );
    _check(r);
  }

  /// Removes a previously registered device token — call from a
  /// "sign out this device" flow so we don't push to a stale token.
  Future<void> deletePushToken({
    required String userId,
    required String token,
  }) async {
    final r = await _http.delete(
      _u(
        '/api/rainbow/enduser/v1.0/users/$userId/push-tokens/'
        '${Uri.encodeComponent(token)}',
      ),
      headers: _authed(),
    );
    _check(r);
  }

  /// Records a completed call in the server-side history so the call
  /// log tab reflects it. Non-fatal — the caller may fire-and-forget.
  Future<void> insertCallLog({
    required String userId,
    required String peerJid,
    String? peerDisplay,
    required String direction,
    required String state,
    String media = 'audio',
    int durationMs = 0,
  }) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/$userId/calllogs'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({
        'peerJid': peerJid,
        if (peerDisplay != null) 'peerDisplay': peerDisplay,
        'direction': direction,
        'state': state,
        'media': media,
        'durationMs': durationMs,
      }),
    );
    _check(r);
  }

  /// Fetches the signed-in user's call history, most recent first.
  Future<List<CallLogEntry>> listCallLogs({
    required String userId,
    int limit = 100,
    int offset = 0,
  }) async {
    final r = await _http.get(
      _u('/api/rainbow/enduser/v1.0/users/$userId/calllogs', {
        'limit': '$limit',
        'offset': '$offset',
      }),
      headers: _authed(),
    );
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (j['data'] as List)
        .cast<Map<String, dynamic>>()
        .map(CallLogEntry.fromJson)
        .toList();
  }

  /// Deletes a single call-log entry by id.
  Future<void> deleteCallLog({
    required String userId,
    required String id,
  }) async {
    final r = await _http.delete(
      _u('/api/rainbow/enduser/v1.0/users/$userId/calllogs/$id'),
      headers: _authed(),
    );
    _check(r);
  }

  /// Two-step upload — creates a descriptor, then PUTs the bytes. Returns
  /// the descriptor with the `downloadUrl` filled in.
  Future<FileDescriptor> uploadFile({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required String peerJid,
    String peerType = 'user',
  }) async {
    final create = await _http.post(
      _u('/api/rainbow/fileServer/v1.0/files'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({
        'peer': peerJid,
        'peerType': peerType,
        'fileName': fileName,
        'mime': mimeType,
        'size': bytes.length,
      }),
    );
    _check(create);
    final createBody = jsonDecode(create.body) as Map<String, dynamic>;
    final id = (createBody['data'] as Map<String, dynamic>)['id'] as String;

    final put = await _http.put(
      _u('/api/rainbow/fileServer/v1.0/files/$id/data'),
      headers: _authed(contentType: mimeType),
      body: bytes,
    );
    _check(put);
    final putBody = jsonDecode(put.body) as Map<String, dynamic>;
    return FileDescriptor.fromJson(
      (putBody['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<List<FileDescriptor>> listSharedFiles(String peerJid) async {
    final r = await _http.get(
      _u('/api/rainbow/fileServer/v1.0/files', {'peer': peerJid}),
      headers: _authed(),
    );
    _check(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final data = (body['data'] as List).cast<Map>();
    return data
        .map((m) => FileDescriptor.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> deleteFile(String id) async {
    final r = await _http.delete(
      _u('/api/rainbow/fileServer/v1.0/files/$id'),
      headers: _authed(),
    );
    _check(r);
  }

  /// Fetches a file's bytes with the current bearer.
  Future<List<int>> downloadFileBytes(String downloadUrl) async {
    final r = await _http.get(Uri.parse(downloadUrl), headers: _authed());
    _check(r);
    return r.bodyBytes;
  }

  void close() => _http.close();

  void _check(http.Response r) {
    if (r.statusCode >= 400) {
      throw RainbowRestException(r.statusCode, r.body);
    }
  }
}
