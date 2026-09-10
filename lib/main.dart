import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';

import 'app.dart';
import 'config.dart';

void main() {
  // Rearch bootstrap sits outside provider (which is still driving the
  // existing screens until Phase C). Both live side-by-side for the duration
  // of the migration; new state lives in capsules, old state in RainbowSession.
  runApp(
    RearchBootstrapper(
      child: RainbowConsumerApp(config: AppConfig.dev),
    ),
  );
}