// Phase M-8 acceptance — ion-sfu JSON-RPC signaling protocol.
// Drives JsonRpcSfuSignaling against an in-memory StreamChannel pair
// and verifies the wire shape matches
// https://github.com/pion/ion-sfu/blob/master/docs/json-rpc.md.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/sfu_signaling.dart';
import 'package:stream_channel/stream_channel.dart';

/// Bidirectional in-memory pipe. [clientChannel] is what
/// [JsonRpcSfuSignaling] talks over; [feedFromServer] pushes JSON
/// frames as if they came from the SFU; [outboundJson] observes
/// everything the client sent.
class _Pipe {
  _Pipe() {
    final clientToServer = StreamController<dynamic>();
    final serverToClient = StreamController<dynamic>();
    clientChannel = StreamChannel<dynamic>(
      serverToClient.stream,
      clientToServer.sink,
    );
    _serverIn = clientToServer.stream;
    _serverOut = serverToClient.sink;
  }

  late final StreamChannel<dynamic> clientChannel;
  late final Stream<dynamic> _serverIn;
  late final StreamSink<dynamic> _serverOut;

  Stream<Map<String, Object?>> get outboundJson =>
      _serverIn.map((v) => jsonDecode(v as String) as Map<String, Object?>);

  void feedFromServer(Map<String, Object?> frame) =>
      _serverOut.add(jsonEncode(frame));

  Future<void> serverClose() => _serverOut.close();
}

void main() {
  test('join sends jsonrpc join and unwraps the answer sdp', () async {
    final pipe = _Pipe();
    final sig = JsonRpcSfuSignaling(pipe.clientChannel);

    final outbound = pipe.outboundJson.take(1).toList();
    final join = sig.join(sid: 'room-1', uid: 'alice', offerSdp: 'v=0-offer\n');

    final sent = (await outbound).first;
    expect(sent['jsonrpc'], '2.0');
    expect(sent['method'], 'join');
    expect(sent['id'], 1);
    final params = sent['params'] as Map<String, Object?>;
    expect(params['sid'], 'room-1');
    expect(params['uid'], 'alice');
    expect((params['offer'] as Map)['sdp'], 'v=0-offer\n');

    pipe.feedFromServer({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {'type': 'answer', 'sdp': 'v=0-answer\n'},
    });

    final answer = await join.timeout(const Duration(seconds: 1));
    expect(answer, 'v=0-answer\n');

    await sig.close();
  });

  test('sendOffer/sendAnswer/sendTrickle serialise correctly', () async {
    final pipe = _Pipe();
    final sig = JsonRpcSfuSignaling(pipe.clientChannel);
    final frames = <Map<String, Object?>>[];
    final capture = pipe.outboundJson.listen(frames.add);

    final offerCall = sig.sendOffer(sid: 's', offerSdp: 'o\n');
    await Future<void>.delayed(Duration.zero);
    pipe.feedFromServer({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {'type': 'answer', 'sdp': 'a\n'},
    });
    expect(await offerCall, 'a\n');

    await sig.sendAnswer(sid: 's', answerSdp: 'ans\n');
    await sig.sendTrickle(
      candidate: 'candidate:1 1 udp 1 10.0.0.1 55555 typ host',
      sdpMid: 'audio',
      sdpMLineIndex: 0,
      target: 1,
    );
    await Future<void>.delayed(Duration.zero);

    expect(frames, hasLength(3));
    expect(frames[0]['method'], 'offer');
    expect(frames[1]['method'], 'answer');
    expect((frames[1]['params'] as Map)['sid'], 's');
    expect(frames[2]['method'], 'trickle');
    final trickleParams = frames[2]['params'] as Map<String, Object?>;
    expect(trickleParams['target'], 1);
    final cand = trickleParams['candidate'] as Map<String, Object?>;
    expect(cand['candidate'], contains('10.0.0.1'));
    expect(cand['sdpMid'], 'audio');
    expect(cand['sdpMLineIndex'], 0);

    await capture.cancel();
    await sig.close();
  });

  test('SFU-initiated offer surfaces as SfuOfferFromServer', () async {
    final pipe = _Pipe();
    final sig = JsonRpcSfuSignaling(pipe.clientChannel);
    final received = <SfuServerMessage>[];
    final sub = sig.messages.listen(received.add);

    pipe.feedFromServer({
      'jsonrpc': '2.0',
      'method': 'offer',
      'params': {'sdp': 'v=0-server-offer\n'},
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(received, hasLength(1));
    expect(received.first, isA<SfuOfferFromServer>());
    expect((received.first as SfuOfferFromServer).sdp, 'v=0-server-offer\n');
    await sub.cancel();
    await sig.close();
  });

  test('SFU trickle notification surfaces as SfuTrickleFromServer', () async {
    final pipe = _Pipe();
    final sig = JsonRpcSfuSignaling(pipe.clientChannel);
    final received = <SfuServerMessage>[];
    final sub = sig.messages.listen(received.add);

    pipe.feedFromServer({
      'jsonrpc': '2.0',
      'method': 'trickle',
      'params': {
        'target': 1,
        'candidate': {
          'candidate': 'candidate:9 1 udp 2 172.16.0.5 44444 typ srflx',
          'sdpMid': 'audio',
          'sdpMLineIndex': 0,
        },
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(received, hasLength(1));
    final t = received.first as SfuTrickleFromServer;
    expect(t.candidate, contains('172.16.0.5'));
    expect(t.target, 1);
    expect(t.sdpMid, 'audio');
    expect(t.sdpMLineIndex, 0);
    await sub.cancel();
    await sig.close();
  });

  test(
    'error response completes the pending future with an exception',
    () async {
      final pipe = _Pipe();
      final sig = JsonRpcSfuSignaling(pipe.clientChannel);
      final capture = pipe.outboundJson.take(1).toList();

      final future = sig.join(sid: 's', uid: 'u', offerSdp: 'o');
      await capture;

      pipe.feedFromServer({
        'jsonrpc': '2.0',
        'id': 1,
        'error': {'code': -32000, 'message': 'room full'},
      });

      await expectLater(future, throwsA(isA<Exception>()));
      await sig.close();
    },
  );

  test('socket close aborts pending calls', () async {
    final pipe = _Pipe();
    final sig = JsonRpcSfuSignaling(pipe.clientChannel);

    final future = sig.join(sid: 's', uid: 'u', offerSdp: 'o');
    await Future<void>.delayed(Duration.zero);
    await pipe.serverClose();

    await expectLater(future, throwsA(isA<StateError>()));
  });
}
