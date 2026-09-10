import 'dart:async';

import 'package:flutter/widgets.dart' show AsyncSnapshot, ConnectionState;
import 'package:rearch/rearch.dart';

import '../../rainbow/webrtc_adapter.dart';
import '../../rainbow/webrtc_adapter_impl.dart';
import 'config_capsule.dart';

/// App-wide singleton [WebRtcAdapter] backed by `flutter_webrtc`. The
/// ICE server list comes from [AppConfig.iceServers].
///
/// Tests override this via `container.mock(webRtcAdapterCapsule)`.
WebRtcAdapter webRtcAdapterCapsule(CapsuleHandle use) {
  final config = use(configCapsule);
  return FlutterWebRtcAdapter(iceServers: config.iceServers);
}

/// Snapshot of a single call, exposed to the UI. Mutations happen via
/// [CallController].
class CallSnapshot {
  const CallSnapshot({
    required this.sid,
    required this.direction,
    required this.state,
  });
  final String sid;
  final CallDirection direction;
  final CallState state;

  CallSnapshot copyWith({CallState? state}) => CallSnapshot(
    sid: sid,
    direction: direction,
    state: state ?? this.state,
  );
}

/// Handle over an active [RtcSession] — the capsule owns the actual
/// session, this is what the UI drives. `close()` is fire-and-forget;
/// the capsule's cleanup takes care of the session lifecycle.
class CallController {
  CallController({
    required this.snapshot,
    required this.session,
    required this.dispose,
  });
  final CallSnapshot snapshot;
  final RtcSession session;
  final Future<void> Function() dispose;
}

/// Family capsule keyed by Jingle sid. Constructs a peer connection
/// via the adapter, translates its [RtcSession.events] into a
/// [CallSnapshot] state slot, and disposes the session when the
/// capsule is dropped.
///
/// M-2 wires the lifecycle only — no Jingle iq is emitted yet
/// (that arrives in M-3). Local ICE candidates and connection state
/// transitions are still exposed so the M-2 acceptance test can drive
/// them from a fake adapter.
final Map<String, Capsule<AsyncSnapshot<CallController>>> _callCache = {};

Capsule<AsyncSnapshot<CallController>> callCapsule({
  required String sid,
  required CallDirection direction,
}) {
  final key = '$sid|${direction.name}';
  return _callCache.putIfAbsent(key, () {
    return (CapsuleHandle use) {
      final adapter = use(webRtcAdapterCapsule);
      final result = use.data<AsyncSnapshot<CallController>>(
        const AsyncSnapshot<CallController>.waiting(),
      );

      use.effect(() {
        RtcSession? session;
        StreamSubscription<RtcSessionEvent>? sub;
        var disposed = false;

        Future<void> dispose() async {
          if (disposed) return;
          disposed = true;
          await sub?.cancel();
          await session?.close();
          _callCache.remove(key);
        }

        unawaited(() async {
          try {
            final s = await adapter.createSession(direction: direction);
            if (disposed) {
              await s.close();
              return;
            }
            session = s;
            var snap = CallSnapshot(
              sid: sid,
              direction: direction,
              state: s.state,
            );
            void publish(CallSnapshot next) {
              snap = next;
              result.value = AsyncSnapshot<CallController>.withData(
                ConnectionState.active,
                CallController(
                  snapshot: next,
                  session: s,
                  dispose: dispose,
                ),
              );
            }

            publish(snap);
            sub = s.events.listen((e) {
              if (e is RtcStateChanged) {
                publish(snap.copyWith(state: e.state));
              }
            });
          } on Object catch (e, st) {
            result.value = AsyncSnapshot<CallController>.withError(
              ConnectionState.done,
              e,
              st,
            );
          }
        }());

        return () => unawaited(dispose());
      }, [adapter, sid, direction]);

      return result.value;
    };
  });
}

/// Clears any cached family capsules so the next test starts fresh.
void resetCallCapsuleCache() => _callCache.clear();
