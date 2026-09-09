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

  Future<void> setPresence(String userId, String show, {String? status}) async {
    final r = await _http.post(
      _u('/api/rainbow/enduser/v1.0/users/$userId/presences'),
      headers: _authed(contentType: 'application/json'),
      body: jsonEncode({'show': show, if (status != null) 'status': status}),
    );
    _check(r);
  }

  void close() => _http.close();

  void _check(http.Response r) {
    if (r.statusCode >= 400) {
      throw RainbowRestException(r.statusCode, r.body);
    }
  }
}
