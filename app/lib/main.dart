import 'dart:io' show Platform;

import 'package:firefly_mobile/app.dart';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit;

/// Entry point of the Firefly III mobile client.
///
/// All async platform setup (secure storage, database open) is deferred to
/// providers so the first frame renders immediately and the app stays usable
/// offline even if a subsystem fails to initialise. The ProviderScope itself
/// lives inside [FireflyApp] so widget tests can pump the root widget alone.
void main() {
  // Required before using any plugin that touches the platform channel.
  WidgetsFlutterBinding.ensureInitialized();

  // Linux desktop runs (demo host for this mobile app) have no sqflite
  // platform channel: initialise the FFI backend that
  // `core/providers.dart`'s `_appDatabaseFactory` will select instead.
  // Android/iOS keep the normal channel factory.
  if (Platform.isLinux) {
    sqfliteFfiInit();
  }

  runApp(const FireflyApp());
}
