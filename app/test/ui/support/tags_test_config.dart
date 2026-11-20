import 'package:firefly_mobile/core/providers.dart' show tagRepositoryProvider;
import 'package:firefly_mobile/data/repositories/sync_repository.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/models/field_spec.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Re-exported so test files need one import for the repo provider override.
export 'package:firefly_mobile/core/providers.dart' show tagRepositoryProvider;

/// The single-field layout every default tags test uses: the required name.
List<FieldSpec> defaultTagFields() => const [
  FieldSpec(key: 'tag', label: 'Tag', kind: FieldKind.text, required: true),
];

/// A tags [EntityConfig] whose write affordances the test controls directly.
///
/// The production `tagsConfig` is exercised untouched by the happy-path
/// tests; this builder exists for the branches production cannot reach in a
/// test run — `canWrite: false` (read-only gating) and extra fields used only
/// to pin the generic form's validation rules (decimal/choice/json).
///
/// [repoOf] is injected rather than watched from providers so the config can
/// bind to the suite's in-memory SQLite handle without any provider override.
EntityConfig<Tag> tagsConfigForTest({
  required bool canWrite,
  Future<SyncRepository<Tag>> Function(WidgetRef ref)? repoOf,
  List<FieldSpec>? fields,
}) {
  return EntityConfig<Tag>(
    title: 'Tags',
    singular: 'tag',
    icon: Icons.label_outline,
    listProvider: _testTagListProvider,
    repoOf: repoOf,
    canWrite: canWrite,
    fields: fields ?? defaultTagFields(),
    rowTitle: (row) => row.tag,
    rowSubtitle: (row) => '—',
    toValues: (row) => <String, Object?>{'tag': row.tag},
    createWith: (values, {required id, required updatedAt, required seq}) =>
        Tag(
          id: id,
          tag: (values['tag'] as String?) ?? '',
          updatedAt: updatedAt,
          seq: seq,
        ),
    editWith: (current, values, {required updatedAt, required seq}) =>
        current.copyWith(
          tag: (values['tag'] as String?) ?? current.tag,
          updatedAt: updatedAt,
          seq: seq,
        ),
  );
}

/// Dedicated list provider so custom configs never share (and never
/// invalidate) the production `tagListProvider` cache.
///
/// Reads through the same `tagRepositoryProvider` the production list uses,
/// so a suite that overrides that provider feeds both.
final _testTagListProvider = FutureProvider<List<Tag>>(
  (ref) => ref
      .watch(tagRepositoryProvider.future)
      .then((repo) => repo.getAll()),
);
