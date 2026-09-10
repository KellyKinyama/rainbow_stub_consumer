// Diagnostic overlay reads a few counters that are marked
// @visibleForTesting on the XMPP client — this is a dev-only surface
// so the lint doesn't apply.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/xmpp_client.dart';
import '../state/capsules/call_manager_capsule.dart';
import '../state/capsules/config_capsule.dart';
import '../state/capsules/group_call_capsule.dart';
import '../state/capsules/push_capsule.dart';
import '../state/capsules/xmpp_capsule.dart';

/// Draggable, semi-transparent panel that surfaces the live state of
/// the XMPP transport, XEP-0198 counters, push registration, and any
/// active WebRTC sessions.
///
/// Only rendered in debug mode — the caller should gate it on
/// `kDebugMode` (or a config toggle) before mounting. Long-press to
/// hide.
class DiagnosticsOverlay extends RearchConsumer {
  const DiagnosticsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetHandle use) {
    final xmpp = use(xmppCapsule);
    final config = use(configCapsule);
    final push = use(pushCapsule);
    final callManager = use(callManagerCapsule);
    final groupCallManager = use(groupCallManagerCapsule);
    final (visible, setVisible) = use.state<bool>(true);
    final (offset, setOffset) = use.state<Offset>(const Offset(12, 96));

    // Force a rebuild every second so hOut / hIn tick.
    final (tick, setTick) = use.state<int>(0);
    use.effect(() {
      final t = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setTick(tick + 1),
      );
      return t.cancel;
    }, const []);

    if (!visible) {
      return Positioned(
        left: offset.dx,
        top: offset.dy,
        child: GestureDetector(
          onTap: () => setVisible(true),
          child: Material(
            color: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.bug_report, size: 18, color: Colors.white70),
            ),
          ),
        ),
      );
    }
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setOffset(offset + d.delta),
        onLongPress: () => setVisible(false),
        child: Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DIAG · ${xmpp.isConnected ? 'XMPP OK' : 'XMPP DOWN'}',
                    style: TextStyle(
                      color: xmpp.isConnected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('jid  ${_shorten(xmpp.fullJid)}'),
                  Text(
                    'sm   enabled=${xmpp.debugSm}  '
                    'hOut=${xmpp.debugHOut}  hIn=${xmpp.debugHIn}  '
                    'pending=${xmpp.debugPendingAckCount}',
                  ),
                  Text('rest ${config.baseUrl}'),
                  Text(
                    'sfu  ${config.sfuUrl?.toString() ?? '<off>'}  '
                    '${groupCallManager.joinedCalls.isEmpty ? 'idle' : '${groupCallManager.joinedCalls.length} joined'}',
                  ),
                  Text(
                    'push ${push.status.name}${push.token == null ? '' : ' · ${push.token!.substring(0, 6)}…'}',
                  ),
                  if (callManager.calls.isNotEmpty)
                    Text(
                      'p2p  ${callManager.calls.length} call(s) · '
                      '${callManager.activeCall?.state.name ?? '-'}',
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'drag · long-press to hide',
                    style: TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _shorten(String jid) {
    if (jid.length <= 32) return jid;
    return '${jid.substring(0, 30)}…';
  }
}

extension _XmppDiag on RainbowXmppClient {
  /// True when XEP-0198 stream management has been negotiated.
  bool get debugSm => debugPendingAckCount > 0 || debugHOut > 0;
}
