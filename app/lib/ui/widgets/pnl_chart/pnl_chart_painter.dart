import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pnl_models.dart';
import 'pnl_scale.dart';
import 'pnl_theme.dart';

enum PnlChartMode { cumulative, daily }

/// Single source of truth for layout; shared by painter and gesture handling.
class ChartGeometry {
  const ChartGeometry({
    required this.size,
    required this.count,
    required this.mode,
  });

  final Size size;
  final int count;
  final PnlChartMode mode;

  static const double axisWidth = 52; // left-hand Y labels
  static const double axisHeight = 26; // bottom X labels
  static const double topPadding = 12;
  static const double innerInset = 8;

  Rect get plot => Rect.fromLTRB(
        axisWidth,
        topPadding,
        size.width,
        math.max(topPadding, size.height - axisHeight),
      );

  Rect get inner {
    final p = plot;
    final r = p.right - innerInset;
    return Rect.fromLTRB(p.left + innerInset, p.top, math.max(p.left + innerInset, r), p.bottom);
  }

  double xAt(int i) {
    final r = inner;
    if (mode == PnlChartMode.daily) {
      return r.left + (i + 0.5) * r.width / math.max(1, count);
    }
    if (count <= 1) return r.center.dx;
    return r.left + i * r.width / (count - 1);
  }

  /// Nearest sample index for a horizontal position, or -1 when empty.
  int indexAt(double dx) {
    if (count <= 0) return -1;
    final r = inner;
    if (r.width <= 0 || count == 1) return 0;
    final int raw;
    if (mode == PnlChartMode.daily) {
      raw = ((dx - r.left) / (r.width / count)).floor();
    } else {
      raw = ((dx - r.left) / r.width * (count - 1)).round();
    }
    return raw.clamp(0, count - 1).toInt();
  }

  double yAt(double v, NiceScale s) =>
      plot.bottom - (v - s.min) / (s.max - s.min) * plot.height;
}

class PnlChartPainter extends CustomPainter {
  PnlChartPainter({
    required this.samples,
    required this.mode,
    required this.theme,
    required this.selectedIndex,
  });

  final List<PnlSample> samples;
  final PnlChartMode mode;
  final PnlChartTheme theme;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final g = ChartGeometry(size: size, count: samples.length, mode: mode);
    final scale = NiceScale.fromValues(
      samples.map((s) => mode == PnlChartMode.cumulative ? s.cumulative : s.daily),
    );

    _paintGrid(canvas, g, scale);
    if (mode == PnlChartMode.cumulative) {
      _paintLine(canvas, size, g, scale);
    } else {
      _paintBars(canvas, g, scale);
    }
    _paintYAxis(canvas, g, scale);
    _paintXAxis(canvas, g);

