import 'dart:convert';

import 'package:xml/xml.dart';

/// Minimal SDP ↔ Jingle codec used for M-3 loopback calling.
///
/// XEP-0166 says a Jingle `<jingle>` element contains one or more
/// `<content>` children, each with a `<description>` (media) and a
/// `<transport>` (candidates). XEP-0167 spells out a full mapping
/// between SDP `m=`/`a=` lines and Jingle child elements — that
/// mapping is genuinely fiddly, so for M-3 we take a shortcut: base64-
/// encoded SDP travels in a custom `urn:rainbow:jingle:sdp:1` element
/// inside the `<content>`. The outer XEP-0166 shape is preserved so a
/// real server can still route by `sid`/`action`; only the inner
/// payload is proprietary. M-6+ or a real-server integration will
/// replace this with a proper XEP-0167 encoder.
///
/// Historically the SDP travelled inside a CDATA section; that broke
/// on Flutter web (dart2js + `xml` package throw
/// `LegacyJavaScriptObject is not a subtype of XmlNode` inside
/// `visitCDATAEvent`). Base64 sidesteps the CDATA path entirely and
/// keeps the wire ASCII-clean.
class JingleSdpCodec {
  static const String rainbowSdpNs = 'urn:rainbow:jingle:sdp:1';

  /// Builds the `<content>` XML string that goes inside `<jingle>`
  /// for a `session-initiate` or `session-accept`.
  static String encodeContentWithSdp({required String sdp}) {
    final b64 = base64.encode(utf8.encode(sdp));
    return '<content name="rtp" creator="initiator">'
        '<rainbow-sdp xmlns="$rainbowSdpNs" enc="b64">$b64</rainbow-sdp>'
        '</content>';
  }

  /// Builds the `<content>` XML for a `transport-info`. [candidate] is
  /// the raw SDP candidate line (`candidate:…`).
  static String encodeCandidateContent({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) {
    final mid = sdpMid == null ? '' : ' sdp-mid="${_attr(sdpMid)}"';
    final idx = sdpMLineIndex == null
        ? ''
        : ' sdp-m-line-index="$sdpMLineIndex"';
    return '<content name="rtp" creator="initiator">'
        '<rainbow-candidate xmlns="$rainbowSdpNs" '
        'line="${_attr(candidate)}"$mid$idx/>'
        '</content>';
  }

  /// Extracts the raw SDP from the peer's `<jingle>` payload
  /// (delivered as a full XML string on [XmppJingle.jingleXml]).
  /// Returns `null` if no `<rainbow-sdp>` element is present.
  ///
  /// Accepts both current base64-encoded (`enc="b64"`) and legacy
  /// CDATA-wrapped payloads so a client running old code can still
  /// hand off to a client running new code.
  static String? decodeSdp(String jingleXml) {
    final doc = XmlDocument.parse(jingleXml);
    final sdp = doc.rootElement.findAllElements(
      'rainbow-sdp',
      namespace: rainbowSdpNs,
    );
    if (sdp.isEmpty) return null;
    final el = sdp.first;
    final enc = el.getAttribute('enc');
    final text = el.innerText;
    if (enc == 'b64') {
      try {
        return utf8.decode(base64.decode(text.trim()));
      } on FormatException {
        return null;
      }
    }
    return text;
  }

  /// Extracts a candidate from a `transport-info` `<jingle>` payload.
  static ({String candidate, String? sdpMid, int? sdpMLineIndex})?
  decodeCandidate(String jingleXml) {
    final doc = XmlDocument.parse(jingleXml);
    final el = doc.rootElement.findAllElements(
      'rainbow-candidate',
      namespace: rainbowSdpNs,
    );
    if (el.isEmpty) return null;
    final line = el.first.getAttribute('line');
    if (line == null) return null;
    final mid = el.first.getAttribute('sdp-mid');
    final idxRaw = el.first.getAttribute('sdp-m-line-index');
    final idx = idxRaw == null ? null : int.tryParse(idxRaw);
    return (candidate: line, sdpMid: mid, sdpMLineIndex: idx);
  }

  static String _attr(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
