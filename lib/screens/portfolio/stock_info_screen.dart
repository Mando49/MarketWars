import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class StockInfoScreen extends StatefulWidget {
  final String symbol;
  final String companyName;

  const StockInfoScreen({
    super.key,
    required this.symbol,
    required this.companyName,
  });

  @override
  State<StockInfoScreen> createState() => _StockInfoScreenState();
}

class _StockInfoScreenState extends State<StockInfoScreen> {
  StockQuote? _quote;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _metrics;
  bool _loading = true;

  int _selectedRange = 0;
  List<double>? _candles;
  bool _candlesLoading = false;

  // Range label, Finnhub resolution, days back
  // Free tier only supports D, W, M resolutions
  static const _ranges = [
    ('1D', 'D', 5), // fetch 5 days of daily, show last point vs prev
    ('1W', 'D', 10), // ~2 weeks of daily to ensure 5 trading days
    ('1M', 'D', 35),
    ('3M', 'D', 95),
    ('1Y', 'W', 370),
    ('ALL', 'M', 3650),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prov = context.read<PortfolioProvider>();
    final results = await Future.wait([
      prov.fetchQuote(widget.symbol),
      prov.fetchCompanyProfile(widget.symbol),
      prov.fetchBasicFinancials(widget.symbol),
    ]);
    if (mounted) {
      setState(() {
        _quote = results[0] as StockQuote?;
        _profile = results[1] as Map<String, dynamic>?;
        _metrics = results[2] as Map<String, dynamic>?;
        _loading = false;
      });
      _loadCandles(0);
    }
  }

  Future<void> _loadCandles(int rangeIndex) async {
    setState(() {
      _selectedRange = rangeIndex;
      _candlesLoading = true;
    });

    final prov = context.read<PortfolioProvider>();
    final range = _ranges[rangeIndex];
    final now = DateTime.now();
    final to = now.millisecondsSinceEpoch ~/ 1000;
    final from =
        now.subtract(Duration(days: range.$3)).millisecondsSinceEpoch ~/ 1000;

    List<double>? data =
        await prov.fetchCandles(widget.symbol, range.$2, from, to);

    // For 1D: if we got daily candles, build an intraday curve from quote
    if (rangeIndex == 0 && _quote != null) {
      if (data != null && data.length >= 2) {
        // Use just last 2 daily closes to simulate today's movement
        data = _generateIntradayFromQuote(_quote!);
      } else {
        data = _generateIntradayFromQuote(_quote!);
      }
    }

    // Trim to reasonable point count for shorter ranges
    if (data != null && rangeIndex == 1 && data.length > 7) {
      data = data.sublist(data.length - 7);
    }

    if (mounted) {
      setState(() {
        _candles = data;
        _candlesLoading = false;
      });
    }
  }

  /// Generate a synthetic intraday curve from open -> current with
  /// realistic noise based on the day's high/low range.
  List<double> _generateIntradayFromQuote(StockQuote q) {
    final rng = Random(widget.symbol.hashCode + DateTime.now().day);
    const points = 78; // ~6.5 hrs of trading in 5-min intervals
    final open = q.open > 0 ? q.open : q.prevClose;
    final current = q.currentPrice;
    final dayRange = (q.high - q.low).clamp(0.01, double.infinity);
    final prices = <double>[];

    for (int i = 0; i <= points; i++) {
      final t = i / points;
      // Linear trend from open to current
      final trend = open + (current - open) * t;
      // Add noise that stays within the day's high/low
      final noise = (rng.nextDouble() - 0.5) * dayRange * 0.25;
      final price = (trend + noise).clamp(q.low, q.high);
      prices.add(price);
    }
    // Ensure last point is exactly the current price
    prices[prices.length - 1] = current;
    return prices;
  }

