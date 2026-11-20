import 'package:flutter/material.dart';

import 'pnl_chart_painter.dart';
import 'pnl_models.dart';
import 'pnl_scale.dart';
import 'pnl_theme.dart';

export 'pnl_models.dart';
export 'pnl_theme.dart';

/// Net-change chart: Cumulative / Daily tabs, range chips, total, chart.
///
/// Pass a stable [data] list (don't re-create it on every parent build);
/// the series is recomputed only when [data], [endDate] or the range changes.
class PnlChart extends StatefulWidget {
  const PnlChart({
    super.key,
    required this.data,
    this.currency = 'USDT',
    this.endDate,
    this.initialRange = PnlRange.d30,
    this.chartHeight = 240,
    this.theme,
  });

  final List<DailyPnl> data;
  final String currency;

  /// Last day of the window. Null = last day present in [data].
  final DateTime? endDate;
  final PnlRange initialRange;
  final double chartHeight;

  /// Null = follows the ambient Material brightness.
  final PnlChartTheme? theme;

  @override
  State<PnlChart> createState() => _PnlChartState();
}

class _PnlChartState extends State<PnlChart> {
  late PnlRange _range;
  PnlChartMode _mode = PnlChartMode.cumulative;
  List<PnlSample> _samples = const [];
  int? _selected;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _rebuildSeries();
  }

  @override
  void didUpdateWidget(PnlChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data) || old.endDate != widget.endDate) {
      _selected = null;
      _rebuildSeries();
    }
  }

  void _rebuildSeries() {
    _samples = PnlSeries.build(widget.data, _range, endDate: widget.endDate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ??
        (Theme.of(context).brightness == Brightness.dark
            ? PnlChartTheme.dark
            : PnlChartTheme.light);

    final total = _samples.isEmpty ? 0.0 : _samples.last.cumulative;
    final totalColor =
        total > 0 ? theme.profit : (total < 0 ? theme.loss : theme.primaryText);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.background),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap, not Row: the chip strip overflowed by 8 px on a 320 dp
            // phone (R23 sweep), and the range strip by 15 px.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  label: 'Cumulative',
                  selected: _mode == PnlChartMode.cumulative,
                  theme: theme,
                  onTap: () => _setMode(PnlChartMode.cumulative),
                ),
                _Chip(
                  label: 'Daily',
                  selected: _mode == PnlChartMode.daily,
                  theme: theme,
                  onTap: () => _setMode(PnlChartMode.daily),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Net change (${widget.currency})',
              style: TextStyle(color: theme.axisText, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              PnlFormat.amount(total, signed: true),
              style: TextStyle(color: totalColor, fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in PnlRange.values)
                  _Chip(
                    label: r.label,
                    selected: r == _range,
                    theme: theme,
                    onTap: () => _setRange(r),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildChart(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(PnlChartTheme theme) {
    if (_samples.isEmpty) {
      return SizedBox(
        height: widget.chartHeight,
        child: Center(
          child: Text('No data', style: TextStyle(color: theme.axisText)),
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, widget.chartHeight);
      final geo = ChartGeometry(size: size, count: _samples.length, mode: _mode);

      void select(Offset p) {
        final i = geo.indexAt(p.dx);
        if (i >= 0 && i != _selected) setState(() => _selected = i);
      }

      void clear() {
        if (_selected != null) setState(() => _selected = null);
      }

      return MouseRegion(
        onHover: (e) => select(e.localPosition),
        onExit: (_) => clear(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => select(d.localPosition),
          onTapUp: (_) => clear(),
          onTapCancel: clear,
          onHorizontalDragStart: (d) => select(d.localPosition),
          onHorizontalDragUpdate: (d) => select(d.localPosition),
          onHorizontalDragEnd: (_) => clear(),
          onHorizontalDragCancel: clear,
          child: CustomPaint(
            size: size,
            painter: PnlChartPainter(
              samples: _samples,
              mode: _mode,
              theme: theme,
              selectedIndex: _selected,
            ),
          ),
        ),
      );
    });
  }

  void _setMode(PnlChartMode m) => setState(() {
        _mode = m;
        _selected = null;
      });

  void _setRange(PnlRange r) => setState(() {
        _range = r;
        _selected = null;
        _rebuildSeries();
      });
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final PnlChartTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? theme.chipSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? theme.primaryText : theme.axisText,
          ),
        ),
      ),
    );
  }
}
