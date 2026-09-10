import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';

/// JSON-RPC 2.0 client for the ion-sfu group SFU signaling protocol.
///
/// The wire shape is documented at
/// https://github.com/pion/ion-sfu/blob/master/docs/json-rpc.md.
/// We speak the two operations that a browser / mobile client needs
/// to publish + subscribe in a room:
///
///   client → SFU  method="join"     params={ sid, uid, offer }
///   client ← SFU  result={ answer }
///   client ↔ SFU  method="offer"    params={ sid, offer } (either side)
///   client ↔ SFU  method="answer"   params={ sid, answer } (either side)
///   client ↔ SFU  method="trickle"  params={ sid, candidate, target }
///
/// Higher-level session lifecycle (create RTCPeerConnection, connect
/// tracks, subscribe to remote streams) lives in `sfu_group_call.dart`
/// so this file remains pure protocol.
abstract class SfuSignaling {
  /// Fires whenever the SFU pushes a message that isn't the response
  /// to one of our outgoing method calls.
  Stream<SfuServerMessage> get messages;

  /// Joins a session ([sid]) as user [uid], publishing [offerSdp].
  /// Returns the SFU's answer SDP.
  Future<String> join({
    required String sid,
    required String uid,
    required String offerSdp,
  });

  /// Sends a fresh renegotiation offer for our publisher connection.
  Future<String> sendOffer({required String sid, required String offerSdp});

  /// Sends an answer in response to an SFU-initiated offer (e.g. when
  /// new remote streams are added to the room).
  Future<void> sendAnswer({required String sid, required String answerSdp});

  /// Trickles a local ICE candidate. [target] is 0 for the publisher
  /// (client → SFU) peer connection and 1 for the subscriber
  /// (SFU → client) connection.
  Future<void> sendTrickle({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    required int target,
  });

  /// Closes the transport.
  Future<void> close();
}

/// One inbound message from the SFU. Only the two variants a caller
/// actually reacts to are modelled — everything else is ignored.
sealed class SfuServerMessage {
  const SfuServerMessage();
}

/// SFU-initiated renegotiation. The client should apply [sdp] as the
/// remote description on its subscriber peer connection and reply with
/// a fresh answer via [SfuSignaling.sendAnswer].
class SfuOfferFromServer extends SfuServerMessage {
  const SfuOfferFromServer(this.sdp);
  final String sdp;
}

/// SFU-relayed remote ICE candidate for a specific peer connection.
class SfuTrickleFromServer extends SfuServerMessage {
  const SfuTrickleFromServer({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
    required this.target,
  });
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  final int target;
}

/// Concrete [SfuSignaling] over a WebSocket, speaking JSON-RPC 2.0.
class JsonRpcSfuSignaling implements SfuSignaling {
  JsonRpcSfuSignaling(this._channel) {
    _sub = _channel.stream.listen(_onFrame, onDone: _onDone, onError: _onError);
  }

  /// Accepts a `WebSocketChannel` (which is a `StreamChannel<dynamic>`)
  /// or any other bidirectional channel — tests inject an in-memory
  /// pair.
  final StreamChannel<dynamic> _channel;
  late final StreamSubscription _sub;
  final _messages = StreamController<SfuServerMessage>.broadcast();
  final _pending = <int, Completer<Object?>>{};
  int _nextId = 1;
  bool _closed = false;

  @override
  Stream<SfuServerMessage> get messages => _messages.stream;

  Future<Object?> _call(String method, Map<String, Object?> params) {
    if (_closed) {
      throw StateError('SfuSignaling closed');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _channel.sink.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future;
  }

  void _notify(String method, Map<String, Object?> params) {
    if (_closed) return;
    _channel.sink.add(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
  }

  void _onFrame(dynamic raw) {
    final text = raw is List<int> ? utf8.decode(raw) : raw as String;
    final Map<String, Object?> msg;
    try {
      msg = jsonDecode(text) as Map<String, Object?>;
    } on FormatException {
      return;
    }
    // Response to one of our calls.
    if (msg.containsKey('id') && (msg.containsKey('result') || msg.containsKey('error'))) {
      final id = (msg['id'] as num).toInt();
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = msg['error'];
      if (error != null) {
        completer.completeError(Exception('SFU error: $error'));
      } else {
        completer.complete(msg['result']);
      }
      return;
    }
    // SFU-pushed notification.
    final method = msg['method'] as String?;
    if (method == null) return;
    final params = (msg['params'] as Map<String, Object?>?) ?? const {};
    switch (method) {
      case 'offer':
        final sdp = params['sdp'] as String?;
        if (sdp != null) _messages.add(SfuOfferFromServer(sdp));
      case 'trickle':
        final candidate = params['candidate'];
        if (candidate is Map<String, Object?>) {
          final line = candidate['candidate'] as String?;
          if (line == null) break;
          _messages.add(
            SfuTrickleFromServer(
              candidate: line,
              sdpMid: candidate['sdpMid'] as String?,
              sdpMLineIndex: (candidate['sdpMLineIndex'] as num?)?.toInt(),
              target: (params['target'] as num?)?.toInt() ?? 0,
            ),
          );
        }
    }
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('SFU socket closed'));
    }
    _pending.clear();
    if (!_messages.isClosed) _messages.close();
  }

  void _onError(Object e) {
    if (_closed) return;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(e);
    }
    _pending.clear();
    if (!_messages.isClosed) _messages.addError(e);
  }

  @override
  Future<String> join({
    required String sid,
    required String uid,
    required String offerSdp,
  }) async {
    final result = await _call('join', {
      'sid': sid,
      'uid': uid,
      'offer': {'type': 'offer', 'sdp': offerSdp},
    });
    if (result is! Map<String, Object?>) {
      throw StateError('SFU join returned unexpected shape: $result');
    }
    final sdp = result['sdp'] as String?;
    if (sdp == null) throw StateError('SFU join answer missing sdp');
    return sdp;
  }

  @override
  Future<String> sendOffer({required String sid, required String offerSdp}) async {
    final result = await _call('offer', {
      'sid': sid,
      'desc': {'type': 'offer', 'sdp': offerSdp},
    });
    if (result is! Map<String, Object?>) {
      throw StateError('SFU offer returned unexpected shape: $result');
    }
    final sdp = result['sdp'] as String?;
    if (sdp == null) throw StateError('SFU offer answer missing sdp');
    return sdp;
  }

  @override
  Future<void> sendAnswer({required String sid, required String answerSdp}) async {
    _notify('answer', {
      'sid': sid,
      'desc': {'type': 'answer', 'sdp': answerSdp},
    });
  }

  @override
  Future<void> sendTrickle({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    required int target,
  }) async {
    _notify('trickle', {
      'target': target,
      'candidate': {
        'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      },
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    // sink.close() on some StreamChannel implementations awaits the
    // remote peer's ack; don't block the caller on that. Fire-and-
    // forget is fine because we've already cancelled our reader and
    // told local callers we're closed.
    unawaited(Future(() async {
      try {
        await _channel.sink.close();
      } catch (_) {}
    }));
    if (!_messages.isClosed) await _messages.close();
  }
}
