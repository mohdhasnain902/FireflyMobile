import 'package:firefly_mobile/app.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entry point of the Firefly III mobile client.
///
/// All async platform setup (secure storage, database open) is deferred to
/// providers so the first frame renders immediately and the app stays usable
/// offline even if a subsystem fails to initialise.
void main() {
  // Required before using any plugin that touches the platform channel.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: FireflyApp()));
}
