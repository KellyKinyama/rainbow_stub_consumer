import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// Chrome throttles Web Audio API contexts in background tabs, so a
// `Timer.periodic` + `AudioContext` beep loop goes silent when the
// callee tab isn't focused. HTMLAudioElement, on the other hand, keeps
// playing across tab-focus changes — hand-roll a tiny WAV of one
// beep-then-silence period and loop it.
web.HTMLAudioElement? _audio;

void platformStartWebRing() {
  if (_audio != null) return;
  final el = web.HTMLAudioElement()
    ..src = _ringtoneDataUrl
    ..loop = true;
  _audio = el;
  // Fire-and-forget: play() returns a Promise. If autoplay is blocked
  // (user hasn't interacted with the page yet) the element stays
  // primed and will play as soon as we manually trigger a gesture.
  el.play();
}

void platformStopWebRing() {
  final el = _audio;
  _audio = null;
  if (el != null) {
    el.pause();
    el.src = '';
  }
}

/// A 1.5 s beep-then-silence WAV, ready to be assigned as an
/// `<audio>` src. Computed once and cached — the buffer is a few kB.
final String _ringtoneDataUrl = () {
  const sampleRate = 8000;
  const beepMs = 400;
  const silenceMs = 1100;
  const beepFreq = 480.0;
  const beepAmplitude = 0.35;
  const totalMs = beepMs + silenceMs;
  const totalSamples = sampleRate * totalMs ~/ 1000;
  const beepSamples = sampleRate * beepMs ~/ 1000;

  final samples = Int16List(totalSamples);
  for (var i = 0; i < beepSamples; i++) {
    final t = i / sampleRate;
    // Short attack + release ramps kill the "click" at the edges.
    final ramp = math.min(1.0, math.min(i, beepSamples - i) / 40.0);
    final s = math.sin(2 * math.pi * beepFreq * t) * beepAmplitude * ramp;
    samples[i] = (s * 32767).round();
  }

  final pcmBytes = samples.buffer.asUint8List();
  final dataSize = pcmBytes.length;
  final riffSize = 36 + dataSize;
  final header = BytesBuilder()
    ..add(ascii.encode('RIFF'))
    ..add(_u32le(riffSize))
    ..add(ascii.encode('WAVE'))
    ..add(ascii.encode('fmt '))
    ..add(_u32le(16))
    ..add(_u16le(1)) // PCM
    ..add(_u16le(1)) // mono
    ..add(_u32le(sampleRate))
    ..add(_u32le(sampleRate * 2)) // byte rate
    ..add(_u16le(2)) // block align
    ..add(_u16le(16)) // bits/sample
    ..add(ascii.encode('data'))
    ..add(_u32le(dataSize))
    ..add(pcmBytes);
  return 'data:audio/wav;base64,${base64.encode(header.toBytes())}';
}();

List<int> _u32le(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

List<int> _u16le(int v) => [v & 0xff, (v >> 8) & 0xff];
