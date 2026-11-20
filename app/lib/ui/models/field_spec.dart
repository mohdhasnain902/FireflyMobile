import 'dart:convert';

import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart'
    show SyncBookkeeping;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form field kinds the generic offline CRUD screens understand.
///
/// Every kind maps 1:1 onto a widget in the generic form (S3) and a typed
/// value in the [FieldSpec]-driven values map:
///
/// - [text] single-line → `String?`
/// - [multiline] notes/description → `String?`
/// - [decimal] money strings as typed by Firefly (`'12.34'`) → `String?`
/// - [integer] small counts (`skip`, `size`) → `int?`
/// - [boolean] toggles → `bool`
/// - [date] date-only pickers → `DateTime?` (always UTC, see SyncBookkeeping)
/// - [choice] dropdown over a grounded enum → `String?`
/// - [reference] dropdown over local rows → `String?` (the local row id, or
///   a natural key such as the currency code)
/// - [json] multiline JSON editors (`tagsJson`, `triggersJson`) → `String?`
enum FieldKind {
  /// Single-line text input.
  text,

  /// Multi-line text input (notes, description).
  multiline,

  /// Decimal number kept as a string (all Firefly money fields are strings).
  decimal,

  /// Whole-number integer.
  integer,

  /// On/off toggle.
  boolean,

  /// Date-only picker (UTC midnight).
  date,

  /// Dropdown over a fixed, server-grounded list of values.
  choice,

  /// Dropdown over rows loaded from a local provider.
  reference,

  /// Multi-line JSON text with parse validation.
  json,

  /// Tag chips (Firefly's tag input): typing a tag and pressing enter turns
  /// it into a chip, and previously used tags are offered in a dropdown.
  /// The value is still the JSON-array string the entity stores, so configs
  /// need no change beyond the kind.
  tags,
}

/// One selectable row in a [FieldKind.reference] dropdown.
class RefOption {
  /// Creates an option whose [id] is written into the form values map.
  const new({required this.id, required this.label});

  /// Value stored in the form map — usually the local row id; for currencies
  /// it is the ISO code because Firefly wires `currency_code`, not a row id.
  final String id;

  /// Human-readable label shown in the dropdown.
  final String label;
}

/// Declarative description of one form field.
///
/// The generic form (S3) renders itself entirely from these specs; entity
/// config files never touch widgets. [key] matches the entity's camelCase
/// property name so the config's typed `createWith`/`editWith` closures can
/// read the values map without reflection.
class FieldSpec {
  /// Declares a field. [key] must match the entity property name exactly.
  const new({
    required this.key,
    required this.label,
    required this.kind,
    this.required = false,
    this.requiredWhen,
    this.hint,
    this.choices = const <String>[],
    this.refOptions,
    this.positive = false,
    this.defaultValue,
    this.isValid,
  });

  /// Entity property name this field reads and writes (camelCase).
  final String key;

  /// Label shown above the input.
  final String label;

  /// Which widget and value type this field uses.
  final FieldKind kind;

  /// Whether a non-empty value is mandatory on create and edit.
  final bool required;

  /// Extra condition making the field required, evaluated against the whole
  /// values map — e.g. Firefly's `required_if:type,asset` on `account_role`.
  final bool Function(Map<String, Object?> values)? requiredWhen;

  /// Secondary help text under the input.
  final String? hint;

  /// Allowed values for [FieldKind.choice]. Every list in this project is
  /// grounded in the Firefly 6.7.9 source (see entity_configs.dart).
  final List<String> choices;

  /// Provider yielding the dropdown rows for [FieldKind.reference].
  final FutureProvider<List<RefOption>>? refOptions;

  /// Whether a [FieldKind.decimal] value must be greater than zero.
  ///
  /// Grounded in Firefly's `IsValidPositiveAmount` where the server enforces
  /// the same rule (transactions, bills, budget limits, subscriptions).
  final bool positive;

  /// Initial value for a newly created row (e.g. `active: true`).
  final Object? defaultValue;

