/// Firefly III's JSON:API envelope helpers (DESIGN §5.3).
///
/// Every read and write on the server is a JSON:API document. A single
/// resource arrives as:
///
/// ```json
/// {"data": {"type": "categories", "id": "3", "attributes": {...}}}
/// ```
///
/// and a collection arrives with `data` as an array of the same member
/// objects. The `id` lives beside `attributes`, not inside it, which is why
/// entity models cannot be (de)serialized with a flat `fromJson`.
library;

import 'dart:convert';

/// Unwraps the top-level `data` member of a JSON:API document.
///
/// Throws [FormatException] when the document is malformed rather than
/// silently returning an empty collection, because a pull that drops a page
/// of data would look like a successful sync.
Map<String, dynamic> jsonApiData(Map<String, dynamic> document) {
  final data = document['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const FormatException('JSON:API document has no `data` object');
}

/// Unwraps a JSON:API collection document into its list of member objects.
List<Map<String, dynamic>> jsonApiCollection(Map<String, dynamic> document) {
  final data = document['data'];
  if (data is! List) {
    throw const FormatException('JSON:API document has no `data` array');
  }
  return data.map((dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    throw const FormatException('JSON:API collection member is not an object');
  }).toList();
}

/// Reads the `id` of a JSON:API member object as a string, or null.
///
/// Firefly sends ids as strings; `.toString()` tolerates a server that sends
/// an integer instead.
String? jsonApiId(Map<String, dynamic> member) =>
    member['id'] == null ? null : '${member['id']}';

/// Reads the `attributes` object of a JSON:API member object.
///
/// Returns an empty map (never null) when absent, so a resource that omits
/// optional attributes still parses with defaults instead of throwing.
Map<String, dynamic> jsonApiAttributes(Map<String, dynamic> member) {
  final attributes = member['attributes'];
  if (attributes is Map<String, dynamic>) return attributes;
  if (attributes is Map) return Map<String, dynamic>.from(attributes);
  return const <String, dynamic>{};
}

/// Reads the server's `updated_at` from an attributes object, if present.
DateTime? jsonApiUpdatedAt(Map<String, dynamic> attributes) =>
    isoJsonToDateTime(attributes['updated_at']);

/// Builds the JSON:API member object for one resource.
Map<String, dynamic> jsonApiMember({
  required String type,
  required String? id,
  required Map<String, dynamic> attributes,
}) => <String, dynamic>{
  'type': type,
  'id': ?id,
  'attributes': attributes,
};

/// Reads a string attribute, returning null when absent or not a string.
///
/// Firefly omits attributes that do not apply to a resource (a transfer has no
/// `bill_id`), so null is a normal outcome rather than an error condition.
String? jsonString(Map<String, dynamic> attributes, String key) =>
    attributes[key] is String ? attributes[key] as String : null;

/// Reads a boolean attribute, falling back to [orElse] when omitted.
bool jsonBool(
  Map<String, dynamic> attributes,
  String key, {
  bool orElse = false,
}) {
  final raw = attributes[key];
  return raw is bool ? raw : orElse;
}

/// Reads an integer attribute such as `order` or `decimal_places`.
int? jsonInt(Map<String, dynamic> attributes, String key) {
  final raw = attributes[key];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

/// Reads a monetary attribute as its canonical decimal [String].
///
/// Firefly sends decimals as strings (`"49.990000000000"`), which the app keeps
/// verbatim to avoid binary-float drift in a ledger (DESIGN §5.1). A payload
/// that ever sends a number instead is converted rather than dropped.
String? jsonDecimal(Map<String, dynamic> attributes, String key) {
  final raw = attributes[key];
  if (raw is String) return raw;
  if (raw is num) return raw.toString();
  return null;
}

/// Returns [raw] as a JSON object, or an empty map if it is missing.
///
/// A rule, recurrence or split-transaction payload nests its body under a key
/// that may legitimately be null on a partially-populated resource.
Map<String, dynamic> jsonObject(dynamic raw) =>
    raw is Map<String, dynamic> ? raw : <String, dynamic>{};

/// Returns [raw] as a JSON list, or an empty list if it is missing.
List<dynamic> jsonList(dynamic raw) =>
    raw is List<dynamic> ? raw : <dynamic>[];

/// Encodes a wire list attribute into the JSON text a TEXT column stores.
///
/// Returns null when the key is absent so the column stays null rather than
/// becoming the string `"[]"` — a difference a round-trip test would catch.
String? jsonListToColumn(dynamic raw) =>
    raw is List<dynamic> ? jsonEncode(raw) : null;

/// Decodes a stored JSON array column back to a [List].
///
/// A column that is null, empty or malformed decodes to an empty list instead
/// of throwing, because a display screen must not crash over one corrupt row.
List<dynamic> jsonListFromColumn(String? raw) {
  if (raw == null || raw.isEmpty) return <dynamic>[];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List<dynamic> ? decoded : <dynamic>[];
  } on FormatException {
    return <dynamic>[];
  }
}

/// Parses the timestamp format Firefly sends (`2026-10-13T09:00:00Z`).
///
/// Returns null for null or unparseable input so one malformed timestamp
/// cannot fail an entire pull. Normalised to UTC to uphold the app-wide
/// invariant documented on `millisToDateTime`.
DateTime? isoJsonToDateTime(dynamic raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// Serialises a [DateTime] to the timestamp format Firefly accepts.
String? dateTimeToJson(DateTime? value) => value?.toUtc().toIso8601String();
