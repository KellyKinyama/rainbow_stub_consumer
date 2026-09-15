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
    this.sfuUrl,
  });

  final Uri baseUrl;
  final Uri wsUrl;
  final String appAuth;
  final String xmppDomain;

  /// WebRTC ICE server list in the shape `flutter_webrtc` expects.
  /// Default: Google's public STUN. TURN can be added by callers when
  /// available (see docs/webrtc-roadmap.md M-7).
  final List<Map<String, dynamic>> iceServers;

  /// Optional ion-sfu (or compatible) JSON-RPC 2.0 WebSocket endpoint
  /// used for group / MUC calls. When null, group calling is disabled
  /// in the UI. Typical dev value: `ws://localhost:7000/ws`.
  final Uri? sfuUrl;

  /// True when the app has been configured with an SFU endpoint —
  /// group-call UI checks this before showing "Start / Join call"
  /// controls on bubbles.
  bool get groupCallsEnabled => sfuUrl != null;

  /// Default dev config — targets a local rainbow-stub. Endpoints can
  /// be overridden at build time via `--dart-define` flags so real
  /// devices can point at the LAN without touching source:
  ///
  /// ```sh
  /// flutter run \
  ///   --dart-define=STUB_SCHEME=http \
  ///   --dart-define=STUB_HOST=192.168.1.42 \
  ///   --dart-define=STUB_PORT=8080 \
  ///   --dart-define=SFU_URL=ws://192.168.1.42:7000/ws
  /// ```
  ///
  /// See `docs/live-smoke-test.md` for the full runbook.
  static AppConfig get dev {
    final scheme = _defaultScheme();
    final host = _defaultHost();
    final port = _defaultPort();
    final sfu = const String.fromEnvironment('SFU_URL');
    return AppConfig(
      baseUrl: Uri.parse('$scheme://$host:$port'),
      wsUrl: Uri.parse(
        '${scheme == 'https' ? 'wss' : 'ws'}://$host:$port/websocket',
      ),
      // Matches the appId/secret shipped with the RN sample and seeded on
      // the stub.
      appAuth:
          'Basic NjVjNjgxYzAxYzhmMTFlOWFkZDg5MzJiMzU4ZWY4MWQ6VVlkdTN3Q1hUZGZ5akltaFVSbklrWjB0YWM1SjlYU0xzeklLQlJVVVdWQjM1YjZuVDNmV1YyQmhBR2hvamRCUQ==',
      xmppDomain: _defaultXmppDomain(host),
      sfuUrl: sfu.isEmpty ? null : Uri.parse(sfu),
    );
  }

  static String _defaultScheme() {
    const override = String.fromEnvironment('STUB_SCHEME');
    if (override.isNotEmpty) return override;
    return 'http';
  }

  static String _defaultHost() {
    const override = String.fromEnvironment('STUB_HOST');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'localhost';
    // TargetPlatform.android would be 10.0.2.2 — we can't tell without a
    // dart:io check, but callers on Android should override via
    // --dart-define=STUB_HOST=... (see docs/live-smoke-test.md).
    return 'localhost';
  }

  static String _defaultPort() {
    const override = String.fromEnvironment('STUB_PORT');
    if (override.isNotEmpty) return override;
    return '8443';
  }

  // The XMPP domain can differ from the HTTP host: on the Android
  // emulator the host is 10.0.2.2 but the stub's JID domain is localhost.
  static String _defaultXmppDomain(String host) {
    const override = String.fromEnvironment('XMPP_DOMAIN');
    if (override.isNotEmpty) return override;
    return host;
  }
}
