import 'package:firefly_mobile/core/currency/exchange_rates.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/sync/sync_controller.dart';
import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/core/settings/db_export.dart';
import 'package:firefly_mobile/data/demo/demo_seeder.dart';
import 'package:firefly_mobile/data/sync/sync_controller.dart'
    show SyncAttempt;
import 'package:firefly_mobile/data/sync/sync_engine.dart'
    show kMaxSyncLogEntries;
import 'package:firefly_mobile/ui/configs/entity_configs.dart'
    show currenciesConfig;
import 'package:firefly_mobile/ui/screens/about_screen.dart';
import 'package:firefly_mobile/ui/screens/conflict_review_screen.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';
import 'package:firefly_mobile/ui/screens/exchange_rates_screen.dart';
import 'package:firefly_mobile/ui/screens/sync_log_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connection + diagnostics settings (P2.4).
///
/// Screens the three things a self-hosted Firefly user needs before the sync
/// engine (P3) can talk to a server:
///
/// 1. **Base URL** — validated through [normalizeBaseUrl], persisted to
///    `device_meta` via the settings store.
/// 2. **PAT** — write-only. Once a token is stored the field never echoes it
///    back (masked dots + "Replace"/"Clear"); the raw value only leaves the
///    screen into secure storage. This is the secure UX the security model in
///    DESIGN §"PAT storage" requires.
/// 3. **Diagnostics** — a live connection probe ([probeFirefly], 4s timeout)
///    and a manual local-DB export ([exportLocalDatabase], the P2 §4 debug
///    aid).
///
/// 4. **Sync** (P3.4) — a "Sync now" trigger that runs one full
///    probe-gated cycle through the sync controller and reports the result in
///    a SnackBar, plus a tile into the [SyncLogScreen] audit trail.
///    "Restore from server" (P3.6/Story 5) lives in the same section behind
///    a destructive confirmation dialog.
/// 5. **PC backup** (P4.1) — sidecar base URL + sidecar token. Empty URL =
///    feature off (the engine then skips its backup step silently). The token
///    is write-only exactly like the PAT: masked dots + Replace/Clear once
///    stored.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates the settings screen.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const SettingsScreen({super.key, this.embedded = false});

  /// When true, renders without its own [AppBar]/[Scaffold] chrome so the
  /// home shell can host it as a bottom-navigation tab.
  final bool embedded;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Base-URL field controller.
  late final TextEditingController _urlCtrl;

  /// PAT field controller — only ever holds what the user just typed.
  late final TextEditingController _patCtrl;

  /// PC-backup sidecar URL field controller (P4.1).
  late final TextEditingController _backupUrlCtrl;

  /// Sidecar-token field controller — only ever holds what was just typed.
  late final TextEditingController _backupTokenCtrl;

  /// True once a backup token is present, driving the masked/"Replace" UI.
  bool _hasBackupToken = false;

  /// Whether the backup-token field is expanded for entry (false = masked).
  bool _editingBackupToken = false;

  /// True once a token is present, driving the masked/"Replace" UI.
  bool _hasPat = false;

  /// Tracks the loaded settings so we can seed fields exactly once.
  bool _loaded = false;

  /// Whether the PAT field is expanded for entry (false = masked summary).
  bool _editingPat = false;

  /// In-flight connection probe.
  bool _probing = false;

  /// Last probe outcome, shown under the probe button.
  ProbeResult? _probeResult;

  /// In-flight DB export.
  bool _exporting = false;

  /// Last export path, shown after a successful export.
  String? _exportPath;

  /// In-flight manual sync ("Sync now").
  bool _syncing = false;

  /// In-flight "Restore from server" (Story 5) — a confirmed restore wipes
  /// local data, so it must not run twice or overlap a manual sync.
  bool _restoring = false;

  /// In-flight demo seed/erase — blocks a second tap while the transaction
  /// runs.
  bool _loadingDemo = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _patCtrl = TextEditingController();
    _backupUrlCtrl = TextEditingController();
    _backupTokenCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _patCtrl.dispose();
    _backupUrlCtrl.dispose();
    _backupTokenCtrl.dispose();
    super.dispose();
  }

  /// Seeds the fields from the persisted settings on first load.
  void _seed(ConnectionSettings settings) {
    if (_loaded) return;
    _loaded = true;
    _urlCtrl.text = settings.baseUrl;
    _hasPat = settings.pat != null && settings.pat!.isNotEmpty;
    _backupUrlCtrl.text = settings.backupUrl;
    _hasBackupToken =
        settings.backupToken != null && settings.backupToken!.isNotEmpty;
  }

  /// Persists the base URL; surfaces a SnackBar on invalid input.
  Future<void> _saveUrl(String raw) async {
    final normalized = normalizeBaseUrl(raw);
    if (normalized == null) {
      _snack('Enter a valid http(s)://host URL');
      return;
    }
    final store = await ref.read(connectionSettingsStoreProvider.future);
    await store.setBaseUrl(normalized);
    _urlCtrl.text = normalized;
    ref.invalidate(connectionSettingsProvider);
    _snack('Base URL saved');
  }

  /// A Firefly III personal access token is a signed JWT: three dot-separated
  /// segments. Copying only the middle payload segment (it still starts with
  /// `eyJ`) produces a token that can never authenticate — the server answers
  /// HTTP 401 on every sync, which reads like a server fault rather than a bad
  /// paste. Catch that specific shape before it is stored.
  static bool _looksLikeCompletePat(String token) =>
      !token.startsWith('eyJ') || token.split('.').length == 3;

  /// Persists the typed PAT and collapses the field back to the masked view.
  Future<void> _savePat() async {
    final pat = _patCtrl.text.trim();
    if (pat.isEmpty) {
      _snack('Token cannot be empty');
      return;
    }
    if (!_looksLikeCompletePat(pat)) {
      _snack(
        'That token looks incomplete — paste the whole token '
        '(three dot-separated parts)',
      );
      return;
    }
    final store = await ref.read(connectionSettingsStoreProvider.future);
    await store.setPat(pat);
    _patCtrl.clear();
    setState(() {
      _hasPat = true;
      _editingPat = false;
    });
    ref.invalidate(connectionSettingsProvider);
    _snack('Token saved');
  }

  /// Removes the stored token.
  Future<void> _clearPat() async {
    final store = await ref.read(connectionSettingsStoreProvider.future);
    await store.clearPat();
    setState(() {
      _hasPat = false;
      _editingPat = false;
    });
    ref.invalidate(connectionSettingsProvider);
    _snack('Token cleared');
  }

  /// Persists the PC-backup sidecar URL (P4.1).
  ///
  /// An empty value *is* the off-switch: it clears the stored URL so
  /// `BackupClient.trigger` reports `isDisabled` and the engine stays silent
  /// — exactly the pre-P4 behaviour, reachable without a separate toggle.
  Future<void> _saveBackupUrl(String raw) async {
    final store = await ref.read(connectionSettingsStoreProvider.future);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await store.setBackupUrl('');
      _backupUrlCtrl.clear();
      ref.invalidate(connectionSettingsProvider);
      _snack('Backup URL cleared — PC backup off');
      return;
    }
    final normalized = normalizeBaseUrl(trimmed);
    if (normalized == null) {
      _snack('Enter a valid http(s)://host URL');
      return;
    }
    await store.setBackupUrl(normalized);
    _backupUrlCtrl.text = normalized;
    ref.invalidate(connectionSettingsProvider);
    _snack('Backup URL saved');
  }

  /// Persists the sidecar token and collapses back to the masked view.
  Future<void> _saveBackupToken() async {
    final token = _backupTokenCtrl.text.trim();
    if (token.isEmpty) {
      _snack('Backup token cannot be empty');
      return;
    }
    final store = await ref.read(connectionSettingsStoreProvider.future);
    await store.setBackupToken(token);
    _backupTokenCtrl.clear();
    setState(() {
      _hasBackupToken = true;
      _editingBackupToken = false;
    });
    ref.invalidate(connectionSettingsProvider);
    _snack('Backup token saved');
  }

  /// Removes the stored sidecar token.
  Future<void> _clearBackupToken() async {
    final store = await ref.read(connectionSettingsStoreProvider.future);
    await store.clearBackupToken();
    setState(() {
      _hasBackupToken = false;
      _editingBackupToken = false;
    });
    ref.invalidate(connectionSettingsProvider);
    _snack('Backup token cleared');
  }

  /// Runs the live connection probe against the currently saved URL + PAT.
  Future<void> _testConnection() async {
    final settings = await ref.read(connectionSettingsProvider.future);
    if (!settings.isConfigured) {
      _snack('Save a base URL first');
      return;
    }
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    final result = await probeFirefly(
      baseUrl: settings.baseUrl,
      pat: settings.pat,
    );
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeResult = result;
    });
  }

  /// Exports the local SQLite file to a shareable copy (debug aid).
  Future<void> _exportDb() async {
    setState(() {
      _exporting = true;
      _exportPath = null;
    });
    try {
      final db = await ref.read(databaseProvider.future);
      final path = await ref.read(databasePathProvider.future);
      final out = await exportLocalDatabase(db, sourcePath: path);
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportPath = out;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportPath = null;
      });
      _snack('Export failed: $e');
    }
  }

  /// Runs one probe-gated sync cycle and reports the outcome (P3.4).
  Future<void> _syncNow() => _runSync(
        'both',
        (c) => c.runNow(),
        busyLabel: 'Syncing…',
      );

  /// Pushes local (phone) queued changes to the website only.
  Future<void> _pushToWebsite() => _runSync(
        'push',
        (c) => c.pushToWebsite(),
        busyLabel: 'Sending…',
      );

  /// Pulls website records into the phone only.
  Future<void> _pullFromWebsite() => _runSync(
        'pull',
        (c) => c.pullFromWebsite(),
        busyLabel: 'Receiving…',
      );

  Future<void> _runSync(
    String mode,
    Future<SyncAttempt> Function(SyncController) run, {
    required String busyLabel,
  }) async {
    setState(() => _syncing = true);
    final SyncAttempt attempt;
    try {
      attempt = await run(ref.read(syncControllerProvider));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _snack('Sync failed — $e');
      return;
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    ref.invalidate(syncLogProvider);
    ref.invalidate(pendingOpsCountProvider);
    ref.invalidate(syncStatusProvider);
    // Pull/full-sync can change local records; refresh every screen that reads
    // them (entity lists, Dashboard/Reports ledgers) so data received from the
    // website — including website-side deletions — shows immediately. A pull
    // that reports a per-entity failure still merged the entities that worked
    // and still tombstoned what the server dropped, so refresh then too.
    if (mode != 'push') {
      for (final p in allSyncedDataProviders) {
        ref.invalidate(p);
      }
    }
    _snack(_describeDirectionalAttempt(mode, attempt));
  }

  String _describeDirectionalAttempt(String mode, SyncAttempt attempt) {
    final skip = attempt.skipped;
    if (skip != null) return skip.message;
    final outcome = attempt.outcome!;
    if (!outcome.ok) {
      final failure = outcome.failure;
      final base = failure == null ? 'failed' : failure.message;
      return switch (mode) {
        'push' => 'Send to website failed — $base',
        'pull' => 'Get from website failed — $base',
        _ => 'Sync failed — $base',
      };
    }
    if (mode == 'push') {
      return outcome.pushedOps == 0
          ? 'Nothing to send — phone and website are up to date (no local changes queued)'
          : 'Sent ${outcome.pushedOps} change(s) to the website';
    }
    if (mode == 'pull') {
      final pull = outcome.pull;
      if (pull == null) return 'Received data from website';
      final changed = pull.inserted + pull.updated + pull.tombstoned;
      return changed == 0
          ? 'Phone is up to date — no new website data'
          : 'Received from website: +${pull.inserted} new, ~${pull.updated} updated, −${pull.tombstoned} removed';
    }
    return describeSyncAttempt(attempt);
  }

  /// Story 5 — asks for a destructive confirmation, then runs the restore.
  ///
  /// The confirm dialog is the only gate: restore wipes every synced table
  /// and re-downloads, so a stray tap must never trigger it. Cancel (or a
  /// dismissed dialog) returns without touching the controller.
  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from server?'),
        content: const Text(
          'This erases every record stored on this device and re-downloads '
          'your data from the server. Local changes that were never synced '
          'will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Erase & restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _restore();
  }

  /// Runs one confirmed restore (Story 5) and reports the outcome.
  ///
  /// Same contract as [_syncNow]: the busy flag blocks a second tap, the log
  /// provider is invalidated so [SyncLogScreen] reflects the cycle, and any
  /// error escaping the engine lands in a SnackBar instead of a red screen.
  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final result = await ref.read(syncControllerProvider).restore();
      if (!mounted) return;
      setState(() => _restoring = false);
      ref.invalidate(syncLogProvider);
      final failure = result.failureOrNull;
      if (failure != null) {
        // A gate skip never touched the server — show the reason bare,
        // exactly like describeSyncAttempt does for a skipped "Sync now"
        // (the sync.skipped.* code is the non-prose discriminator).
        final skipped = (failure.code ?? '').startsWith('sync.skipped.');
        _snack(
          skipped ? failure.message : 'Restore failed — ${failure.message}',
        );
        return;
      }
      final stats = result.valueOrNull!;
      _snack(
        'Restored from server — '
        '${stats.inserted} added, ${stats.updated} updated',
      );
    // Catches Errors too (on Object): anything escaping the engine must
    // reach the SnackBar, never a red screen.
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _restoring = false);
      _snack('Restore failed — $e');
    }
  }

  /// Loads the demo dataset (seedDemoData) and reports the outcome.
  ///
  /// Idempotent: re-running upserts the same `demo-` keys. Synced rows are
  /// born with `SyncStatus.synced` so nothing enters the push queue. After
  /// a successful seed every list provider is invalidated so Dashboard /
  /// entity screens re-query without a restart.
  Future<void> _loadDemo() async {
    setState(() => _loadingDemo = true);
    try {
      final db = await ref.read(databaseProvider.future);
      await seedDemoData(db);
      if (!mounted) return;
      setState(() => _loadingDemo = false);
      allEntityListProviders.forEach(ref.invalidate);
      _snack('Demo data loaded');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadingDemo = false);
      _snack('Demo load failed — $e');
    }
  }

  /// Confirms then erases every `demo-` row (and clears the seeded flag).
  Future<void> _confirmEraseDemo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase demo data?'),
        content: const Text(
          'This deletes every record whose ID starts with "demo-" '
          '(the sample dataset). Real synced data is not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Erase demo data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _eraseDemo();
  }

  /// Runs one confirmed demo erase and reports the outcome.
  Future<void> _eraseDemo() async {
    setState(() => _loadingDemo = true);
    try {
      final db = await ref.read(databaseProvider.future);
      await eraseDemoData(db);
      if (!mounted) return;
      setState(() => _loadingDemo = false);
      allEntityListProviders.forEach(ref.invalidate);
      _snack('Demo data erased');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadingDemo = false);
      _snack('Demo erase failed — $e');
    }
  }

  /// Fires a brief confirmation message.
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(connectionSettingsProvider);
    final content = settingsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading settings'),
      ),
      error: (e, _) => Center(child: Text('Settings unavailable: $e')),
      data: (settings) {
        _seed(settings);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
              _sectionLabel(context, 'Connection'),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Firefly base URL',
                  hintText: 'https://firefly.example.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => _saveUrl(_urlCtrl.text),
                  child: const Text('Save URL'),
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Personal access token'),
              _patSection(),
              const SizedBox(height: 24),
              _sectionLabel(context, 'PC backup'),
              TextField(
                controller: _backupUrlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Backup sidecar URL',
                  hintText: 'http://pc:8095',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (settings.backupUrl.isEmpty) ...[
                Text(
                  'Empty — PC backup stays off after sync.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => _saveBackupUrl(_backupUrlCtrl.text),
                  child: const Text('Save backup URL'),
                ),
              ),
              const SizedBox(height: 12),
              _backupTokenSection(),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Diagnostics'),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _probing ? null : _testConnection,
                      icon: _probing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('Test connection'),
                    ),
                  ),
                ],
              ),
              if (_probeResult != null) ...[
                const SizedBox(height: 8),
                _ProbeResultView(result: _probeResult!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : _exportDb,
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt),
                      label: const Text('Export local database'),
                    ),
                  ),
                ],
              ),
              if (_exportPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Saved to $_exportPath',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              _sectionLabel(context, 'Sync'),
              Text(
                'Choose how to sync. "Sync now" sends local changes and then '
                'downloads website data. You can also sync one direction at a time.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_syncing || _restoring) ? null : _syncNow,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(_syncing ? 'Syncing…' : 'Sync now (both ways)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_syncing || _restoring) ? null : _pushToWebsite,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Sync phone → website'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_syncing || _restoring) ? null : _pullFromWebsite,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Sync website → phone'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.settings_backup_restore_outlined),
                title: const Text('Restore from server'),
                subtitle:
                    const Text('Erase local records and re-download them'),
                enabled: !_syncing && !_restoring,
                trailing: _restoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _confirmRestore,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text(kSyncLogTitle),
                subtitle: const Text('Last $kMaxSyncLogEntries sync entries'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SyncLogScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Conflicts'),
              ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber,
                ),
                title: const Text('Review conflicts'),
                subtitle: const Text(
                  'Server-won LWW overwrites across all entities',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConflictReviewScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Currency & conversion'),
              _CurrencyDisplaySection(
                onChanged: () => ref.invalidate(currencyDisplayProvider),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Currencies'),
                subtitle: const Text(
                  'Add a custom currency (BTC, tokens) or edit one',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EntityListScreen(
                        config: currenciesConfig,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: const Text('Exchange rates'),
                subtitle: const Text(
                  'Enter both directions of a pair by hand',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExchangeRatesScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Demo data'),
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Load demo data'),
                subtitle: const Text(
                  'Seed a sample dataset (synced rows, no push queue)',
                ),
                enabled: !_loadingDemo,
                trailing: _loadingDemo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _loadDemo,
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Erase demo data'),
                subtitle: const Text('Remove every demo- prefixed row'),
                enabled: !_loadingDemo,
                onTap: _confirmEraseDemo,
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'About'),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text(kAboutTitle),
                subtitle: const Text('Third-party licenses & attribution'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  );
                },
              ),
            ],
          );
      },
    );
    if (widget.embedded) {
      return content;
    }
    return Scaffold(
      appBar: AppBar(title: const Text(kSettingsTitle)),
      body: content,
    );
  }

  /// Section heading used to group the settings list.
  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  /// PAT row: masked summary with Replace/Clear, or an active entry field.
  Widget _patSection() {
    if (!_editingPat) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hasPat ? 'Token saved (••••••••)' : 'No token saved',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: () => setState(() => _editingPat = true),
                child: Text(_hasPat ? 'Replace' : 'Add token'),
              ),
              if (_hasPat) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _clearPat,
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _patCtrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Personal access token',
            hintText: 'Paste your Firefly PAT',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        // Wrap, not Row: at 320 logical px (and under font scaling) the two
        // buttons exceeded the 288px content width by 42px in the sweep test.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _savePat,
              child: const Text('Save token'),
            ),
            OutlinedButton(
              onPressed: () => setState(() {
                _editingPat = false;
                _patCtrl.clear();
              }),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
  /// Sidecar-token row: masked summary with Replace/Clear, or entry field.
  ///
  /// Deliberately a private twin of [_patSection] rather than a shared
  /// parameterised widget: the PAT screen is covered by four existing tests
  /// and per scoped-changes must not be refactored to serve P4.
  Widget _backupTokenSection() {
    if (!_editingBackupToken) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hasBackupToken
                ? 'Backup token saved (••••••••)'
                : 'No backup token saved',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: () => setState(() => _editingBackupToken = true),
                child: Text(_hasBackupToken ? 'Replace' : 'Add backup token'),
              ),
              if (_hasBackupToken) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _clearBackupToken,
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _backupTokenCtrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Backup token',
            hintText: 'Sidecar token from the PC',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        // Wrap, not Row — same narrow-width overflow as the PAT row above.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _saveBackupToken,
              child: const Text('Save token'),
            ),
            OutlinedButton(
              onPressed: () => setState(() {
                _editingBackupToken = false;
                _backupTokenCtrl.clear();
              }),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}


