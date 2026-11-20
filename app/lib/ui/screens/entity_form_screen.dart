import 'package:firefly_mobile/core/currency/exchange_rates.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/models/field_spec.dart';
import 'package:firefly_mobile/ui/widgets/tag_input.dart';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Generic create/edit form driven entirely by an [EntityConfig] (P2.2.2/3).
///
/// One widget serves all 14 entities: the config supplies the field specs,
/// the defaults and the typed write closures; this screen only renders the
/// inputs, validates through [validateField] and calls the repository. It
/// never touches the network — every write lands in SQLite and queues an op.
///
/// Modes:
/// - **create** (`existing == null`): values seeded from per-field
///   `defaultValue`s; required date fields start at today (UTC midnight).
/// - **edit**: values seeded from `config.toValues(existing)`.
/// - **read-only** (`!config.canWrite`): every input disabled, no save
///   action — used for pull-only entities such as currencies.
class EntityFormScreen<T extends SyncBookkeeping>
    extends ConsumerStatefulWidget {
  /// Opens the form for [existing] (edit) or a blank row (create).
  const new({required this.config, this.existing, super.key});

  /// The entity definition supplying fields and write path.
  final EntityConfig<T> config;

  /// The row being edited; null means "create new".
  final T? existing;

  @override
  ConsumerState<EntityFormScreen<T>> createState() =>
      _EntityFormScreenState<T>();
}

