import 'package:flutter/material.dart';

/// Palette sampled pixel-by-pixel from the four UI/UX design PNGs in
/// `docs/` (2026-10-19): dark olive finance-app look. Every hex below was
/// measured with PIL on those images — do not "improve" values by eye.
class FireflyPalette {
  new _();

  /// App scaffold background (dominant color of all four shots, ~#10160A).
  static const Color background = Color(0xFF10160A);

  /// Card / drawer / sheet surface (dominant card pixel, ~#1D2513).
  static const Color surface = Color(0xFF1D2513);

  /// Elevated chips / pressed states (~#262F1C).
  static const Color surfaceElevated = Color(0xFF262F1C);

  /// Dim olive fill used by active segments and progress tracks (~#43582B).
  static const Color oliveFill = Color(0xFF43582B);

  /// Primary lime accent — active chips, "+amount", links, progress
  /// (exact mode of saturated pixels in the transactions shot, #A5D075).
  static const Color primary = Color(0xFFA5D075);

  /// Brighter lime for large filled controls (FAB / Save pill, ~#B0E080).
  static const Color primaryBright = Color(0xFFB0E080);

  /// Negative amounts / errors / over-budget (transactions shot, #F17C5C).
  static const Color negative = Color(0xFFF17C5C);

  /// Chart-only greens/ambers measured in the Reports shot; positive
  /// amounts in lists reuse [primary] (that is what the design uses).
  static const Color chartGreen = Color(0xFF7BA055);
  /// Donut/legend amber slice in the Reports shot.
  static const Color chartAmber = Color(0xFFCCBB62);

  /// Primary text: pure white in every shot.
  static const Color textPrimary = Color(0xFFFFFFFF);
  /// Secondary text (subtitles, labels, timestamps).
  static const Color textMuted = Color(0xFF959892);
  /// Dimmest text (hints, disabled).
  static const Color textDim = Color(0xFF777C75);

  /// Hairline outlines / field borders (midpoint between elevated and fill).
  static const Color outline = Color(0xFF394426);

  /// Text/icons on lime fills (dark-on-light for AA contrast).
  static const Color onPrimary = Color(0xFF10160A);
}

/// Single source of truth for the app's [ThemeData].
///
/// The design set is dark-only, so [dark] is wired into BOTH `theme:` and
/// `darkTheme:` in `FireflyApp` — system light mode still renders the
/// designed look instead of an undesigned white fallback.
class FireflyTheme {
  new _();