/// Display-currency picker and exchange-rate refresh (open fawazahmed0 API).
class _CurrencyDisplaySection extends ConsumerStatefulWidget {
  const _CurrencyDisplaySection({required this.onChanged});
  final VoidCallback onChanged;

  @override
  ConsumerState<_CurrencyDisplaySection> createState() =>
      _CurrencyDisplaySectionState();
}

class _CurrencyDisplaySectionState
    extends ConsumerState<_CurrencyDisplaySection> {
  bool _refreshing = false;

  Future<void> _setDisplay(String? code) async {
    final store = await ref.read(currencyDisplayStoreProvider.future);
    await store.setDisplayCurrency(code);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _refreshRates(CurrencyDisplaySettings settings) async {
    setState(() => _refreshing = true);
    try {
      final store = await ref.read(currencyDisplayStoreProvider.future);
      // Fetch well-connected bases (USD/EUR always, plus the selected display
      // currency and a few common ones) so cross-conversion works for most
      // source/target pairs (including PKR, AUD, etc.).
      final bases = <String>{
        'USD',
        'EUR',
        if (settings.enabled) settings.displayCurrency!,
        'PKR',
        'GBP',
        'AUD',
        'INR',
      };
      var current = settings;
      for (final base in bases) {
        current = await ensureRatesFor(
          store,
          current,
          base,
          maxAge: Duration.zero,
        );
      }
      widget.onChanged();
      if (!mounted) return;
      final ok = current.cache.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Exchange rates updated (${current.cache.length} base currencies cached)'
                : 'Could not fetch exchange rates. Check your internet connection and try again.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh rates: $e')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(currencyDisplayProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Currency settings unavailable: $e'),
      data: (settings) {
        final selected = settings.displayCurrency;
        final fetched = settings.fetchedAtMs == null
            ? 'never'
            : DateTime.fromMillisecondsSinceEpoch(
                settings.fetchedAtMs!,
              ).toLocal().toString().split('.').first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Show amounts in (secondary)',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Off (original currency only)'),
                ),
                for (final c in kCommonCurrencyCodes)
                  DropdownMenuItem<String?>(value: c, child: Text(c)),
                if (selected != null && !kCommonCurrencyCodes.contains(selected))
                  DropdownMenuItem<String?>(
                    value: selected,
                    child: Text(selected),
                  ),
              ],
              onChanged: (v) => _setDisplay(v),
            ),
            const SizedBox(height: 8),
            Text(
              'Converted amounts are shown below originals (like exchange apps). '
              'Rates: open-source fawazahmed0/exchange-api (daily). Last update: $fetched.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _refreshing ? null : () => _refreshRates(settings),
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.currency_exchange),
              label: Text(_refreshing ? 'Refreshing…' : 'Refresh exchange rates'),
            ),
          ],
        );
      },
    );
  }
}