class _EntityFormScreenState<T extends SyncBookkeeping>
    extends ConsumerState<EntityFormScreen<T>> {
  /// Single source of truth for every field value, keyed by FieldSpec.key.
  late final Map<String, Object?> _values;

  /// Text controllers, one per text-like field, created once in [initState]
  /// so keystrokes never rebuild into a fresh controller (cursor would jump).
  final Map<String, TextEditingController> _controllers = {};

  /// Per-field error messages produced by the last save attempt.
  final Map<String, String> _errors = {};

  /// Whether a write is currently in flight (double-submit guard).
  bool _saving = false;

  EntityConfig<T> get _config => widget.config;

  bool get _editing => widget.existing != null;

  /// No save affordances for pull-only entities or configs without a repo.
  bool get _writable => _config.canWrite && _config.repoOf != null && !_saving;

  @override
  void initState() {
    super.initState();
    _values = _seedValues();
    for (final spec in _config.fields) {
      if (_isTextLike(spec.kind)) {
        _controllers[spec.key] = TextEditingController(
          text: _values[spec.key]?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Builds the initial values map for the form.
  ///
  /// Edit mode starts from the row itself; create mode applies each spec's
  /// [FieldSpec.defaultValue] and pins required date fields to *today* in
  /// UTC midnight form (the [SyncBookkeeping] contract: every DateTime in
  /// the app is UTC).
  Map<String, Object?> _seedValues() {
    if (_editing) {
      return Map<String, Object?>.of(_config.toValues(widget.existing!));
    }
    final today = DateTime.now().toUtc();
    final utcToday = DateTime.utc(today.year, today.month, today.day);
    final values = <String, Object?>{};
    for (final spec in _config.fields) {
      if (spec.defaultValue != null) {
        values[spec.key] = spec.defaultValue;
      }
      if (spec.kind == FieldKind.date && spec.required) {
        values[spec.key] ??= utcToday;
      }
    }
    return values;
  }

  /// Which kinds are backed by a [TextEditingController].
  bool _isTextLike(FieldKind kind) =>
      kind == FieldKind.text ||
      kind == FieldKind.multiline ||
      kind == FieldKind.decimal ||
      kind == FieldKind.integer ||
      kind == FieldKind.json;

  /// Validates every field against its spec; keeps the first error per field.
  bool _validateAll() {
    _errors.clear();
    for (final spec in _config.fields) {
      final error = validateField(spec, _values[spec.key], _values);
      if (error != null) _errors[spec.key] = error;
    }
    return _errors.isEmpty;
  }

  /// Validates + writes, then pops with `true` so callers can refresh.
  Future<void> _save() async {
    if (!_writable) return;
    if (!_validateAll()) {
      setState(() {}); // surface the per-field errors
      return;
    }
    setState(() => _saving = true);
    try {
      // WidgetRef-based loader (see EntityConfig.repoOf doc).
      final repo = await _config.repoOf!(ref);
      final existing = widget.existing;
      if (existing == null) {
        await repo.create(
          (id, updatedAt, seq) => _config.createWith(
            _values,
            id: id,
            updatedAt: updatedAt,
            seq: seq,
          ),
        );
      } else {
        await repo.update(
          existing,
          (current, updatedAt, seq) => _config.editWith(
            current,
            _values,
            updatedAt: updatedAt,
            seq: seq,
          ),
        );
      }
      // The list screen + app-bar sync badge watch these — invalidate so
      // the list re-queries and the badge refreshes the pending count.
      ref
        ..invalidate(_config.listProvider)
        ..invalidate(pendingOpsCountProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $error')));
    }
  }

  /// Discards edits and pops with `false`.
  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final canWrite = _config.canWrite && _config.repoOf != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Edit ${_config.singular}' : 'New ${_config.singular}',
        ),
        actions: [
          if (canWrite)
            TextButton(
              onPressed: _writable ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final spec in _config.fields) _buildField(spec),
            const SizedBox(height: 24),
            if (canWrite)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _cancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _writable ? _save : null,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            if (!canWrite)
              const Text(
                'Read-only — this entity cannot be edited on the phone.',
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  /// Renders the input widget matching `spec.kind`.
  Widget _buildField(FieldSpec spec) {
    final error = _errors[spec.key];
    final enabled = _config.canWrite && _config.repoOf != null && !_saving;
    switch (spec.kind) {
      case FieldKind.text:
      case FieldKind.decimal:
      case FieldKind.integer:
        return _buildTextField(spec, error: error, enabled: enabled);

      case FieldKind.multiline:
        return _buildTextField(
          spec,
          error: error,
          enabled: enabled,
          maxLines: 4,
        );

      case FieldKind.json:
        return _buildTextField(
          spec,
          error: error,
          enabled: enabled,
          maxLines: 6,
          mono: true,
        );

      case FieldKind.boolean:
        return SwitchListTile(
          title: Text(spec.label),
          subtitle: error == null ? _hint(spec) : Text(error),
          value: boolValue(_values, spec.key),
          onChanged: enabled
              ? (next) => setState(() => _values[spec.key] = next)
              : null,
        );

      case FieldKind.date:
        return _buildDateField(spec, error: error, enabled: enabled);

      case FieldKind.choice:
        return _buildChoiceField(spec, error: error, enabled: enabled);

      case FieldKind.reference:
        return _buildReferenceField(spec, error: error, enabled: enabled);

      case FieldKind.tags:
        // Chips speak the stored JSON-array string; the widget owns typing,
        // enter-to-commit, backspace-to-remove and the history dropdown, so
        // the form only mirrors its value into the values map.
        return TagInputField(
          label: spec.label,
          hint: spec.hint,
          errorText: error,
          enabled: enabled,
          value: _values[spec.key]?.toString(),
          onChanged: (next) => setState(() => _values[spec.key] = next),
        );
    }
  }

  /// Shared text input for text/decimal/integer/multiline/json kinds.
  Widget _buildTextField(
    FieldSpec spec, {
    required String? error,
    required bool enabled,
    int maxLines = 1,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[spec.key],
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: spec.kind == FieldKind.decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : spec.kind == FieldKind.integer
            ? TextInputType.number
            : null,
        style: mono ? const TextStyle(fontFamily: 'monospace') : null,
        decoration: InputDecoration(
          labelText: spec.label,
          hintText: spec.hint,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) => _onFieldChanged(spec.key, text),
      ),
    );
  }

  /// Date picker row; stores a UTC midnight DateTime.
  Widget _buildDateField(
    FieldSpec spec, {
    required String? error,
    required bool enabled,
  }) {
    final value = _values[spec.key];
    final date = value is DateTime ? value.toUtc() : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: spec.label,
          errorText: error,
          border: const OutlineInputBorder(),
          suffixIcon: enabled && date != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _values[spec.key] = null),
                )
              : null,
        ),
        child: InkWell(
          onTap: enabled ? () => _pickDate(spec) : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  date == null ? (spec.hint ?? 'Not set') : _formatDate(date),
                ),
              ),
              if (enabled) const Icon(Icons.calendar_today, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the Material date picker and writes the chosen UTC date.
  Future<void> _pickDate(FieldSpec spec) async {
    final current = _values[spec.key];
    final now = DateTime.now().toUtc();
    final initial = current is DateTime
        ? current.toUtc()
        : DateTime.utc(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.utc(2000),
      lastDate: DateTime.utc(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _values[spec.key] = DateTime.utc(picked.year, picked.month, picked.day);
    });
  }

  /// Handles a field value change, applying currency conversion when a
  /// currency field is changed (e.g. amount follows currency).
  void _onFieldChanged(String key, Object? value) {
    final old = _values[key];
    _values[key] = value;
    setState(() {});
    if (key == 'currencyCode' || key == 'foreignCurrencyCode') {
      final oldCode = old is String ? old.trim() : null;
      final newCode = value is String ? value.trim() : null;
      if (oldCode != null && newCode != null && oldCode.isNotEmpty &&
          newCode.isNotEmpty && oldCode.toUpperCase() != newCode.toUpperCase()) {
        _convertPairedAmounts(key, oldCode, newCode);
      }
    }
  }

  Future<void> _convertPairedAmounts(
    String currencyKey,
    String fromCode,
    String toCode,
  ) async {
    final amountKeys = currencyKey == 'foreignCurrencyCode'
        ? const <String>['foreignAmount']
        : const <String>['amount', 'openingBalance', 'virtualBalance'];
    // Only convert if at least one paired amount is present.
    final hasAny = amountKeys.any((k) {
      final v = _values[k];
      if (v == null) return false;
      final s = v.toString().trim();
      return s.isNotEmpty && double.tryParse(s) != null;
    });
    if (!hasAny) return;
    try {
      final store = await ref.read(currencyDisplayStoreProvider.future);
      var settings = await ref.read(currencyDisplayProvider.future);
      settings = await ensureConversionRates(
        store,
        settings,
        preferredBases: <String>{
          'usd',
          'eur',
          fromCode.toLowerCase(),
          toCode.toLowerCase(),
        },
      );
      ref.invalidate(currencyDisplayProvider);
      if (!mounted) return;
      final rate = settings.convert(1.0, fromCode, toCode);
      if (rate == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No exchange rate available for $fromCode → $toCode. '
                'Open Settings → Currency & conversion and refresh rates.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      var changed = false;
      for (final k in amountKeys) {
        if (!_values.containsKey(k) && _controllers[k] == null) continue;
        final raw = _controllers[k]?.text ?? _values[k]?.toString();
        if (raw == null) continue;
        final n = double.tryParse(raw.trim());
        if (n == null) continue;
        final converted = n * rate;
        final text = _formatConvertedAmount(converted);
        _values[k] = text;
        _controllers[k]?.text = text;
        changed = true;
      }
      if (changed && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Amounts converted to ${toCode.toUpperCase()}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Rates unavailable; leave amounts unchanged but log for diagnosis.
      debugPrint('[currency] conversion failed $fromCode->$toCode: $e');
    }
  }

  String _formatConvertedAmount(double value) {
    final abs = value.abs();
    if (abs == 0) return '0';
    // Preserve a sensible number of decimals for money.
    String s;
    if (abs >= 1) {
      s = value.toStringAsFixed(2);
    } else {
      s = value.toStringAsFixed(6);
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    // Trim trailing zeros for .00 in >=1 case? keep 2 decimals for clarity.
    if (abs >= 1 && s.contains('.')) {
      // keep as-is (2 dp)
    }
    return s;
  }

  /// Dropdown over a server-grounded [FieldSpec.choices] list.
  Widget _buildChoiceField(
    FieldSpec spec, {
    required String? error,
    required bool enabled,
  }) {
    final current = _values[spec.key];
    final selected = current is String ? current : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _validSelection(selected, spec.choices),
        decoration: InputDecoration(
          labelText: spec.label,
          hintText: spec.hint,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final choice in spec.choices)
            DropdownMenuItem(value: choice, child: Text(choice)),
        ],
        // Constrain the dropdown's inner Row: without expansion the hint/item
        // IndexedStack sizes to the *widest* child and overflows a 320px
        // field (budgets hint overflowed by ~495px in the sweep tests).
        isExpanded: true,
        onChanged: enabled
            ? (next) => _onFieldChanged(spec.key, next)
            : null,
      ),
    );
  }

  /// Dropdown over local rows loaded from [FieldSpec.refOptions].
  ///
  /// Handles the provider's loading/error states inline; if the form holds a
  /// value the provider no longer returns (row deleted elsewhere), the value
  /// is re-added as an item so the dropdown never throws on an unknown value.
  Widget _buildReferenceField(
    FieldSpec spec, {
    required String? error,
    required bool enabled,
  }) {
    final provider = spec.refOptions;
    if (provider == null) {
      // Config bug: reference field without options — degrade to text.
      return _buildTextField(spec, error: error, enabled: enabled);
    }
    final asyncOptions = ref.watch(provider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: asyncOptions.when(
        loading: () => InputDecorator(
          decoration: InputDecoration(
            labelText: spec.label,
            border: const OutlineInputBorder(),
          ),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
        error: (loadError, _) => InputDecorator(
          decoration: InputDecoration(
            labelText: spec.label,
            errorText: 'Failed to load ${spec.label.toLowerCase()}',
            border: const OutlineInputBorder(),
          ),
          child: Text(loadError.toString(), maxLines: 2),
        ),
        data: (options) {
          final current = _values[spec.key];
          final selected = current is String ? current : null;
          final known = options.map((option) => option.id).toSet();
          final items = [
            for (final option in options)
              DropdownMenuItem(value: option.id, child: Text(option.label)),
          ];
          final allowedIds = <String>[...known];
          // Keep an unknown pre-seeded value selectable instead of crashing.
          if (selected != null && !known.contains(selected)) {
            items.add(DropdownMenuItem(value: selected, child: Text(selected)));
            allowedIds.add(selected);
          }
          return DropdownButtonFormField<String>(
            initialValue: _validSelection(selected, allowedIds),
            decoration: InputDecoration(
              labelText: spec.label,
              hintText: spec.hint,
              errorText: error,
              border: const OutlineInputBorder(),
            ),
            items: items,
            // Same expansion guard as [_buildChoiceField]: reference labels
            // can be longer than a 320px field row.
            isExpanded: true,
            onChanged: enabled
                ? (next) => _onFieldChanged(spec.key, next)
                : null,
          );
        },
      ),
    );
  }

  /// Returns [selected] only when it is one of [allowed]; else null.
  String? _validSelection(String? selected, List<String> allowed) {
    if (selected == null) return null;
    return allowed.contains(selected) ? selected : null;
  }

  /// Optional hint line for kinds that do not use InputDecoration.errorText.
  Widget? _hint(FieldSpec spec) => spec.hint == null ? null : Text(spec.hint!);

  /// Date label for the date field body (en-ISO, unambiguous + i18n-free).
  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
