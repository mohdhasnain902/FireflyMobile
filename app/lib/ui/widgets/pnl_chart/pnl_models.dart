/// Domain models + series construction. No Flutter dependencies.

/// One day's realized PnL, as supplied by the data layer.
class DailyPnl {
  const DailyPnl(this.date, this.pnl);
  final DateTime date;
  final double pnl;
}

/// One plotted point: a calendar day with its daily and cumulative PnL.
class PnlSample {
  const PnlSample(this.date, this.daily, this.cumulative);
  final DateTime date;
  final double daily;
  final double cumulative;
}

enum PnlRange {
  d7('7D', 7),
  d30('30D', 30),
  d90('90D', 90),
  all('All', null);

  const PnlRange(this.label, this.days);
  final String label;
  final int? days;
}

class PnlSeries {
  const PnlSeries._();

  /// Builds a gap-filled daily series for [range].
  ///
  /// - Dates are normalised to calendar days; same-day entries are summed.
  /// - Days without an entry are filled with 0 (flat cumulative line).
  /// - The window ends at [endDate] (pass `DateTime.now()` to anchor to today)
  ///   or, when null, at the last day present in [data].
  /// - Cumulative PnL restarts at 0 at the beginning of the window.
  static List<PnlSample> build(
    List<DailyPnl> data,
    PnlRange range, {
    DateTime? endDate,
  }) {
    if (data.isEmpty) return const [];

    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

    final byDay = <DateTime, double>{};
    for (final e in data) {
      if (!e.pnl.isFinite) continue;
      final d = day(e.date);
      byDay[d] = (byDay[d] ?? 0) + e.pnl;
    }
    if (byDay.isEmpty) return const [];

    final days = byDay.keys.toList()..sort();
    final end = endDate != null ? day(endDate) : days.last;
    final start = range.days == null
        ? days.first
        : DateTime(end.year, end.month, end.day - (range.days! - 1));
    if (start.isAfter(end)) return const [];

    final out = <PnlSample>[];
    var cumulative = 0.0;
    for (var d = start;
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      final v = byDay[d] ?? 0.0;
      cumulative += v;
      out.add(PnlSample(d, v, cumulative));
    }
    return out;
  }
}