/// Renders one probe outcome with an icon and a short human message.
class _ProbeResultView extends StatelessWidget {
  /// Creates the result row.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const _ProbeResultView({required this.result});

  /// The probe outcome to render.
  final ProbeResult result;

  @override
  Widget build(BuildContext context) {
    final (icon, color, message) = switch (result.status) {
      ProbeStatus.ok => (
        Icons.check_circle,
        Colors.green,
        'Connected — Firefly responded ${result.statusCode}.',
      ),
      ProbeStatus.unauthorized => (
        Icons.key_off,
        Colors.orange,
        'Reachable but unauthorized (${result.statusCode}). '
            'Check the token.',
      ),
      ProbeStatus.unexpectedStatus => (
        Icons.error_outline,
        Colors.orange,
        'Reachable but unexpected response '
            '(${result.statusCode ?? 'no status'}).',
      ),
      ProbeStatus.unreachable => (
        Icons.cloud_off,
        Colors.red,
        'Could not reach the server'
            '${result.detail == null ? '' : ' — ${result.detail}'}',
      ),
    };
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    );
  }
}

/// Route title shown in the app bar.
const kSettingsTitle = 'Settings';

/// One-line SnackBar summary for a finished `SyncController.runNow` attempt.
///
/// Skips surface the gate's own user-facing text; failures lead with
/// `Sync failed` so the tone reads even when `Failure.message` is a long
/// transport string; a clean cycle that moved nothing says so instead of
/// implying fresh data.
String describeSyncAttempt(SyncAttempt attempt) {
  final skip = attempt.skipped;
  if (skip != null) return skip.message;
  final outcome = attempt.outcome!;
  if (!outcome.ok) {
    final failure = outcome.failure;
    return failure == null ? 'Sync failed' : 'Sync failed — ${failure.message}';
  }
  final pull = outcome.pull;
  final changed = pull != null &&
      (pull.inserted > 0 || pull.updated > 0 || pull.tombstoned > 0);
  if (outcome.pushedOps == 0 && !changed) {
    return 'Sync complete — already up to date';
  }
  final parts = <String>[
    if (outcome.pushedOps > 0) 'pushed ${outcome.pushedOps}',
    if (pull != null) ...[
      if (pull.inserted > 0) '+${pull.inserted} new',
      if (pull.updated > 0) '~${pull.updated} updated',
      if (pull.tombstoned > 0) '−${pull.tombstoned} removed',
    ],
  ];
  return 'Sync complete — ${parts.join(', ')}';
}
