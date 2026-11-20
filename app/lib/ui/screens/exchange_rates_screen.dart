import 'package:firefly_mobile/core/currency/exchange_rates.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart'
    show currencyRefOptionsProvider;
import 'package:firefly_mobile/ui/models/field_spec.dart' show RefOption;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firefly's "Exchange rates" screen, phone edition.
///
/// Online rates (fawazahmed0 feed) cover the ISO currencies, but a custom
/// currency — BTC, a loyalty point, an in-game token — has no feed. Firefly
/// lets you type both directions of a pair by hand, so this screen does too:
/// "1 BTC = 65000 USD" and "65000.34 USD = 1 BTC" are stored as two entries
/// and both are honoured exactly as typed (they are not forced to be
/// reciprocals). Manual rates win over fetched ones and work offline.
class ExchangeRatesScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<ExchangeRatesScreen> createState() =>
      _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends ConsumerState<ExchangeRatesScreen> {
  /// Codes offered in the pickers: every currency in the book, plus the common
  /// ISO set so a pair can be entered before the currency is pulled.
  List<String> _codes(List<String> fromBook) {
    final codes = <String>{...fromBook, ...kCommonCurrencyCodes};
    final list = codes.toList()..sort();
    return list;
  }

  Future<void> _save(
    Map<String, Map<String, double>> next,
  ) async {
    final store = await ref.read(currencyDisplayStoreProvider.future);
    await store.saveManualRates(next);
    ref.invalidate(currencyDisplayProvider);
  }

  /// Removes both directions of [from] ↔ [to].
  Future<void> _delete(
    Map<String, Map<String, double>> rates,
    String from,
    String to,
  ) async {
    final next = <String, Map<String, double>>{
      for (final entry in rates.entries)
        entry.key: Map<String, double>.of(entry.value),
    };
    next[from]?.remove(to);
    if (next[from]?.isEmpty ?? false) next.remove(from);
    next[to]?.remove(from);
    if (next[to]?.isEmpty ?? false) next.remove(to);
    await _save(next);
  }

  Future<void> _edit({
    required Map<String, Map<String, double>> rates,
    required List<String> codes,
    String? initialFrom,
    String? initialTo,
  }) async {
    final result = await showDialog<_RatePair>(
      context: context,
      builder: (_) => _RateDialog(
        codes: codes,
        initialFrom: initialFrom,
        initialTo: initialTo,
        fromRate: initialFrom == null
            ? null
            : rates[initialFrom]?[initialTo ?? ''],
        toRate: initialFrom == null
            ? null
            : rates[initialTo ?? '']?[initialFrom],
      ),
    );
    if (result == null) return;
    final next = <String, Map<String, double>>{
      for (final entry in rates.entries)
        entry.key: Map<String, double>.of(entry.value),
    };
    // Both directions are stored exactly as typed; a blank one is left out so
    // the other direction can still be derived by the conversion lookup.
    if (result.fromRate != null) {
      (next[result.from] ??= <String, double>{})[result.to] = result.fromRate!;
    } else {
      next[result.from]?.remove(result.to);
      if (next[result.from]?.isEmpty ?? false) next.remove(result.from);
    }
    if (result.toRate != null) {
      (next[result.to] ??= <String, double>{})[result.from] = result.toRate!;
    } else {
      next[result.to]?.remove(result.from);
      if (next[result.to]?.isEmpty ?? false) next.remove(result.to);
    }
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(currencyDisplayProvider);
    final bookCodes = ref.watch(currencyRefOptionsProvider).value ??
        const <RefOption>[];
    final codes = _codes(bookCodes.map((RefOption option) => option.id).toList());
    return Scaffold(
      appBar: AppBar(title: const Text('Exchange rates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: settingsAsync.value == null
            ? null
            : () => _edit(rates: settingsAsync.value!.manualRates, codes: codes),
        icon: const Icon(Icons.add),
        label: const Text('Add rate'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Rates unavailable: $error'),
        ),
        data: (settings) {
          final pairs = <(String, String, double, double?)>[];
          final seen = <String>{};
          for (final from in settings.manualRates.keys.toList()..sort()) {
            for (final to in settings.manualRates[from]!.keys.toList()..sort()) {
              final key = ([from, to]..sort()).join('↔');
              if (!seen.add(key)) continue;
              pairs.add((
                from,
                to,
                settings.manualRates[from]![to]!,
                settings.manualRates[to]?[from],
              ));
            }
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Manual rates are checked before the online feed, so a '
                  'custom currency converts exactly as you enter it — '
                  'both directions, offline included.',
                ),
              ),
              if (pairs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No manual rates yet. Add one with the button.'),
                ),
              for (final pair in pairs)
                ListTile(
                  leading: const Icon(Icons.currency_exchange),
                  title: Text(
                    '1 ${pair.$1} = ${_fmt(pair.$3)} ${pair.$2}',
                  ),
                  subtitle: Text(
                    pair.$4 == null
                        ? '1 ${pair.$2} = ${_fmt(1 / pair.$3)} ${pair.$1} '
                            '(derived)'
                        : '1 ${pair.$2} = ${_fmt(pair.$4!)} ${pair.$1}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(
                          rates: settings.manualRates,
                          codes: codes,
                          initialFrom: pair.$1,
                          initialTo: pair.$2,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            _delete(settings.manualRates, pair.$1, pair.$2),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Money-free formatting: up to 6 decimals, trailing zeros trimmed.
  static String _fmt(double value) {
    if (value == 0) return '0';
    String text;
    if (value >= 1) {
      text = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    } else {
      text = value.toStringAsFixed(6);
    }
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }
}

/// One pair as typed by the user: 1 [from] = [fromRate] [to], and the reverse.
class _RatePair {
  const _RatePair({
    required this.from,
    required this.to,
    required this.fromRate,
    required this.toRate,
  });

  final String from;
  final String to;
  final double? fromRate;
  final double? toRate;
}

/// Dialog entering both directions of one currency pair.
class _RateDialog extends StatefulWidget {
  const _RateDialog({
    required this.codes,
    this.initialFrom,
    this.initialTo,
    this.fromRate,
    this.toRate,
  });

  final List<String> codes;
  final String? initialFrom;
  final String? initialTo;
  final double? fromRate;
  final double? toRate;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late String _from = widget.initialFrom ??
      (widget.codes.contains('BTC') ? 'BTC' : widget.codes.first);
  late String _to = widget.initialTo ??
      (widget.codes.contains('USD') ? 'USD' : widget.codes.last);
  late final TextEditingController _fromController = TextEditingController(
    text: widget.fromRate?.toString() ?? '',
  );
  late final TextEditingController _toController = TextEditingController(
    text: widget.toRate?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  /// Typing one side fills the other with its reciprocal until the other side
  /// is edited by hand — the pair stays freely editable in both directions.
  void _onFromChanged(String text) {
    final value = double.tryParse(text.trim());
    if (value != null && value != 0) {
      final inverse = 1 / value;
      _toController.text = inverse
          .toStringAsFixed(inverse >= 1 ? 2 : 8)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
  }

  void _onToChanged(String text) {
    final value = double.tryParse(text.trim());
    if (value != null && value != 0) {
      final inverse = 1 / value;
      _fromController.text = inverse
          .toStringAsFixed(inverse >= 1 ? 2 : 8)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
  }

  void _submit() {
    final fromRate = double.tryParse(_fromController.text.trim());
    final toRate = double.tryParse(_toController.text.trim());
    if (_from.isEmpty || _to.isEmpty) {
      setState(() => _error = 'Pick both currencies');
      return;
    }
    if (_from == _to) {
      setState(() => _error = 'Pick two different currencies');
      return;
    }
    if ((fromRate != null && fromRate <= 0) ||
        (toRate != null && toRate <= 0)) {
      setState(() => _error = 'Rates must be greater than zero');
      return;
    }
    if (fromRate == null && toRate == null) {
      setState(() => _error = 'Enter at least one rate');
      return;
    }
    Navigator.of(context).pop(
      _RatePair(from: _from, to: _to, fromRate: fromRate, toRate: toRate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exchange rate'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: widget.codes.contains(_from) ? _from : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final code in widget.codes)
                  DropdownMenuItem(value: code, child: Text(code)),
              ],
              onChanged: (next) => setState(() => _from = next ?? _from),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: widget.codes.contains(_to) ? _to : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Compared to',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final code in widget.codes)
                  DropdownMenuItem(value: code, child: Text(code)),
              ],
              onChanged: (next) => setState(() => _to = next ?? _to),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fromController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '1 $_from =',
                suffixText: _to,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onFromChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _toController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '1 $_to =',
                suffixText: _from,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onToChanged,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