  /// Cross-field validation hook — receives the current values map and the
  /// field's own value. Returns an error message, or null when valid. Used
  /// for grounded pairs like budget-limit `end` after `start`.
  final String? Function(Object? value, Map<String, Object?> all)? isValid;
}

// ---------------------------------------------------------------------------
// Typed value helpers used by entity config closures and the generic form.
// ---------------------------------------------------------------------------

/// Reads a required text/decimal value after validation has run.
///
/// Throws [StateError] instead of silently null-casting so a config bug
/// surfaces as a clear message rather than a `TypeError` deep in a form.
String reqString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String) {
    throw StateError('Field "$key" missing or not a string after validation');
  }
  return value;
}

/// Reads an optional text/decimal value; blank normalises to null so the wire
/// payload omits empty attributes.
String? optString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Reads an optional integer; null/blank normalises to null.
int? optInt(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is int) return value;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Reads a date field; always UTC ([SyncBookkeeping] contract — every
/// DateTime in the app is UTC so equality holds across round-trips).
DateTime? optDate(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is DateTime) return value.toUtc();
  return null;
}

/// Reads a boolean field, defaulting when the map has no entry yet.
bool boolValue(
  Map<String, Object?> values,
  String key, {
  bool fallback = false,
}) {
  final value = values[key];
  if (value is bool) return value;
  return fallback;
}

/// Validates one field against its spec, given the full values map.
///
/// Returns an error message for the UI, or null when valid. Lives here rather
/// than in the widget so the rules are unit-testable without a widget tree.
String? validateField(FieldSpec spec, Object? value, Map<String, Object?> all) {
  // Resolve "required": the static flag, or the cross-field condition.
  final conditionallyRequired = spec.requiredWhen?.call(all) ?? false;
  final required = spec.required || conditionallyRequired;

  switch (spec.kind) {
    case FieldKind.boolean:
      // A toggle always has a value; nothing to check.
      return null;

    case FieldKind.tags:
      // The chips widget always emits either null/'' or a JSON array of
      // non-blank strings, so a decode here is a safety net rather than a
      // user-facing validation.
      final tagsRaw = value is String ? value.trim() : '';
      if (tagsRaw.isEmpty) {
        return required ? '${spec.label} is required' : null;
      }
      try {
        final decoded = jsonDecode(tagsRaw);
        if (decoded is! List) return '${spec.label} must be a list of tags';
      } on FormatException {
        return '${spec.label} must be a list of tags';
      }
      return spec.isValid?.call(value, all);

    case FieldKind.text:
    case FieldKind.multiline:
    case FieldKind.decimal:
    case FieldKind.integer:
    case FieldKind.json:
      final text = value is String ? value.trim() : '';
      if (required && text.isEmpty) return '${spec.label} is required';
      if (text.isEmpty) return null; // optional + blank → fine

      if (spec.kind == FieldKind.integer &&
          !RegExp(r'^-?\d+$').hasMatch(text)) {
        return '${spec.label} must be a whole number';
      }
      if (spec.kind == FieldKind.decimal) {
        // Firefly amount shape: digits with an optional fraction.
        if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
          return '${spec.label} must be a number (e.g. 12.34)';
        }
        if (spec.positive && (double.tryParse(text) ?? 0) <= 0) {
          return '${spec.label} must be greater than zero';
        }
      }
      if (spec.kind == FieldKind.json) {
        try {
          jsonDecode(text);
        } on FormatException {
          return '${spec.label} must be valid JSON';
        }
      }
      return spec.isValid?.call(value, all);

    case FieldKind.date:
      if (required && value is! DateTime) return '${spec.label} is required';
      if (value is DateTime) return spec.isValid?.call(value, all);
      return null;

    case FieldKind.choice:
      final text = value is String ? value : '';
      if (required && text.isEmpty) return '${spec.label} is required';
      if (text.isNotEmpty && !spec.choices.contains(text)) {
        return '${spec.label} must be one of ${spec.choices.join(', ')}';
      }
      return null;

    case FieldKind.reference:
      final text = value is String ? value : '';
      if (required && text.isEmpty) return '${spec.label} is required';
      return spec.isValid?.call(value, all);
  }
}