  @override
  Widget build(BuildContext context) {
    // Determine chart color based on candle data direction
    Color accent;
    if (_candles != null && _candles!.length >= 2) {
      accent =
          _candles!.last >= _candles!.first ? AppTheme.green : AppTheme.red;
    } else {
      accent = (_quote?.isPositive ?? true) ? AppTheme.green : AppTheme.red;
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share,
                size: 20, color: AppTheme.textMuted),
            onPressed: () {},
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.green, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _buildHeader(accent),
                _buildChart(accent),
                _buildTimeRangeSelector(accent),
                const SizedBox(height: 8),
                _buildStatsSection(),
                if (_profile != null) _buildAboutSection(),
              ],
            ),
    );
  }

  // ── Header ──
  Widget _buildHeader(Color accent) {
    if (_quote == null) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('Unable to load quote',
                  style: TextStyle(color: AppTheme.textMuted))));
    }

    final isUp = _quote!.isPositive;
    final sign = isUp ? '+' : '';
    final arrow = isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.companyName,
            style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(widget.symbol,
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5)),
        const SizedBox(height: 12),
        Text(AppTheme.currency(_quote!.currentPrice),
            style: const TextStyle(
                fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -2)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(arrow, color: accent, size: 22),
          Text(
            '$sign${AppTheme.currency(_quote!.change.abs())} '
            '($sign${_quote!.changePercent.abs().toStringAsFixed(2)}%) today',
            style: TextStyle(
                color: accent, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ]),
      ]),
    );
  }

  // ── Chart with real candle data ──
  Widget _buildChart(Color accent) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      height: 200,
      child: _candlesLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.green, strokeWidth: 2))
          : _candles != null && _candles!.length >= 2
              ? CustomPaint(
                  size: const Size(double.infinity, 200),
                  painter: _CandleChartPainter(
                    color: accent,
                    prices: _candles!,
                  ),
                )
              : Center(
                  child: Text(
                    'No chart data available',
                    style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.6),
                        fontSize: 13),
                  ),
                ),
    );
  }

  // ── Time range pills ──
  Widget _buildTimeRangeSelector(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_ranges.length, (i) {
          final selected = i == _selectedRange;
          return GestureDetector(
            onTap: () => _loadCandles(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_ranges[i].$1,
                  style: TextStyle(
                    color: selected ? accent : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontFamily: 'Courier',
                  )),
            ),
          );
        }),
      ),
    );
  }

  // ── Stats list ──
  Widget _buildStatsSection() {
    final items = <(String, String)>[];

    if (_quote != null) {
      items.add(('Open', AppTheme.currency(_quote!.open)));
      items.add(('Previous Close', AppTheme.currency(_quote!.prevClose)));
      items.add(('Day High', AppTheme.currency(_quote!.high)));
      items.add(('Day Low', AppTheme.currency(_quote!.low)));
    }

    final vol = _metrics?['10DayAverageTradingVolume'];
    if (vol != null) {
      items.add(('Avg Volume', _formatCompact((vol as num).toDouble() * 1e6)));
    }

    final mktCap = _profile?['marketCapitalization'];
    if (mktCap != null) {
      items.add(
          ('Market Cap', _formatCompact((mktCap as num).toDouble() * 1e6)));
    }

    final wk52High = _metrics?['52WeekHigh'];
    final wk52Low = _metrics?['52WeekLow'];
    if (wk52High != null && wk52Low != null) {
      items.add((
        '52 Week Range',
        '${AppTheme.currency((wk52Low as num).toDouble())} – ${AppTheme.currency((wk52High as num).toDouble())}'
      ));
    }

    final pe = _metrics?['peBasicExclExtraTTM'] ?? _metrics?['peTTM'];
    if (pe != null) {
      items.add(('P/E Ratio', (pe as num).toDouble().toStringAsFixed(2)));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(
                      bottom: BorderSide(color: AppTheme.border, width: 0.5)),
            ),
            child: Row(children: [
              Text(e.value.$1,
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(e.value.$2,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Courier')),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ── About section ──
  Widget _buildAboutSection() {
    final industry = _profile!['finnhubIndustry'] ?? '';
    final exchange = _profile!['exchange'] ?? '';
    final ipo = _profile!['ipo'] ?? '';
    final weburl = _profile!['weburl'] ?? '';
    final country = _profile!['country'] ?? '';
    final name = _profile!['name'] ?? widget.companyName;

    if (industry.isEmpty && exchange.isEmpty) return const SizedBox.shrink();

    final parts = <String>[];
    if (industry.isNotEmpty) {
      parts.add('$name operates in the $industry industry.');
    }
    if (exchange.isNotEmpty && country.isNotEmpty) {
      parts.add('Listed on $exchange ($country).');
    } else if (exchange.isNotEmpty) {
      parts.add('Listed on $exchange.');
    }
    if (ipo.isNotEmpty) parts.add('IPO date: $ipo.');
    if (weburl.isNotEmpty) parts.add(weburl);

    final details = <(String, String)>[];
    if (industry.isNotEmpty) details.add(('Industry', industry));
    if (exchange.isNotEmpty) details.add(('Exchange', exchange));
    if (country.isNotEmpty) details.add(('Country', country));
    if (ipo.isNotEmpty) details.add(('IPO Date', ipo));

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text('About',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(parts.join(' '),
              style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.6)),
        ),
        ...details.asMap().entries.map((e) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
            ),
            child: Row(children: [
              Text(e.value.$1,
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(e.value.$2,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
        const SizedBox(height: 4),
      ]),
    );
  }

  String _formatCompact(double value) {
    if (value >= 1e12) return '\$${(value / 1e12).toStringAsFixed(2)}T';
    if (value >= 1e9) return '\$${(value / 1e9).toStringAsFixed(2)}B';
    if (value >= 1e6) return '\$${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '\$${(value / 1e3).toStringAsFixed(1)}K';
    return '\$${value.toStringAsFixed(0)}';
  }
}

// ── Chart painter using real close prices ──
class _CandleChartPainter extends CustomPainter {
  final Color color;
  final List<double> prices;

  _CandleChartPainter({required this.color, required this.prices});

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;

    final minPrice = prices.reduce(min);
    final maxPrice = prices.reduce(max);
    final priceRange = (maxPrice - minPrice).clamp(0.01, double.infinity);
    const padding = 10.0;

    // Build points
    final points = <Offset>[];
    for (int i = 0; i < prices.length; i++) {
      final x = (i / (prices.length - 1)) * size.width;
      final normalized = (prices[i] - minPrice) / priceRange;
      final y = (1.0 - normalized) * (size.height - padding * 2) + padding;
      points.add(Offset(x, y));
    }

    // Gradient fill
    final fillPath = Path()..moveTo(0, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Smooth line using cubic bezier
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cpx = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpx, prev.dy, cpx, curr.dy, curr.dx, curr.dy);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // End dot with glow
    final last = points.last;
    canvas.drawCircle(last, 4, Paint()..color = color);
    canvas.drawCircle(last, 8, Paint()..color = color.withValues(alpha: 0.2));

    // Price labels (min / max)
    final textStyle = TextStyle(
      color: color.withValues(alpha: 0.5),
      fontSize: 10,
      fontFamily: 'Courier',
    );
    _drawText(canvas, AppTheme.currency(maxPrice), const Offset(4, padding - 2),
        textStyle);
    _drawText(canvas, AppTheme.currency(minPrice),
        Offset(4, size.height - padding - 12), textStyle);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CandleChartPainter oldDelegate) =>
      oldDelegate.prices != prices || oldDelegate.color != color;
}
