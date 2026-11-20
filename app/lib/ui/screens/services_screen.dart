/// Services screen: editable "My Favorites" plus all other service pages.
library;

import 'package:firefly_mobile/ui/services/favorites_provider.dart';
import 'package:firefly_mobile/ui/services/service_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Services screen with editable favorites.
class ServicesScreen extends ConsumerStatefulWidget {
  /// Creates the services screen.
  const new({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final favoritesAsync = ref.watch(favoritesProvider);
    final favorites = favoritesAsync.value ?? kDefaultFavoriteIds;
    final favoritePages = favorites
        .map(servicePageById)
        .whereType<ServicePage>()
        .toList();
    final otherPages = allServicePages
        .where((p) => !favorites.contains(p.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Services'),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() => _editing = !_editing),
            child: Text(_editing ? 'Done' : 'Edit'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('My Favorites'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final ServicePage page in favoritePages)
                _ServiceTile(
                  page: page,
                  editing: _editing,
                  onRemove: () =>
                      ref.read(favoritesProvider.notifier).remove(page.id),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('All Services'),
          const SizedBox(height: 8),
          for (final ServicePage page in otherPages)
            ListTile(
              leading: Icon(page.icon),
              title: Text(page.title),
              trailing: _editing
                  ? IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: favorites.length >= kMaxFavorites
                          ? null
                          : () =>
                              ref.read(favoritesProvider.notifier).add(page.id),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _editing
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: page.builder,
                        ),
                      ),
            ),
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const new({
    required this.page,
    required this.editing,
    required this.onRemove,
  });

  final ServicePage page;
  final bool editing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        children: <Widget>[
          Stack(
            children: <Widget>[
              IconButton(
                icon: Icon(page.icon),
                onPressed: editing
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: page.builder,
                          ),
                        ),
              ),
              if (editing)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: const Icon(Icons.remove_circle, color: Colors.red),
                  ),
                ),
            ],
          ),
          Text(page.title, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
