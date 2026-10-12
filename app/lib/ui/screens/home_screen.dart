import 'package:firefly_mobile/core/constants.dart';

import 'package:flutter/material.dart';

/// Temporary landing screen used while P1+ screens are built.
///
/// Exists so the app boots into something meaningful and the smoke test has a
/// stable target. Replaced by the dashboard in P4.
class HomeScreen extends StatelessWidget {
  /// Creates the placeholder home screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kAppName)),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_alt, size: 64),
            SizedBox(height: 16),
            Text('Offline-first expense tracking'),
            SizedBox(height: 4),
            Text(
              'Syncing with self-hosted Firefly III',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
