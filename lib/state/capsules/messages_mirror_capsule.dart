import 'package:flutter/widgets.dart';
import 'package:rearch/rearch.dart';

import '../messages_mirror.dart';

/// SharedPreferences-backed by default; degrades to
/// [NoOpMessagesMirror] when the flutter binding isn't up.
MessagesMirror messagesMirrorCapsule(CapsuleHandle use) {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    return const SharedPrefsMessagesMirror();
  } on Object {
    return const NoOpMessagesMirror();
  }
}
