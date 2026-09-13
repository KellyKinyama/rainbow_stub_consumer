import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';

/// The chat currently shown in the desktop detail pane. `null` means
/// nothing is selected yet (detail pane shows a placeholder).
sealed class ChatSelection {
  const ChatSelection();
}

/// A 1:1 conversation with [peer].
class PeerSelection extends ChatSelection {
  const PeerSelection(this.peer);
  final RainbowUser peer;
}

/// A group conversation in [bubble].
class BubbleSelection extends ChatSelection {
  const BubbleSelection(this.bubble);
  final RainbowBubble bubble;
}

/// Writable slot holding the conversation shown in the desktop
/// two-pane layout's detail area. Unused on narrow (mobile) layouts,
/// which push a full-screen route instead.
ValueWrapper<ChatSelection?> detailSelectionCapsule(CapsuleHandle use) =>
    use.data<ChatSelection?>(null);
