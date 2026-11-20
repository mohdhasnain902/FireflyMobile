import 'package:firefly_mobile/data/repositories/sync_repository.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/ui/models/field_spec.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything the two generic screens need to serve one entity type.
///
/// The design deliberately avoids `dynamic`: the generic list screen watches
/// a typed `FutureProvider<List<T>>`, and the generic form works on a plain
/// `Map<String, Object?>` whose keys are [FieldSpec.key]s, converting to and
/// from the concrete entity through the typed [toValues]/[createWith]/
/// [editWith] closures each config provides. All dynamic dispatch is thereby
/// confined to closures whose signatures are checked at compile time.
class EntityConfig<T extends SyncBookkeeping> {
  /// Declares one entity's screens, fields and write path.
  const new({
    required this.title,
    required this.singular,
    required this.icon,
    required this.listProvider,
    required this.fields,
    required this.rowTitle,
    required this.rowSubtitle,
    required this.toValues,
    required this.createWith,
    required this.editWith,
    this.repoOf,
    this.canWrite = true,
    this.searchHint,
    this.filters,
    this.groupLabel,
    this.groupCompare,
    this.rowLeading,
    this.rowSubtitleWidget,
    this.rowTrailingWidget,
    this.cardRows = false,
    this.fabLabel,
  });

  /// Plural drawer/list title, e.g. `Accounts`.
  final String title;

  /// Singular form used in dialog copy, e.g. `account`.
  final String singular;

  /// Drawer icon for the entity.
  final IconData icon;

  /// Newest-50 page the list screen renders; defined in `core/providers.dart`.
  final FutureProvider<List<T>> listProvider;

  /// Form fields, rendered in order by the generic form screen.
  final List<FieldSpec> fields;

  /// Leading text for a list row (its "name").
  final String Function(T row) rowTitle;

  /// Secondary line for a list row.
  final String Function(T row) rowSubtitle;

  /// Projects an entity into the form's values map via its [FieldSpec.key]s.
  final Map<String, Object?> Function(T row) toValues;

  /// Builds a brand-new entity from validated values, stamping the
  /// bookkeeping the repository reserved ([SyncRepository.create] contract).
  final T Function(
    Map<String, Object?> values, {
    required String id,
    required DateTime updatedAt,
    required int seq,
  })
  createWith;

  /// Applies validated values onto an existing entity, keeping its id and
  /// stamping fresh bookkeeping ([SyncRepository.update] contract).
  final T Function(
    T current,
    Map<String, Object?> values, {
    required DateTime updatedAt,
    required int seq,
  })
  editWith;

  /// Repository loader for write screens. Null means read-only (currencies:
  /// Firefly's currency API has no write endpoints for clients).
  ///
  /// Takes a [WidgetRef] because only widget code (list/form screens) calls
  /// it — in Riverpod 3 a widget's `ref` is a `WidgetRef`, not the provider-
  /// side `Ref`. The config closures just `ref.watch(...)` either way.
  final Future<SyncRepository<T>> Function(WidgetRef ref)? repoOf;

  /// Whether create/edit/delete affordances are shown at all.
  final bool canWrite;

  // --- Optional list-screen hooks (docs/2nd UI 2.png, transactions design).
  // Every hook defaults to null/false, so a config that omits them renders
  // exactly the old generic list (13 non-transaction entities unchanged).

  /// Placeholder text of the search field; null = `Search`.
  final String? searchHint;

  /// Quick-filter pills shown above the results (index 0 is always `All`).
  final List<ListFilter<T>>? filters;

  /// Day/section header for a row (null = flat list, old order).
  final String Function(T row)? groupLabel;

  /// Sort key for grouping: descending (newest first). Dart's sort is
  /// unstable, so the list screen sorts index copies to keep same-group
  /// rows in provider order.
  final int Function(T a, T b)? groupCompare;

  /// Leading widget (circle icon); null = plain ListTile leading.
  final Widget Function(BuildContext context, WidgetRef ref, T row)?
  rowLeading;

  /// Replaces the plain-text subtitle (e.g. to add a tag chip under it).
  final Widget Function(BuildContext context, WidgetRef ref, T row)?
  rowSubtitleWidget;

  /// Extra widget before the SyncBadge in the trailing slot (amount/time
  /// column). null = old trailing (badge + menu only).
  final Widget Function(BuildContext context, WidgetRef ref, T row)?
  rowTrailingWidget;

  /// Wrap each row in the theme's Card (16px inset, radius 16).
  final bool cardRows;

  /// Extended-FAB caption; null = plain FAB (old behavior).
  final String? fabLabel;

  /// Creates this entity's generic list screen with [T] bound to the
  /// runtime entity type.
  ///
  /// Callers holding an erased `EntityConfig<SyncBookkeeping>` (e.g. the
  /// More tab iterating allEntityConfigs) must use this instead of
  /// `EntityListScreen<SyncBookkeeping>(config: ...)`: binding T to the
  /// supertype makes `_buildRow` read `rowTitle` with static type
  /// `(SyncBookkeeping) => String`, which the runtime closure
  /// `(Transaction) => String` fails — TypeError (regression R20).
  /// Virtual dispatch through this method re-binds T per config.
  Widget buildListScreen({Key? key, bool embedded = false}) =>
      EntityListScreen<T>(key: key, config: this, embedded: embedded);
}

/// One quick-filter pill: [label] on the chip, [test] decides row match.
class ListFilter<T> {
  /// Creates a pill with its chip [label] and row-matching [test].
  const new({required this.label, required this.test});

  /// Text shown on the chip.
  final String label;

  /// Decides whether a row belongs to this filter.
  final bool Function(T row) test;
}
