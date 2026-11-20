import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Open-source notices screen (P2.4).
///
/// Renders the bundled [kNoticePath] file — the same NOTICE.md referenced by
/// DESIGN/NFR attribution requirements (SQLCipher BSD-3-Clause, SQLite,
/// OpenSSL). The text is loaded once per open and shown read-only, so a user
/// (or auditor) can always reach the third-party licenses from the app.
///
/// The asset is declared in `pubspec.yaml`; if it is ever missing the screen
/// degrades to a clear message rather than crashing — the offline-first rule
/// applies to UI chrome too.
class AboutScreen extends StatefulWidget {
  /// Creates the notices screen.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  /// Loaded notice text, or null while loading / on failure.
  String? _text;

  /// Non-null when the asset could not be read.
  String? _error;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: _load sets state on completion and guards `mounted`.
    unawaited(_load());
  }

  /// Reads the bundled NOTICE.md once.
  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(kNoticePath);
      if (!mounted) return;
      setState(() => _text = raw);
    } on Exception {
      if (!mounted) return;
      setState(() => _error = 'Notices unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kAboutTitle)),
      body: switch ((_text, _error)) {
        (final String text, null) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5)),
        ),
        (null, final String error) => Center(child: Text(error)),
        _ => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading notices'),
        ),
      },
    );
  }
}

/// Route title shown in the app bar.
const kAboutTitle = 'Open-source licenses';

/// Asset path of the notices file, registered under `flutter: assets:` in
/// `pubspec.yaml`.
const kNoticePath = 'NOTICE.md';
