import 'package:flutter/widgets.dart';
import 'package:rearch/rearch.dart';

import '../outgoing_queue.dart';

/// SharedPreferences-backed by default; degrades to
/// [NoOpOutgoingQueue] when the flutter binding isn't up.
OutgoingQueue outgoingQueueCapsule(CapsuleHandle use) {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    return const SharedPrefsOutgoingQueue();
  } on Object {
    return const NoOpOutgoingQueue();
  }
}
