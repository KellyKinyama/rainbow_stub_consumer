import 'package:flutter/widgets.dart';
import 'package:rearch/rearch.dart';

import '../conversations_mirror.dart';

/// SharedPreferences-backed by default; degrades to [NoOpConversationsMirror]
/// when the flutter binding isn't up (unit tests).
ConversationsMirror conversationsMirrorCapsule(CapsuleHandle use) {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    return const SharedPrefsConversationsMirror();
  } on Object {
    return const NoOpConversationsMirror();
  }
}