    final sel = selectedIndex;
    if (sel != null && sel >= 0 && sel < samples.length) {
      _paintSelection(canvas, g, scale, sel);
    }
  }

  // ---------------------------------------------------------------- grid
  void _paintGrid(Canvas canvas, ChartGeometry g, NiceScale scale) {
    final gridPaint = Paint()
      ..color = theme.grid
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = theme.zeroLine
      ..strokeWidth = 1;

    for (final t in scale.ticks) {
      final y = g.yAt(t, scale);
      final a = Offset(g.plot.left, y);
      final b = Offset(g.plot.right, y);
      if (t == 0) {
        canvas.drawLine(a, b, zeroPaint);
      } else {
        _dashedLine(canvas, a, b, gridPaint);
      }
    }
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p,
      {double dash = 3, double gap = 3}) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      c.drawLine(a + dir * d, a + dir * end, p);
      d += dash + gap;
    }
  }

  // ------------------------------------------------------- cumulative line
  void _paintLine(Canvas canvas, Size size, ChartGeometry g, NiceScale scale) {
    final n = samples.length;
    final zeroY = g.yAt(0, scale);
    final pts = <Offset>[
      for (var i = 0; i < n; i++) Offset(g.xAt(i), g.yAt(samples[i].cumulative, scale)),
    ];

    if (n == 1) {
      canvas.drawCircle(pts.first, 3, Paint()..color = _signColor(samples.first.cumulative));
      return;
    }

    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < n; i++) {
      linePath.lineTo(pts[i].dx, pts[i].dy);
    }
    final areaPath = Path.from(linePath)
      ..lineTo(pts.last.dx, zeroY)
      ..lineTo(pts.first.dx, zeroY)
      ..close();

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Same geometry drawn twice, clipped at the zero line: exact colour
    // split at every zero crossing.
    void half(Rect clip, Color color, double gradientFarY) {
      canvas.save();
      canvas.clipRect(clip);
      final fill = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, gradientFarY),
          Offset(0, zeroY),
          [color.withAlpha(72), color.withAlpha(0)],
        );
      canvas.drawPath(areaPath, fill);
      canvas.drawPath(linePath, strokePaint..color = color);
      canvas.restore();
    }

    half(Rect.fromLTRB(0, 0, size.width, zeroY), theme.profit, g.plot.top);
    half(Rect.fromLTRB(0, zeroY, size.width, size.height), theme.loss, g.plot.bottom);
  }

  // ----------------------------------------------------------- daily bars
  void _paintBars(Canvas canvas, ChartGeometry g, NiceScale scale) {
    final n = samples.length;
    final zeroY = g.yAt(0, scale);
    final slot = g.inner.width / n;
    final barW = math.max(1.0, math.min(slot * 0.6, 18.0));

    for (var i = 0; i < n; i++) {
      final v = samples[i].daily;
      if (v == 0) continue;
      final x = g.xAt(i);
      final y = g.yAt(v, scale);
      var top = math.min(y, zeroY);
      var bottom = math.max(y, zeroY);
      if (bottom - top < 1) {
        // Keep tiny values visible.
        top = v > 0 ? zeroY - 1 : zeroY;
        bottom = v > 0 ? zeroY : zeroY + 1;
      }
      canvas.drawRect(
        Rect.fromLTRB(x - barW / 2, top, x + barW / 2, bottom),
        Paint()..color = _signColor(v),
      );
    }
  }

  // ----------------------------------------------------------------- axes
  void _paintYAxis(Canvas canvas, ChartGeometry g, NiceScale scale) {
    final style = TextStyle(color: theme.axisText, fontSize: 10.5);
    for (final t in scale.ticks) {
      final tp = _tp(PnlFormat.axis(t, scale.step), style);
      final y = g.yAt(t, scale) - tp.height / 2;
      // Right-align labels in the left axis gutter.
      final x = g.plot.left - 6 - tp.width;
      tp.paint(canvas, Offset(math.max(0, x), y));
    }
  }

  void _paintXAxis(Canvas canvas, ChartGeometry g) {
    final n = samples.length;
    final style = TextStyle(color: theme.axisText, fontSize: 10.5);
    final longSpan = samples.last.date.difference(samples.first.date).inDays > 365;

    final maxLabels = math.max(2, (g.plot.width / 72).floor());
    final labelCount = math.min(n, maxLabels);
    final indices = <int>{};
    if (labelCount <= 1) {
      indices.add(0);
    } else {
      for (var k = 0; k < labelCount; k++) {
        indices.add((k * (n - 1) / (labelCount - 1)).round());
      }
    }

    for (final i in indices) {
      final tp = _tp(PnlFormat.date(samples[i].date, longSpan: longSpan), style);
      final x = math.max(g.plot.left, math.min(g.xAt(i) - tp.width / 2, g.plot.right - tp.width));
      tp.paint(canvas, Offset(x, g.plot.bottom + 7));
    }
  }

  // ------------------------------------------------------------ selection
  void _paintSelection(Canvas canvas, ChartGeometry g, NiceScale scale, int i) {
    final x = g.xAt(i);
    final s = samples[i];

    if (mode == PnlChartMode.cumulative) {
      _dashedLine(
        canvas,
        Offset(x, g.plot.top),
        Offset(x, g.plot.bottom),
        Paint()
          ..color = theme.crosshair
          ..strokeWidth = 1,
      );
      final c = Offset(x, g.yAt(s.cumulative, scale));
      canvas.drawCircle(c, 5.5, Paint()..color = theme.background == const Color(0x00000000)
          ? theme.tooltipBackground
          : theme.background);
      canvas.drawCircle(c, 3.5, Paint()..color = _signColor(s.cumulative));
    } else {
      final slot = g.inner.width / samples.length;
      canvas.drawRect(
        Rect.fromLTWH(x - slot / 2, g.plot.top, slot, g.plot.height),
        Paint()..color = theme.crosshair.withAlpha(36),
      );
    }
    _paintTooltip(canvas, g, s, x);
  }

  void _paintTooltip(Canvas canvas, ChartGeometry g, PnlSample s, double x) {
    final rows = mode == PnlChartMode.cumulative
        ? [('Cumulative', s.cumulative), ('Daily', s.daily)]
        : [('Daily', s.daily), ('Cumulative', s.cumulative)];

    final small = TextStyle(color: theme.axisText, fontSize: 11);
    final title = _tp(PnlFormat.date(s.date, full: true), small);
    final labels = <TextPainter>[];
    final values = <TextPainter>[];
    for (final r in rows) {
      labels.add(_tp(r.$1, small));
      values.add(_tp(
        PnlFormat.amount(r.$2, signed: true),
        TextStyle(color: _signColor(r.$2), fontSize: 12, fontWeight: FontWeight.w600),
      ));
    }

    const padX = 10.0, padY = 8.0, colGap = 16.0, rowGap = 5.0;
    var contentW = title.width;
    var contentH = title.height;
    for (var k = 0; k < rows.length; k++) {
      contentW = math.max(contentW, labels[k].width + colGap + values[k].width);
      contentH += rowGap + math.max(labels[k].height, values[k].height);
    }
    final w = contentW + padX * 2;
    final h = contentH + padY * 2;

    var left = x + 12;
    if (left + w > g.plot.right) left = x - 12 - w;
    left = math.max(g.plot.left, left);
    final top = g.plot.top + 4;

    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(6));
    canvas.drawRRect(box, Paint()..color = theme.tooltipBackground);
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.tooltipBorder,
    );

    var dy = top + padY;
    title.paint(canvas, Offset(left + padX, dy));
    dy += title.height;
    for (var k = 0; k < rows.length; k++) {
      dy += rowGap;
      labels[k].paint(canvas, Offset(left + padX, dy));
      values[k].paint(canvas, Offset(left + w - padX - values[k].width, dy));
      dy += math.max(labels[k].height, values[k].height);
    }
  }

  // -------------------------------------------------------------- helpers
  Color _signColor(double v) =>
      v > 0 ? theme.profit : (v < 0 ? theme.loss : theme.primaryText);

  TextPainter _tp(String text, TextStyle style) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  bool shouldRepaint(PnlChartPainter old) =>
      !identical(old.samples, samples) ||
      old.mode != mode ||
      old.theme != theme ||
      old.selectedIndex != selectedIndex;
}
