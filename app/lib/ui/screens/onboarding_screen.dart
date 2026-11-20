/// Onboarding screen (Phase D — first-run welcome flow).
///
/// Guides a new install through the three things the sync engine needs before
/// the main shell unlocks:
///
/// 1. **Firefly base URL** — validated through [normalizeBaseUrl].
/// 2. **PAT** — write-only, stored in secure storage (never echoed back).
/// 3. **PC backup sidecar URL + token** (optional) — backup is off if unset.
///
/// After saving, the app probes `GET /api/v1/about` to confirm reachability,
/// then navigates to the home shell. The probe is 4s and gate-based: an
/// unreachable server shows a clear error but does not block — the app is
/// fully usable offline (DESIGN NFR-1).
///
/// The screen is a [ConsumerStatefulWidget] so it can read
/// [connectionSettingsStoreProvider] and write through it. Widget tests can
/// override the store seam.
library;

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One onboarding step: [url], [pat], [backup], [done].
enum OnboardStep {
  url,
  pat,
  backup,
  done,
}

/// First-run welcome flow.
///
/// On completion, the caller (HomeShell) navigates to the main shell. The
/// screen writes settings through [connectionSettingsStoreProvider] and runs
/// a probe-gated connectivity check before finishing.
class OnboardingScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _urlCtrl = TextEditingController();
  final _patCtrl = TextEditingController();
  final _backupUrlCtrl = TextEditingController();
  final _backupTokenCtrl = TextEditingController();

  OnboardStep _step = OnboardStep.url;
  bool _saving = false;
  String? _error;
  ProbeResult? _probeResult;

  /// Whether a PAT is already stored (drives masked/"Replace" UI).
  bool _hasPat = false;
  bool _editingPat = false;

  bool _hasBackupToken = false;
  bool _editingBackupToken = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _patCtrl.dispose();
    _backupUrlCtrl.dispose();
    _backupTokenCtrl.dispose();
    super.dispose();
  }

  /// Loads current settings to seed fields exactly once.
  Future<void> _load() async {
    final store = await ref.read(connectionSettingsStoreProvider.future);
    final settings = await store.read();
    if (settings.baseUrl.isNotEmpty && _urlCtrl.text.isEmpty) {
      _urlCtrl.text = settings.baseUrl;
    }
    _hasPat = settings.pat != null && settings.pat!.isNotEmpty;
    _hasBackupToken = settings.backupToken != null && settings.backupToken!.isNotEmpty;
    if (settings.backupUrl.isNotEmpty && _backupUrlCtrl.text.isEmpty) {
      _backupUrlCtrl.text = settings.backupUrl;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Validates and saves the current step, advancing on success.
  Future<void> _saveAndNext() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final store = await ref.read(connectionSettingsStoreProvider.future);

      switch (_step) {
        case OnboardStep.url:
          final normalized = normalizeBaseUrl(_urlCtrl.text.trim());
          if (normalized == null) {
            setState(() {
              _error = 'Enter a valid Firefly base URL (http:// or https://)';
              _saving = false;
            });
            return;
          }
          await store.setBaseUrl(normalized);
          _advance();

        case OnboardStep.pat:
          if (_patCtrl.text.trim().isEmpty) {
            setState(() {
              _error = 'Enter your Firefly personal access token';
              _saving = false;
            });
            return;
          }
          await store.setPat(_patCtrl.text.trim());
          _advance();

        case OnboardStep.backup:
          final backupUrl = _backupUrlCtrl.text.trim();
          if (backupUrl.isNotEmpty) {
            final normalized = normalizeBaseUrl(backupUrl);
            if (normalized == null) {
              setState(() {
                _error = 'Enter a valid backup sidecar URL (http:// or https://)';
                _saving = false;
              });
              return;
            }
            await store.setBackupUrl(normalized);
          }
          if (_backupTokenCtrl.text.trim().isNotEmpty) {
            await store.setBackupToken(_backupTokenCtrl.text.trim());
          }
          _advance();

        case OnboardStep.done:
          break;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _advance() {
    const values = OnboardStep.values;
    final idx = values.indexOf(_step);
    if (idx + 1 < values.length) {
      setState(() => _step = values[idx + 1]);
      _error = null;
    } else {
      setState(() => _step = OnboardStep.done);
    }
  }

  /// Runs the 4s probe against the saved URL/PAT. On success, signals done.
  /// On failure, shows the error but still allows continuing (offline-first).
  Future<void> _probeAndFinish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final store = await ref.read(connectionSettingsStoreProvider.future);
      final settings = await store.read();
      _probeResult = await probeFirefly(
        baseUrl: settings.baseUrl,
        pat: settings.pat,
      );
      switch (_probeResult!.status) {
        case ProbeStatus.ok:
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        case ProbeStatus.unauthorized:
          setState(() {
            _error = 'The server rejected the saved token — check it in Settings.';
            _saving = false;
          });
        case ProbeStatus.unexpectedStatus:
          setState(() {
            _error = 'That URL did not answer like a Firefly API — check it in Settings.';
            _saving = false;
          });
        case ProbeStatus.unreachable:
          setState(() {
            _error =
                'Firefly is unreachable — the app still works offline. Tap Continue anyway.';
            _saving = false;
          });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitle),
        automaticallyImplyLeading: _step != OnboardStep.url,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(step: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _stepTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stepSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    _StepContent(
                      step: _step,
                      urlCtrl: _urlCtrl,
                      patCtrl: _patCtrl,
                      backupUrlCtrl: _backupUrlCtrl,
                      backupTokenCtrl: _backupTokenCtrl,
                      hasPat: _hasPat,
                      editingPat: _editingPat,
                      hasBackupToken: _hasBackupToken,
                      editingBackupToken: _editingBackupToken,
                      onPatToggle: () => setState(() => _editingPat = !_editingPat),
                      onBackupTokenToggle: () =>
                          setState(() => _editingBackupToken = !_editingBackupToken),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (_probeResult != null && _probeResult!.status != ProbeStatus.ok)
                      const SizedBox(height: 16),
                    const SizedBox(height: 32),
                    _PrimaryButton(
                      step: _step,
                      saving: _saving,
                      probeResult: _probeResult,
                      onPressed: _step == OnboardStep.done
                          ? () => Navigator.of(context).pop(true)
                          : _step == OnboardStep.backup
                              ? _probeAndFinish
                              : _saveAndNext,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case OnboardStep.url:
        return 'Firefly server';
      case OnboardStep.pat:
        return 'Access token';
      case OnboardStep.backup:
        return 'PC backup (optional)';
      case OnboardStep.done:
        return 'Done';
    }
  }

  String get _stepSubtitle {
    switch (_step) {
      case OnboardStep.url:
        return 'Enter your Firefly III base URL, e.g. http://firefly.cachyos.ts.net';
      case OnboardStep.pat:
        return 'Create a PAT in Firefly → Options → Profile → OAuth → Create new token.';
      case OnboardStep.backup:
        return 'Enter your PC backup sidecar URL and token to enable automatic snapshots after every sync.';
      case OnboardStep.done:
        return 'You are ready to use Firefly III offline. Sync happens automatically when the server is reachable.';
    }
  }
}

/// Renders the input fields for the current step.
class _StepContent extends StatelessWidget {
  const new({
    required this.step,
    required this.urlCtrl,
    required this.patCtrl,
    required this.backupUrlCtrl,
    required this.backupTokenCtrl,
    required this.hasPat,
    required this.editingPat,
    required this.hasBackupToken,
    required this.editingBackupToken,
    required this.onPatToggle,
    required this.onBackupTokenToggle,
  });

  final OnboardStep step;
  final TextEditingController urlCtrl;
  final TextEditingController patCtrl;
  final TextEditingController backupUrlCtrl;
  final TextEditingController backupTokenCtrl;
  final bool hasPat;
  final bool editingPat;
  final bool hasBackupToken;
  final bool editingBackupToken;
  final VoidCallback onPatToggle;
  final VoidCallback onBackupTokenToggle;

  @override
  Widget build(BuildContext context) {
    switch (step) {
      case OnboardStep.url:
        return _TextField(
          controller: urlCtrl,
          label: 'Base URL',
          hint: 'http://firefly.cachyos.ts.net',
          icon: Icons.language,
        );
      case OnboardStep.pat:
        return Column(
          children: [
            _PatField(
              controller: patCtrl,
              hasToken: hasPat,
              editing: editingPat,
              onToggle: onPatToggle,
            ),
          ],
        );
      case OnboardStep.backup:
        return Column(
          children: [
            _TextField(
              controller: backupUrlCtrl,
              label: 'Backup sidecar URL',
              hint: 'http://192.168.1.10:8095 (optional)',
              icon: Icons.backup,
            ),
            const SizedBox(height: 16),
            _PatField(
              controller: backupTokenCtrl,
              label: 'Sidecar token',
              hasToken: hasBackupToken,
              editing: editingBackupToken,
              onToggle: onBackupTokenToggle,
              hint: 'Leave empty to run backup without a token',
            ),
          ],
        );
      case OnboardStep.done:
        return const _DoneView();
    }
  }
}

/// Write-only PAT field: masked dots + Replace/Clear once stored.
class _PatField extends StatelessWidget {
  const new({
    required this.controller,
    required this.hasToken,
    required this.editing,
    required this.onToggle,
    this.label = 'Personal access token',
    this.hint,
  });

  final TextEditingController controller;
  final bool hasToken;
  final bool editing;
  final VoidCallback onToggle;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    if (hasToken && !editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.vpn_key, size: 20),
                const SizedBox(width: 12),
                const Text('••••••••••••••••'),
                const Spacer(),
                TextButton(
                  onPressed: onToggle,
                  child: const Text('Replace'),
                ),
                TextButton(
                  onPressed: () {
                    controller.clear();
                    onToggle();
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint!, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color)),
          ],
        ],
      );
    }
    return _TextField(
      controller: controller,
      label: label,
      hint: hint ?? 'Paste your PAT here (write-only)',
      icon: Icons.vpn_key,
      obscureText: true,
    );
  }
}

