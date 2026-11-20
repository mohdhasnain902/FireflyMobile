import 'package:flutter/painting.dart';

import 'package:firefly_mobile/ui/theme/app_theme.dart';

/// Chart colors tuned to the app's Firefly palette.
class PnlChartTheme {
  const PnlChartTheme({
    required this.background,
    required this.profit,
    required this.loss,
    required this.grid,
    required this.zeroLine,
    required this.axisText,
    required this.primaryText,
    required this.accent,
    required this.chipSelected,
    required this.tooltipBackground,
    required this.tooltipBorder,
    required this.crosshair,
  });

  final Color background;
  final Color profit;
  final Color loss;
  final Color grid;
  final Color zeroLine;
  final Color axisText;
  final Color primaryText;
  final Color accent;
  final Color chipSelected;
  final Color tooltipBackground;
  final Color tooltipBorder;
  final Color crosshair;

  static const dark = PnlChartTheme(
    background: Color(0x00000000), // transparent to blend into cards
    profit: FireflyPalette.primary,
    loss: FireflyPalette.negative,
    grid: FireflyPalette.outline,
    zeroLine: FireflyPalette.textDim,
    axisText: FireflyPalette.textDim,
    primaryText: FireflyPalette.textPrimary,
    accent: FireflyPalette.primary,
    chipSelected: FireflyPalette.surfaceElevated,
    tooltipBackground: FireflyPalette.surfaceElevated,
    tooltipBorder: FireflyPalette.outline,
    crosshair: FireflyPalette.textMuted,
  );

  static const light = PnlChartTheme(
    background: Color(0xFFFFFFFF),
    profit: FireflyPalette.chartGreen,
    loss: FireflyPalette.negative,
    grid: Color(0xFFEDEEF0),
    zeroLine: Color(0xFFC4C8CF),
    axisText: Color(0xFF8E96A3),
    primaryText: FireflyPalette.background,
    accent: FireflyPalette.primary,
    chipSelected: Color(0xFFF1F2F4),
    tooltipBackground: Color(0xFFFFFFFF),
    tooltipBorder: Color(0xFFDADDE2),
    crosshair: Color(0xFF8E96A3),
  );
}
