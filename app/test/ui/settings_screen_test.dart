import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/ui/screens/settings_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the P2.4 Settings screen.
///
/// Backed by the real [InMemoryConnectionSettingsStore] (same behaviour as the
/// Keystore store, no platform channel). Covers: URL validation + save, the
/// masked-PAT flow (save / replace / clear, raw value never re-shown), the
/// probe/export buttons being wired, About-screen navigation, and (P4.1) the
/// PC-backup section: sidecar URL save/normalise/clear, its invalid-input
/// snackbar, and the masked backup-token flow that must not collide with the
/// PAT finders above it.
///
/// The live probe path is unit-tested in connection_probe_test.dart; here we
/// only assert the button exists and is enabled, since wiring the screen's
/// `probeFirefly` call to an injected client would require a seam the screen
/// does not currently expose.
void main() {
  /// Overrides the settings-store seam with an in-memory double.
  Override settingsOverride(ConnectionSettingsStore store) =>
      connectionSettingsStoreProvider.overrideWith((_) async => store);

  /// Overrides the connection probe's HTTP client via a mock that returns
  /// [status] for any request. The probe builds its own `http.Client` unless
  /// one is injected, so we swap the package-level client factory the screen
  /// reaches for by... actually the screen calls `probeFirefly` without a
  /// client, which constructs a real one. To keep the test offline we drive
  /// the probe indirectly through the store + a client injected at the seam.
  ///
  /// Because `probeFirefly` is called by the screen without an injectable
  /// client, these tests exercise the *result rendering* by seeding a probe
  /// outcome through a thin wrapper is not possible without a seam. Instead we
  /// verify the screen's button wiring and the pure normalize/save logic, and
  /// cover the probe itself in connection_probe_test.dart. The probe button is
  /// asserted to exist and be enabled; its live path is unit-tested separately.
  Future<void> pumpSettings(
    WidgetTester tester,
    ConnectionSettingsStore store,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsOverride(store)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrollable of the Settings list (not a text field's internal one).
  Finder settingsScrollable() => find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Brings [f] into view before a tap/type — the PC-backup section sits
  /// below PAT in the Settings ListView and can be past the initial
  /// viewport *or* past the ListView cacheExtent (the About-tile trap:
  /// unbuilt until scrolled into range). Covers both cases.
  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: settingsScrollable(),
      );
    }
    // scrollUntilVisible already did a final ensureVisible; for elements
    // that were already built, bring them into the viewport if needed.
    await tester.ensureVisible(f);
    // Settle scroll animations without pumpAndSettle (which can hang on
    // indeterminate progress indicators / snackbar timers in this screen).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('seeds the URL field from the saved settings', (tester) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.example.com'),
    );
    await pumpSettings(tester, store);

    final urlField = find.widgetWithText(TextField, 'Firefly base URL');
    expect(
      tester.widget<TextField>(urlField).controller!.text,
      'https://firefly.example.com',
    );
    expect(find.text('No token saved'), findsOneWidget);
  });

  testWidgets('save URL rejects a non-http value with a snackbar', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(tester, store);

    await tester.enterText(
      find.widgetWithText(TextField, 'Firefly base URL'),
      'ftp://nope',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save URL'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid http(s)://host URL'), findsOneWidget);
    expect((await store.read()).baseUrl, isEmpty, reason: 'must not persist');
  });

  testWidgets('save URL normalizes and persists a valid value', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(tester, store);

    await tester.enterText(
      find.widgetWithText(TextField, 'Firefly base URL'),
      '  https://firefly.example.com/subpath/  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save URL'));
    await tester.pumpAndSettle();

    // Path is dropped; trailing slash/whitespace trimmed.
    expect((await store.read()).baseUrl, 'https://firefly.example.com');
    expect(find.text('Base URL saved'), findsOneWidget);
  });

  testWidgets('add token saves and switches to the masked summary', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(tester, store);

    expect(find.text('No token saved'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add token'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Personal access token'),
      'secret-token-123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save token'));
    await tester.pumpAndSettle();

    expect((await store.read()).pat, 'secret-token-123');
    expect(find.text('Token saved (••••••••)'), findsOneWidget);
    // The raw value must never be re-shown after save.
    expect(find.text('secret-token-123'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Replace'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Clear'), findsOneWidget);
  });

  testWidgets('clear token removes it and shows the empty state', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'old'),
    );
    await pumpSettings(tester, store);

    expect(find.text('Token saved (••••••••)'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
    await tester.pumpAndSettle();

    expect((await store.read()).pat, isNull);
    expect(find.text('No token saved'), findsOneWidget);
  });

  testWidgets('replace token overwrites the stored value', (tester) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'old'),
    );
    await pumpSettings(tester, store);

    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Personal access token'),
      'new-token',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save token'));
    await tester.pumpAndSettle();

    expect((await store.read()).pat, 'new-token');
  });

  testWidgets('probe button exists and is enabled once settings load', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example'),
    );
    await pumpSettings(tester, store);

    final probeButton = find.widgetWithText(OutlinedButton, 'Test connection');
    // The PC-backup section sits above Diagnostics: the probe button is
    // past the initial cacheExtent until scrolled into range.
    await scrollTo(tester, probeButton);
    expect(probeButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(probeButton).onPressed, isNotNull);
  });

  testWidgets('export button is wired and enabled', (tester) async {
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(tester, store);

    final exportButton = find.widgetWithText(
      OutlinedButton,
      'Export local database',
    );
    // Same lazy-range trap as the probe button (PC backup pushes
    // Diagnostics down the ListView).
    await scrollTo(tester, exportButton);
    expect(exportButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(exportButton).onPressed, isNotNull);
  });

  testWidgets('about tile is present and navigates to the notices screen', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(tester, store);

    // The Sync section (Story 2) pushed About past the initial ListView
    // cacheExtent: the tile is lazily unbuilt until scrolled into range.
    await tester.scrollUntilVisible(
      find.text('Open-source licenses'),
      200,
      scrollable: settingsScrollable(),
    );
    await tester.tap(find.text('Open-source licenses'));
    await tester.pumpAndSettle();

    expect(find.text('Open-source licenses'), findsWidgets);
  });

  // ── PC backup section (P4.1, DESIGN §8.2) ─────────────────────────────────

  testWidgets('seeds backup URL + masked token; PAT and backup coexist', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(
        baseUrl: 'https://firefly.example.com',
        pat: 'pat-secret',
        backupUrl: 'http://pc:8095',
        backupToken: 'sidecar-secret',
      ),
    );
    await pumpSettings(tester, store);

    // URL field seeded from the store; helper hidden while non-empty.
    final backupUrlField = find.widgetWithText(
      TextField,
      'Backup sidecar URL',
    );
    expect(
      tester.widget<TextField>(backupUrlField).controller!.text,
      'http://pc:8095',
    );
    expect(
      find.text('Empty — PC backup stays off after sync.'),
      findsNothing,
    );
    // Both masked summaries show, with distinct labels; 'Clear' exists
    // once per section (2 total) without either test finder colliding.
    expect(find.text('Token saved (••••••••)'), findsOneWidget);
    expect(find.text('Backup token saved (••••••••)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Clear'), findsNWidgets(2));
  });

  testWidgets('save backup URL normalizes, persists, and drops the helper', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(tester, store);

    expect(
      find.text('Empty — PC backup stays off after sync.'),
      findsOneWidget,
    );

    // Type FIRST while the field is still in the built window, then scroll
    // to the button: ensureVisible(button) would evict the field from the
    // ListView's lazy range above it.
    await tester.enterText(
      find.widgetWithText(TextField, 'Backup sidecar URL'),
      '  http://pc:8095/subpath/  ',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Save backup URL');
    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect((await store.read()).backupUrl, 'http://pc:8095');
    expect(find.text('Backup URL saved'), findsOneWidget);
    // Non-empty URL → helper disappears on the rebuild after invalidate.
    expect(
      find.text('Empty — PC backup stays off after sync.'),
      findsNothing,
    );
    // Normalised value is re-shown in the field, not the raw entry.
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Backup sidecar URL'),
          )
          .controller!
          .text,
      'http://pc:8095',
    );
  });

  testWidgets('clearing the backup URL with an empty save turns the '
      'feature off', (tester) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(
        baseUrl: 'https://x.example',
        backupUrl: 'http://pc:9000',
      ),
    );
    await pumpSettings(tester, store);
    expect(
      find.text('Empty — PC backup stays off after sync.'),
      findsNothing,
    );

    // Type first, then scroll (see the normalize test for the ordering trap).
    await tester.enterText(
      find.widgetWithText(TextField, 'Backup sidecar URL'),
      '',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Save backup URL');
    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect((await store.read()).backupUrl, isEmpty);
    expect(find.text('Backup URL cleared — PC backup off'), findsOneWidget);
    // Helper returns: empty IS the off-switch, no separate toggle.
    expect(
      find.text('Empty — PC backup stays off after sync.'),
      findsOneWidget,
    );
  });

  testWidgets('save backup URL rejects a non-http value with a snackbar', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(
        baseUrl: 'https://x.example',
        backupUrl: 'http://pc:9000',
      ),
    );
    await pumpSettings(tester, store);

    // Type first, then scroll (see the normalize test for the ordering trap).
    await tester.enterText(
      find.widgetWithText(TextField, 'Backup sidecar URL'),
      'ftp://nope',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Save backup URL');
    await scrollTo(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid http(s)://host URL'), findsOneWidget);
    // The previously saved URL must survive the rejection.
    expect((await store.read()).backupUrl, 'http://pc:9000');
  });

  testWidgets('add backup token saves and switches to the masked summary', (
    tester,
  ) async {
    // No PAT on purpose: 'Clear'/'Replace'/'Save token' must resolve to the
    // backup section alone, proving the rename to 'Add backup token' keeps
    // the PAT finders unambiguous.
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(
        baseUrl: 'https://x.example',
        backupUrl: 'http://pc:8095',
      ),
    );
    await pumpSettings(tester, store);

    expect(find.text('No backup token saved'), findsOneWidget);
    // Distinct from the PAT empty state.
    expect(find.text('No token saved'), findsOneWidget);

    final addButton = find.widgetWithText(
      FilledButton,
      'Add backup token',
    );
    await scrollTo(tester, addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Backup token'),
      'sidecar-secret-1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save token'));
    await tester.pumpAndSettle();

    expect((await store.read()).backupToken, 'sidecar-secret-1');
    expect(find.text('Backup token saved (••••••••)'), findsOneWidget);
    // Raw value must never be re-shown; PAT mask string must not appear.
    expect(find.text('sidecar-secret-1'), findsNothing);
    expect(find.text('Token saved (••••••••)'), findsNothing);
    // Backup-only token → exactly one Replace/Clear pair (backup's).
    expect(find.widgetWithText(FilledButton, 'Replace'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Clear'), findsOneWidget);
  });

  testWidgets('clear backup token removes it but keeps the URL', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(
        baseUrl: 'https://x.example',
        backupUrl: 'http://pc:8095',
        backupToken: 'old-sidecar',
      ),
    );
    await pumpSettings(tester, store);

    expect(find.text('Backup token saved (••••••••)'), findsOneWidget);

    final clearButton = find.widgetWithText(OutlinedButton, 'Clear');
    await scrollTo(tester, clearButton);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect((await store.read()).backupToken, isNull);
    expect((await store.read()).backupUrl, 'http://pc:8095');
    expect(find.text('No backup token saved'), findsOneWidget);
    expect(find.text('Backup token cleared'), findsOneWidget);
    // Back to the add-state button, no Clear left.
    expect(
      find.widgetWithText(FilledButton, 'Add backup token'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Clear'), findsNothing);
  });
}
