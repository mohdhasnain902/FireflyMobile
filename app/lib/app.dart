import 'package:firefly_mobile/core/constants.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/sync_lifecycle.dart';
import 'package:firefly_mobile/ui/screens/home_screen.dart';
import 'package:firefly_mobile/ui/screens/onboarding_screen.dart';
import 'package:firefly_mobile/ui/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod does not
// re-export it (same import the widget tests use).
import 'package:flutter_riverpod/misc.dart' show Override;

/// Root widget of the application.
///
/// Owns the theme, navigation shell and the app-wide [ProviderScope] — the
/// scope lives here (not in `main()`) so tests can pump `FireflyApp` directly
/// and every ConsumerWidget still finds a container.
///
/// Shows [OnboardingScreen] until a Firefly base URL is saved; after that the
/// [HomeScreen] navigation shell is shown. The app is fully usable offline
/// either way — onboarding only gates the sync configuration (DESIGN NFR-1).
class FireflyApp extends StatelessWidget {
  /// Creates the root application widget.
  ///
  /// [overrides] lets tests swap seam providers (e.g. `databaseProvider`)
  /// before first build. Without it the Linux/FFI database chain does real
  /// async work (dart:io + isolate) that never settles under the fake-async
  /// `testWidgets` zone — see docs/REGRESSION-LOG.md R19.
  const new({super.key, this.overrides = const []});

  /// Seam-provider overrides injected into the app-wide [ProviderScope].
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: overrides,
      // Watcher wraps MaterialApp (not home) so its lifecycle observer lives
      // for the whole app regardless of navigation, and sits inside the
      // ProviderScope it reads the sync controller from (P3.4.2).
      child: SyncLifecycleWatcher(
        child: MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          // Design set is dark-only (4 PNGs in docs/), so the designed dark
          // theme serves BOTH slots — system light mode still renders the
          // designed look instead of an undesigned white fallback.
          theme: FireflyTheme.dark,
          darkTheme: FireflyTheme.dark,
          home: const _HomeOrOnboarding(),
        ),
      ),
    );
  }
}

/// Shows [OnboardingScreen] until a Firefly base URL is saved, then
/// [HomeScreen].
class _HomeOrOnboarding extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(connectionSettingsProvider);

    return settingsAsync.when(
      data: (settings) {
        if (settings.baseUrl.isEmpty) {
          return const OnboardingScreen();
        }
        return const HomeScreen();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const HomeScreen(), // degrade gracefully
    );
  }
}
