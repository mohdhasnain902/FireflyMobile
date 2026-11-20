import 'dart:math' as math;

/// "Nice" axis scale (1/2/5 x 10^k steps) that always contains zero.
class NiceScale {
  const NiceScale._(this.min, this.max, this.step, this.ticks);

  final double min;
  final double max;
  final double step;
  final List<double> ticks;

  /// Derives the axis from the data. Zero is always included so the
  /// profit/loss baseline is always visible.
  factory NiceScale.fromValues(Iterable<double> values, {int targetTicks = 5}) {
    var lo = 0.0;
    var hi = 0.0;
    for (final v in values) {
      if (!v.isFinite) continue;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (hi == lo) {
      lo = -1;
      hi = 1;
    }

    // Head-room only on the sides that actually contain data.
    final pad = (hi - lo) * 0.08;
    if (hi > 0) hi += pad;
    if (lo < 0) lo -= pad;

    final step = _niceNum((hi - lo) / (targetTicks - 1), round: true);
    final kMin = (lo / step + 1e-9).floor();
    final kMax = (hi / step - 1e-9).ceil();
    final ticks = <double>[for (var k = kMin; k <= kMax; k++) k * step];
    return NiceScale._(kMin * step, kMax * step, step, ticks);
  }

  static double _niceNum(double x, {required bool round}) {
    var exp = (math.log(x) / math.ln10).floor();
    // Guard against log10 rounding error at exact powers of ten.
    if (math.pow(10, exp + 1) <= x) exp++;
    final pow10 = math.pow(10, exp).toDouble();
    final f = x / pow10;
    final double nf;
    if (round) {
      nf = f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10));
    } else {
      nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
    }
    return nf * pow10;
  }
}

class PnlFormat {
  const PnlFormat._();

  /// Compact axis label (1.5K, 2M ...). Decimals follow the tick step so all
  /// labels on one axis are distinguishable.
  static String axis(double v, double step) {
    if (v.abs() < step * 1e-9) return '0';
    final a = v.abs();
    var div = 1.0;
    var suffix = '';
    if (a >= 1e9) {
      div = 1e9;
      suffix = 'B';
    } else if (a >= 1e6) {
      div = 1e6;
      suffix = 'M';
    } else if (a >= 1e3) {
      div = 1e3;
      suffix = 'K';
    }
    final s = step / div;
    final decimals =
        math.min(8, math.max(0, -((math.log(s) / math.ln10) + 1e-9).floor()));
    return '${(v / div).toStringAsFixed(decimals)}$suffix';
  }

  /// 1,234.56 / +1,234.56 / -1,234.56 (never "-0.00").
  static String amount(double v, {bool signed = false, int decimals = 2}) {
    final fixed = v.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0]
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final body = parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
    final isZero = double.parse(fixed) == 0;
    final sign = isZero ? '' : (v < 0 ? '-' : (signed ? '+' : ''));
    return '$sign$body';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// full: yyyy-MM-dd. Otherwise MM-dd, or yy-MM when [longSpan].
  static String date(DateTime d, {bool full = false, bool longSpan = false}) {
    if (full) return '${d.year}-${_two(d.month)}-${_two(d.day)}';
    if (longSpan) return '${_two(d.year % 100)}-${_two(d.month)}';
    return '${_two(d.month)}-${_two(d.day)}';
  }
}
