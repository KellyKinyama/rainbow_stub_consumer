import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.wsUrl,
    required this.appAuth,
    required this.xmppDomain,
    this.iceServers = const [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  });

  final Uri baseUrl;
  final Uri wsUrl;
  final String appAuth;
  final String xmppDomain;

  /// WebRTC ICE server list in the shape `flutter_webrtc` expects.
  /// Default: Google's public STUN. TURN can be added by callers when
  /// available (see docs/webrtc-roadmap.md M-7).
  final List<Map<String, dynamic>> iceServers;

  /// Default dev config — targets a local rainbow-stub on :8443.
  /// On the Android emulator swap `localhost` for `10.0.2.2`.
  static AppConfig get dev {
    final scheme = _defaultScheme();
    final host = _defaultHost();
    return AppConfig(
      baseUrl: Uri.parse('$scheme://$host:8443'),
      wsUrl: Uri.parse(
        '${scheme == 'https' ? 'wss' : 'ws'}://$host:8443/websocket',
      ),
      // Matches the appId/secret shipped with the RN sample and seeded on
      // the stub.
      appAuth:
          'Basic NjVjNjgxYzAxYzhmMTFlOWFkZDg5MzJiMzU4ZWY4MWQ6VVlkdTN3Q1hUZGZ5akltaFVSbklrWjB0YWM1SjlYU0xzeklLQlJVVVdWQjM1YjZuVDNmV1YyQmhBR2hvamRCUQ==',
      xmppDomain: host,
    );
  }

  static String _defaultScheme() {
    // Web builds must use the same scheme as the page; keep https to match
    // the stub's TLS default.
    return kIsWeb ? 'https' : 'https';
  }

  static String _defaultHost() {
    if (kIsWeb) return 'localhost';
    // TargetPlatform.android would be 10.0.2.2 — we can't tell without a
    // dart:io check, but callers on Android should override via
    // AppConfig(...).
    return 'localhost';
  }
}