  /// Builds the designed dark theme.
  ///
  /// Built fresh per call: ThemeData is immutable but tests rebuild the app
  /// and a shared const instance would be flagged by no-leading-const lint
  /// patterns in tests; cheap either way.
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      // Lime accent family.
      primary: FireflyPalette.primary,
      onPrimary: FireflyPalette.onPrimary,
      primaryContainer: FireflyPalette.oliveFill,
      onPrimaryContainer: FireflyPalette.primary,
      secondary: FireflyPalette.primaryBright,
      onSecondary: FireflyPalette.onPrimary,
      secondaryContainer: FireflyPalette.surfaceElevated,
      onSecondaryContainer: FireflyPalette.textPrimary,
      tertiary: FireflyPalette.chartAmber,
      onTertiary: FireflyPalette.onPrimary,
      tertiaryContainer: FireflyPalette.oliveFill,
      onTertiaryContainer: FireflyPalette.chartAmber,
      // Coral is the design's error/negative colour.
      error: FireflyPalette.negative,
      onError: FireflyPalette.onPrimary,
      // Surfaces (no deprecated `background`/`surfaceVariant` args — they
      // would add analyzer infos above the 62 baseline).
      surface: FireflyPalette.background,
      onSurfaceVariant: FireflyPalette.textMuted,
      outline: FireflyPalette.outline,
      outlineVariant: FireflyPalette.surfaceElevated,
    );

    // Shared pill radius — every control in the design is fully rounded.
    const pill = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: FireflyPalette.background,

      // Screen titles: bold white, left-aligned (design "Dashboard" style).
      appBarTheme: const AppBarTheme(
        backgroundColor: FireflyPalette.background,
        foregroundColor: FireflyPalette.textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: FireflyPalette.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),

      // Cards (entity rows, report tiles): flat, 16dp radius, no shadow.
      cardTheme: CardThemeData(
        color: FireflyPalette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: FireflyPalette.surface,
        elevation: 0,
      ),

      // List rows: white labels, muted leading icons (design lists).
      listTileTheme: const ListTileThemeData(
        iconColor: FireflyPalette.textMuted,
        textColor: FireflyPalette.textPrimary,
      ),

      // Chips: outlined when idle, solid lime with dark label when selected
      // (design filter pills — "All" = filled lime, rest = outline).
      chipTheme: const ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: FireflyPalette.outline),
        selectedColor: FireflyPalette.primary,
        showCheckmark: false,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        labelStyle: TextStyle(
          color: FireflyPalette.textMuted,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(
          color: FireflyPalette.onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: StadiumBorder(),
      ),

      // Primary pill buttons ("Save"): lime fill, dark bold label.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FireflyPalette.primaryBright,
          foregroundColor: FireflyPalette.onPrimary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: pill,
        ),
      ),

      // Secondary pill buttons (design "Export CSV"/"Share" outlines).
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FireflyPalette.textPrimary,
          side: const BorderSide(color: FireflyPalette.outline),
          textStyle: const TextStyle(fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: pill,
        ),
      ),

      // "New transaction"-style extended FAB: brighter lime pill.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: FireflyPalette.primaryBright,
        foregroundColor: FireflyPalette.onPrimary,
        elevation: 0,
        shape: StadiumBorder(),
      ),

      // Search fields: dark pill fill, hint dim, lime focus ring.
      inputDecorationTheme: const InputDecorationThemeData(
        filled: true,
        fillColor: FireflyPalette.surface,
        hintStyle: TextStyle(color: FireflyPalette.textDim),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          borderSide: BorderSide(
            color: FireflyPalette.primary,
            width: 1.5,
          ),
        ),
      ),

      // Budget-style progress: lime fill on dim olive track.
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: FireflyPalette.primary,
        linearTrackColor: FireflyPalette.oliveFill,
        circularTrackColor: FireflyPalette.oliveFill,
      ),

      dividerTheme: const DividerThemeData(
        color: FireflyPalette.surfaceElevated,
        thickness: 1,
        space: 1,
      ),

      // Transient messages: surface card, lime action (design snackbar look).
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: FireflyPalette.surface,
        contentTextStyle: TextStyle(color: FireflyPalette.textPrimary),
        actionTextColor: FireflyPalette.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: FireflyPalette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          color: FireflyPalette.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(color: FireflyPalette.textMuted),
      ),

      // Selection/cursor follow the lime accent.
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: FireflyPalette.primary,
        selectionColor: Color(0x66A5D075),
        selectionHandleColor: FireflyPalette.primary,
      ),

      // Bottom nav (Phase 1 redesign): lime rounded-rect indicator behind
      // the active icon, muted inactive labels — matches the mockup nav bar.
      // Not const: WidgetStateProperty.resolveWith is a method call.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: FireflyPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: FireflyPalette.primary,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? FireflyPalette.onPrimary
                : FireflyPalette.textMuted,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? FireflyPalette.textPrimary
                : FireflyPalette.textMuted,
          ),
        ),
      ),

      // Binary controls (settings toggles): lime when on.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FireflyPalette.onPrimary
              : FireflyPalette.textDim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FireflyPalette.primary
              : FireflyPalette.surfaceElevated,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FireflyPalette.primary
              : FireflyPalette.surfaceElevated,
        ),
        checkColor: WidgetStateProperty.all(FireflyPalette.onPrimary),
      ),
    );
  }
}
