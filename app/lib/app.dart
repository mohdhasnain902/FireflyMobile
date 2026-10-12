import 'package:firefly_mobile/core/constants.dart';
import 'package:firefly_mobile/ui/screens/home_screen.dart';

import 'package:flutter/material.dart';

/// Root widget of the application.
///
/// Owns the theme and navigation shell only — business logic lives in
/// Riverpod providers and the domain layer, never in widgets.
class FireflyApp extends StatelessWidget {
  /// Creates the root application widget.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Deterministic brand colour so light/dark stay recognisably ours.
        colorSchemeSeed: const Color(0xFF5C3FD6),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5C3FD6),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
