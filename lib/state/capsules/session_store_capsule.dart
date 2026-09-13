import 'package:flutter/widgets.dart';
import 'package:rearch/rearch.dart';

import '../session_store.dart';

/// SharedPreferences-backed by default; swaps to [NoOpSessionStore]
/// when the flutter binding hasn't been initialised (unit tests that
/// build a [MockableContainer] without `runApp`).
SessionStore sessionStoreCapsule(CapsuleHandle use) {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    return const SharedPrefsSessionStore();
  } on Object {
    return const NoOpSessionStore();
  }
}
