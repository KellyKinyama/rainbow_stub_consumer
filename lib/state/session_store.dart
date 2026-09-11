import 'package:shared_preferences/shared_preferences.dart';

/// Persisted snapshot of the last signed-in session. Written on
/// [AuthController.signIn] success and cleared on
/// [AuthController.signOut]. Read once at app boot to attempt a
/// silent re-authentication.
class StoredSession {
  const StoredSession({
    required this.email,
    required this.token,
    required this.userId,
  });
  final String email;
  final String token;
  final String userId;
}

abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession s);
  Future<void> clear();
}

class SharedPrefsSessionStore implements SessionStore {
  const SharedPrefsSessionStore();

  static const _kEmail = 'session.email';
  static const _kToken = 'session.token';
  static const _kUserId = 'session.userId';

  @override
  Future<StoredSession?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_kEmail);
      final token = prefs.getString(_kToken);
      final userId = prefs.getString(_kUserId);
      if (email == null || token == null || userId == null) return null;
      return StoredSession(email: email, token: token, userId: userId);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(StoredSession s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEmail, s.email);
      await prefs.setString(_kToken, s.token);
      await prefs.setString(_kUserId, s.userId);
    } on Object {
      // ignore
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kEmail);
      await prefs.remove(_kToken);
      await prefs.remove(_kUserId);
    } on Object {
      // ignore
    }
  }
}

/// No-op used by tests where the flutter binding isn't initialised.
class NoOpSessionStore implements SessionStore {
  const NoOpSessionStore();
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession s) async {}
  @override
  Future<void> clear() async {}
}
