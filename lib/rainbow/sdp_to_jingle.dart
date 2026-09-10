import 'package:xml/xml.dart';

/// Pragmatic Jingle content-XML codec.
///
/// The M-3 loopback demo tunnels a full SDP blob inside a
/// `<description>` element rather than mapping every SDP line to a
/// XEP-0167 element. That keeps this phase small and lets us round-
/// trip anything `flutter_webrtc` produces (Opus, VP8, DTLS-SRTP,
/// bundle groups, etc.) without a large mapping table. The trade-off
/// is that the stub is no longer wire-compatible with real Rainbow or
/// ejabberd — but the roadmap only promises loopback / dev-network
/// interop for M-3. A future phase can swap this out for a proper
/// XEP-0167 mapper.
class SdpToJingle {
  /// Builds a Jingle content element wrapping [sdp] inside a
  /// `<description>/<sdp>` pair, plus an empty ICE-UDP transport.
  static String encode({
    required String sdp,
    required String contentName,
    required String creator,
    required String media,
  }) {
    final desc = XmlElement(XmlName('description'), [
      XmlAttribute(XmlName('xmlns'), 'urn:xmpp:jingle:apps:rtp:1'),
      XmlAttribute(XmlName('media'), media),
    ], [
      XmlElement(XmlName('sdp'), const [], [XmlText(sdp)]),
    ]);
    final transport = XmlElement(XmlName('transport'), [
      XmlAttribute(XmlName('xmlns'), 'urn:xmpp:jingle:transports:ice-udp:1'),
    ]);
    final content = XmlElement(XmlName('content'), [
      XmlAttribute(XmlName('name'), contentName),
      XmlAttribute(XmlName('creator'), creator),
    ], [desc, transport]);
    return content.toXmlString();
  }

  /// Extracts the tunnelled SDP from the first content/description/sdp
  /// nesting in [jingleXml]. Accepts either a full jingle payload or a
  /// bare content element. Returns `null` if the payload isn't in the
  /// expected shape.
  static String? decode(String jingleXml) {
    XmlElement root;
    try {
      root = XmlDocument.parse(jingleXml).rootElement;
    } on XmlException {
      return null;
    }
    final contents = root.name.local == 'content'
        ? [root]
        : _childrenNamed(root, 'content');
    for (final content in contents) {
      for (final desc in _childrenNamed(content, 'description')) {
        for (final sdp in _childrenNamed(desc, 'sdp')) {
          return sdp.innerText;
        }
      }
    }
    return null;
  }

  /// Builds a transport element with a single candidate line and
  /// wraps it in a content element. Trickle-friendly.
  static String encodeCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    String contentName = 'audio',
  }) {
    final cand = XmlElement(XmlName('candidate'), [
      XmlAttribute(XmlName('sdp'), candidate),
      if (sdpMid != null) XmlAttribute(XmlName('sdpMid'), sdpMid),
      if (sdpMLineIndex != null)
        XmlAttribute(XmlName('sdpMLineIndex'), '$sdpMLineIndex'),
    ]);
    final transport = XmlElement(XmlName('transport'), [
      XmlAttribute(XmlName('xmlns'), 'urn:xmpp:jingle:transports:ice-udp:1'),
    ], [cand]);
    final content = XmlElement(XmlName('content'), [
      XmlAttribute(XmlName('name'), contentName),
      XmlAttribute(XmlName('creator'), 'initiator'),
    ], [transport]);
    return content.toXmlString();
  }

  /// Inverse of [encodeCandidate]. Accepts either a `<jingle>` payload
  /// or a bare `<content>` element.
  static ({String candidate, String? sdpMid, int? sdpMLineIndex})?
      decodeCandidate(String jingleXml) {
    XmlElement root;
    try {
      root = XmlDocument.parse(jingleXml).rootElement;
    } on XmlException {
      return null;
    }
    final contents = root.name.local == 'content'
        ? [root]
        : _childrenNamed(root, 'content');
    for (final content in contents) {
      for (final transport in _childrenNamed(content, 'transport')) {
        for (final cand in _childrenNamed(transport, 'candidate')) {
          final s = cand.getAttribute('sdp');
          if (s == null || s.isEmpty) continue;
          return (
            candidate: s,
            sdpMid: cand.getAttribute('sdpMid'),
            sdpMLineIndex: int.tryParse(
              cand.getAttribute('sdpMLineIndex') ?? '',
            ),
          );
        }
      }
    }
    return null;
  }
}

Iterable<XmlElement> _childrenNamed(XmlElement el, String local) =>
    el.children.whereType<XmlElement>().where((c) => c.name.local == local);
