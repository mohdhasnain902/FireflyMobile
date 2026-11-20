# UI Work Log

This document records UI-related work performed in this repository so project documentation stays current. It is factual and scoped to implemented changes and verification actually performed.

## 2026 (session): Dashboard chart, spending trend, and Reports

### Net worth / “PnL” chart (dashboard hero)
- **Added reusable chart module:** `app/lib/ui/widgets/pnl_chart/`
  - `pnl_models.dart` — `PnlSeries`, `PnlRange`, `DailyPnl` and range/series helpers.
  - `pnl_scale.dart` — “nice” Y-axis scale calculation.
  - `pnl_theme.dart` — chart theme values (adapted to the app’s Firefly palette with transparent background instead of the sample theme).
  - `pnl_chart_painter.dart` — custom painter and `ChartGeometry`; **adapted to render the Y-axis scale and labels on the left** (per requirement) rather than the right.
  - `pnl_chart.dart` — interactive chart widget (Cumulative/Daily modes, range selection, total/tooltip behavior).
- **Integrated into dashboard:** `app/lib/ui/screens/dashboard_screen.dart`
  - Replaced the previous net sparkline/day-axis implementation with `_NetPnlChart` backed by `PnlChart`.
  - Chart data is derived from `DashboardSummary.netSeries` as daily deltas for the selected month (stable `List<DailyPnl>`), shown over the full viewed month (`PnlRange.all`, `endDate` = month end), using the summary’s currency.
  - **Terminology:** user-facing labels changed from “PnL” to personal-finance wording — header “Net change (selected period)” and mode tabs/tooltips “Cumulative” / “Daily”. Internal `Pnl*` type/class names were retained for the chart module.
  - Removed the old `_NetSparkline` / `_DayAxisLabels` widgets.

### Spending trend (dashboard)
- **Restyled** `_SpendingLineChart` in `app/lib/ui/screens/dashboard_screen.dart`:
  - Themed dashed horizontal grid and left-aligned Y-axis labels with readable formatting.
  - 0-baseline aware range/padding, curved line with points, and subtle area fill.
  - Thinned bottom month labels to reduce crowding and added touch tooltips.
  - Restored `dart:math` import required by the chart.

### Reports section (rewritten)
- **Rewrote** `app/lib/ui/screens/reports_screen.dart` as a period-based report inspired by Firefly III’s default report concepts (researched via Firefly III reports documentation; the website itself was not modified): https://docs.firefly-iii.org/how-to/firefly-iii/finances/reports/
- **Features implemented:**
  - Period scope selector: This month, Last month, Last 3/6/12 months, Year to date, All time, and Custom range.
  - Summary cards: Income, Expenses, Net for the selected period.
  - Income vs expenses by month: grouped bar chart with axes, grid, legend, and tooltips.
  - Expenses and income by category: pie chart (with legend/percentages) plus ranked breakdown bars.
  - Budgets: spending in period versus overlapping budget limit(s), with progress/remaining or over-budget indication where applicable.
  - Account balances: current asset and liability account balances with section totals.
  - Bills & subscriptions: active bills with amount and next expected date.
- **Data:** loads from repositories (`getAll(limit: 100000)` for transactions, accounts, budgets, budget limits, bills, categories) and aggregates over the selected period so reporting is not constrained by small list-provider windows. (Balances are current point-in-time; budget limits shown where they overlap the selected period.)

### Verification performed
- Environment: Flutter SDK at `/mnt/data/opencode/tools/flutter/bin/flutter` (Flutter 3.47.7, Dart 3.13.5) on Linux desktop (`DISPLAY=:1`). `flutter pub get` run in `app/`.
- Static analysis (no errors reported; lint/info-level issues only, e.g. style/line-length in some areas): `flutter analyze` on modified dashboard/chart files and `flutter analyze lib/ui/screens/reports_screen.dart`.
- Build/run: app built and launched on Linux desktop in debug mode (`flutter run -d linux`) during the session so UI changes could be viewed. (A running debug process may be stopped/restarted between checks; see current session state.)

### Notes / limitations
- Visual correctness was validated by build/run on desktop; no automated screenshot/visual-regression baseline was added.
- Report figures depend on locally available/synced data and the aggregation rules above; they are not a byte-for-byte replica of the Firefly III web report.
- Changes in this session are local working-tree edits (not committed/pushed here).

## 2026 (session, approved): Navigation and sync affordance
- **Settings in bottom navigation:** added **Settings** as the rightmost bottom-bar destination after Reports in `app/lib/ui/screens/home_screen.dart` (5th tab, `Icons.settings_outlined`), hosted in the shell `IndexedStack`. Settings remains available in other places (e.g. Services/Quick access/favorites via `service_pages.dart`) as before.
- **Settings screen embedding:** added `embedded` support to `app/lib/ui/screens/settings_screen.dart` so it can render without its own `AppBar`/outer `Scaffold` when shown inside the shell, while still working as a standalone pushed screen.
- **Sync status/action consistency:** removed the stub “Sync now” button/snackbar from the app-bar `SyncStatusIndicator` (`app/lib/ui/widgets/sync_status.dart`). The manual sync action remains in **Settings → Sync**; the top-right sync status indicator (state icon, label/tooltip, pending count) remains visible in the shell app bar so sync state/in-progress status is still shown.

## UI audit (point-in-time, for review/approval)
A whole-UI audit was prepared in-session covering navigation, screens, consistency, accessibility, and standards observations, with file-level locations and a prioritized list. User-approved items implemented in this session: add Settings to the bottom bar rightmost after Reports (kept elsewhere) and move the sync action out of the app-bar stub into Settings while keeping the syncing/status icon visible in the top-right. Remaining audit findings were listed for separate approval and are not implemented here unless noted above.


## 2026 (session): Currency conversion and display
- **Exchange rates (open-source, no key):** added `app/lib/core/currency/exchange_rates.dart` using the fawazahmed0/exchange-api (jsDelivr CDN with Cloudflare Pages fallback, daily rates, broad currency coverage incl. PKR). Rates are fetched on demand/refresh and cached in `device_meta` for offline conversion.
- **Display/secondary currency setting:** added “Currency & conversion” in `app/lib/ui/screens/settings_screen.dart` to choose a secondary currency (or Off) and refresh exchange rates. Cached rates/selection stored via `DeviceMetaDao` keys (`display_currency`, `exchange_rates_cache`, `exchange_rates_fetched_at`).
- **Secondary amount display:** when a display currency is set and a cached rate is available, converted amounts are shown below originals (≈ …) in key views: dashboard net worth/income/spent cards (`dashboard_screen.dart`) and Reports summary cards (`reports_screen.dart`).
- **Form amount conversion on currency change:** in `app/lib/ui/screens/entity_form_screen.dart`, changing a currency field (`currencyCode` / `foreignCurrencyCode`) converts paired amount fields (e.g. `amount`, `openingBalance`, `virtualBalance`, or `foreignAmount`) using cached/fetched rates when available, so the numeric amount reflects the selected currency.
- **Reports quality fixes (post-audit):** stabilized report data loading (cached `Future`/reload on refresh), corrected empty-state condition to consider all sections, added bills truncation notice, improved currency-formatted amounts in category/budget/account summaries, and adjusted category legend layout for better fit.

### Notes
- Secondary conversion display depends on available cached rates for the source currency and the selected display currency; rates can be refreshed in Settings. If rates are unavailable, originals are shown unchanged and form auto-conversion is skipped.
- Currency conversion on edit changes the entered amount to the equivalent in the newly selected currency (as requested); it uses fetched rates and may differ slightly due to rounding and daily rate snapshots.
