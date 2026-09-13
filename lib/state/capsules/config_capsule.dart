import 'package:rearch/rearch.dart';

import '../../config.dart';

/// Immutable app configuration exposed as a capsule so downstream
/// capsules (rest, xmpp) can depend on it declaratively.
AppConfig configCapsule(CapsuleHandle use) => AppConfig.dev;
