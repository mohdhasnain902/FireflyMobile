/// Favorites state for the Services grid (Bybit-style home quick access).
library;

import 'dart:convert';

import 'package:firefly_mobile/core/providers.dart' show metaProvider;
import 'package:firefly_mobile/ui/services/service_pages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Key under which the user's favorite service ids are persisted.
const String kServicesFavoritesKey = 'services_favorites';

/// AsyncNotifier holding the ordered list of favorite service ids.
class FavoritesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final meta = await ref.watch(metaProvider.future);
    final raw = await meta.get(kServicesFavoritesKey);
    if (raw == null || raw.isEmpty) {
      return List<String>.from(kDefaultFavoriteIds);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final ids = decoded.whereType<String>().toList();
        if (ids.isEmpty) return List<String>.from(kDefaultFavoriteIds);
        return ids;
      }
    } on FormatException {
      // Fall back to defaults on corrupt data.
    }
    return List<String>.from(kDefaultFavoriteIds);
  }

  Future<void> _persist(List<String> ids) async {
    final meta = await ref.read(metaProvider.future);
    await meta.set(kServicesFavoritesKey, jsonEncode(ids));
  }

  /// Adds [id] to favorites if not already present and under the cap.
  Future<void> add(String id) async {
    final current = state.value ?? <String>[];
    if (current.contains(id)) return;
    if (current.length >= kMaxFavorites) return;
    final next = <String>[...current, id];
    state = AsyncData(next);
    await _persist(next);
  }

  /// Removes [id] from favorites.
  Future<void> remove(String id) async {
    final current = state.value ?? <String>[];
    final next = current.where((e) => e != id).toList();
    state = AsyncData(next);
    await _persist(next);
  }

  /// Reorders favorites by moving the item at [oldIndex] to [newIndex].
  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = List<String>.from(state.value ?? <String>[]);
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex < 0 || newIndex > current.length) return;
    final item = current.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    current.insert(insertAt.clamp(0, current.length), item);
    state = AsyncData(current);
    await _persist(current);
  }
}

/// Provider for the favorites list.
final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<String>>(
  FavoritesNotifier.new,
);
