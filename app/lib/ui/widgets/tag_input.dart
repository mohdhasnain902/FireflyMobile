import 'dart:convert';

import 'package:firefly_mobile/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firefly's tag input: type a tag, press enter (or comma), and it becomes a
/// chip; backspace in the empty field removes the last chip; the history
/// button lists tags already used in the book for one-tap re-use.
///
/// The widget speaks the same JSON-array string the entity stores
/// (`tagsJson`: `'["card","travel"]'`) so switching a field to
/// [FieldKind.tags] needs no change in the entity configs.
class TagInputField extends ConsumerStatefulWidget {
  /// Creates the input. [onChanged] receives the encoded JSON array, or null
  /// once every tag has been removed.
  const new({
    required this.label,
    required this.onChanged,
    this.hint,
    this.errorText,
    this.enabled = true,
    this.value,
    super.key,
  });

  /// Field label, shown above the chips like every other form input.
  final String label;

  /// Secondary help text shown under the field when there is no error.
  final String? hint;

  /// Validation message from the form's last save attempt.
  final String? errorText;

  /// Whether the field accepts input (read-only forms disable it).
  final bool enabled;

  /// Current value as the stored JSON-array string.
  final String? value;

  /// Called with the new JSON-array string (null when empty).
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<TagInputField> createState() => _TagInputFieldState();
}

class _TagInputFieldState extends ConsumerState<TagInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final List<String> _tags = _decode(widget.value);

  static List<String> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded
          .whereType<String>()
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    } on FormatException {
      return <String>[];
    }
  }

  void _emit() {
    widget.onChanged(_tags.isEmpty ? null : jsonEncode(_tags));
  }

  /// Adds [raw] as a tag unless it is blank or already present (Firefly keeps
  /// tags unique per transaction, case-insensitively).
  void _add(String raw) {
    final tag = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (tag.isEmpty) return;
    if (_tags.any((existing) => existing.toLowerCase() == tag.toLowerCase())) {
      _controller.clear();
      return;
    }
    setState(() => _tags.add(tag));
    _controller.clear();
    _emit();
  }

  void _remove(String tag) {
    setState(() => _tags.remove(tag));
    _emit();
  }

  /// Enter or comma commits the typed text; backspace on an empty field
  /// deletes the last chip (the behaviour of every tag field).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _add(_controller.text);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controller.text.isEmpty &&
        _tags.isNotEmpty) {
      _remove(_tags.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickFromHistory() async {
    final suggestions = await ref.read(tagSuggestionsProvider.future);
    if (!mounted) return;
    final unused = suggestions
        .where(
          (tag) => !_tags.any(
            (existing) => existing.toLowerCase() == tag.toLowerCase(),
          ),
        )
        .toList();
    if (unused.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other tags in your book yet')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final tag in unused)
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text(tag),
                onTap: () => Navigator.of(context).pop(tag),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _add(picked);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Focus(
        onKeyEvent: _onKey,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.hint,
            errorText: widget.errorText,
            border: const OutlineInputBorder(),
            suffixIcon: widget.enabled
                ? IconButton(
                    tooltip: 'Previously used tags',
                    icon: const Icon(Icons.expand_more),
                    onPressed: _pickFromHistory,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        onDeleted: widget.enabled ? () => _remove(tag) : null,
                      ),
                  ],
                ),
              if (_tags.isNotEmpty) const SizedBox(height: 6),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Type a tag and press enter',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: _add,
                onChanged: (text) {
                  // A comma commits the tag, exactly like Firefly's tag field.
                  if (text.contains(',')) {
                    for (final part in text.split(',')) {
                      _add(part);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