/// A single-line text field with label, hint, leading icon, and optional obscure text.
class _TextField extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.next,
    );
  }
}

/// Primary action button: Save & Next / Continue / Done.
class _PrimaryButton extends StatelessWidget {
  const new({
    required this.step,
    required this.saving,
    required this.probeResult,
    required this.onPressed,
  });

  final OnboardStep step;
  final bool saving;
  final ProbeResult? probeResult;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = step == OnboardStep.done
        ? 'Done'
        : step == OnboardStep.backup
            ? 'Continue'
            : 'Save & next';

    return SizedBox(
      height: 52,
      child: saving
          ? const Center(child: CircularProgressIndicator())
          : FilledButton(
              onPressed: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  if (step == OnboardStep.backup && probeResult != null) ...[
                    const SizedBox(width: 12),
                    _ProbeChip(result: probeResult!),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Small chip showing probe status on the backup step.
class _ProbeChip extends StatelessWidget {
  const new({required this.result});

  final ProbeResult result;

  Color _color() {
    switch (result.status) {
      case ProbeStatus.ok:
        return Colors.green;
      case ProbeStatus.unreachable:
        return Colors.amber;
      case ProbeStatus.unauthorized:
      case ProbeStatus.unexpectedStatus:
        return Colors.red;
    }
  }

  IconData _icon() {
    switch (result.status) {
      case ProbeStatus.ok:
        return Icons.check_circle;
      case ProbeStatus.unreachable:
        return Icons.error_outline;
      case ProbeStatus.unauthorized:
      case ProbeStatus.unexpectedStatus:
        return Icons.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(_icon(), size: 16, color: _color()),
      label: Text(
        result.status == ProbeStatus.ok ? 'Server reachable' : 'Server unreachable',
        style: const TextStyle(fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Done view on the final step.
class _DoneView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Setup complete',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Firefly III works fully offline. Sync starts automatically when the server is reachable.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Step progress indicator.
class _StepIndicator extends StatelessWidget {
  const new({required this.step});

  final OnboardStep step;

  @override
  Widget build(BuildContext context) {
    const values = OnboardStep.values;
    final idx = values.indexOf(step);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < values.length; i++)
            _StepChip(
              label: _stepShortLabel(values[i]),
              active: i == idx,
              done: i < idx,
            ),
        ],
      ),
    );
  }

  String _stepShortLabel(OnboardStep s) {
    switch (s) {
      case OnboardStep.url:
        return 'Server';
      case OnboardStep.pat:
        return 'Token';
      case OnboardStep.backup:
        return 'Backup';
      case OnboardStep.done:
        return 'Done';
    }
  }
}

/// One chip in the step indicator.
class _StepChip extends StatelessWidget {
  const new({required this.label, required this.active, required this.done});

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primary
            : done
                ? Colors.green.withValues(alpha: 0.2)
                : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active
              ? Theme.of(context).colorScheme.onPrimary
              : done
                  ? Colors.green
                  : Theme.of(context).textTheme.bodySmall?.color,
          fontWeight: active || done ? FontWeight.w600 : FontWeight.normal,
          fontSize: 11,
        ),
      ),
    );
  }
}
