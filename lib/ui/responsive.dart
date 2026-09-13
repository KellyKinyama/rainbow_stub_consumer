import 'package:flutter/material.dart';
import 'package:rearch/rearch.dart';

import '../rainbow/models.dart';
import '../state/capsules/detail_selection_capsule.dart';
import 'bubble_topics_page.dart';
import 'chat_page.dart';

/// Width at or above which the home screen switches from single-pane
/// (mobile / WhatsApp-style push navigation) to a two-pane
/// master-detail layout (desktop: list + active chat side by side).
const double kWideLayoutBreakpoint = 900;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

/// Opens a 1:1 chat with [peer]. On wide layouts it fills the detail
/// pane; on narrow layouts it pushes a full-screen [ChatPage].
void openPeerChat(
  BuildContext context,
  ValueWrapper<ChatSelection?> selection,
  RainbowUser peer,
) {
  if (isWideLayout(context)) {
    selection.value = PeerSelection(peer);
  } else {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ChatPage(peer: peer)));
  }
}

/// Opens the group's topic list full-screen (whole app), regardless of
/// layout. Topics replace the list; drilling into a topic and backing
/// out is plain push/pop navigation.
void openBubbleChat(
  BuildContext context,
  ValueWrapper<ChatSelection?> selection,
  RainbowBubble bubble,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => BubbleTopicsPage(bubble: bubble)),
  );
}
