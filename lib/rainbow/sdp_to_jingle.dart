import 'package:xml/xml.dart';

/// Minimal SDP ↔ Jingle codec used for M-3 loopback calling.
///
/// XEP-0166 says a Jingle `<jingle>` element contains one or more
/// `<content>` children, each with a `<description>` (media) and a
/// `<transport>` (candidates). XEP-0167 spells out a full mapping
/// between SDP `m=`/`a=` lines and Jingle child elements — that
/// mapping is genuinely fiddly, so for M-3 we take a shortcut: raw
/// SDP travels in a custom `urn:rainbow:jingle:sdp:1` element inside
/// the `<content>`. The outer XEP-0166 shape is preserved so a real
/// server can still route by `sid`/`action`; only the inner payload
/// is proprietary. M-6+ or a real-server integration will replace
/// this with a proper XEP-0167 encoder.
class JingleSdpCodec {
  static const String rainbowSdpNs = 'urn:rainbow:jingle:sdp:1';

  /// Builds the `<content>` XML string that goes inside `<jingle>`
  /// for a `session-initiate` or `session-accept`.
  static String encodeContentWithSdp({required String sdp}) {
    final safe = _cdata(sdp);
    return '<content name="rtp" creator="initiator">'
        '<rainbow-sdp xmlns="$rainbowSdpNs">'
        '<![CDATA[$safe]]>'
        '</rainbow-sdp>'
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
  static String? decodeSdp(String jingleXml) {
    final doc = XmlDocument.parse(jingleXml);
    final sdp = doc.rootElement.findAllElements(
      'rainbow-sdp',
      namespace: rainbowSdpNs,
    );
    if (sdp.isEmpty) return null;
    return sdp.first.innerText;
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

  // XML doesn't allow "]]>" inside a CDATA section. Split it if the
  // SDP ever contains that sequence (SDP won't in practice, but the
  // guard costs nothing).
  static String _cdata(String s) => s.replaceAll(']]>', ']]]]><![CDATA[>');

  static String _attr(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
