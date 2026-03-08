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
  int _selectedRange = 0; // index into time range chips

  static const _ranges = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUp = _quote?.isPositive ?? true;
    final accent = isUp ? AppTheme.green : AppTheme.red;

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
            icon: const Icon(Icons.ios_share, size: 20, color: AppTheme.textMuted),
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

  // ── Apple-style header: name left, price right ──
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
        // Company name
        Text(widget.companyName,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        // Ticker
        Text(widget.symbol,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 12),
        // Price large
        Text(AppTheme.currency(_quote!.currentPrice),
            style: const TextStyle(
                fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -2)),
        const SizedBox(height: 4),
        // Change row
        Row(children: [
          Icon(arrow, color: accent, size: 22),
          Text(
            '$sign${AppTheme.currency(_quote!.change.abs())} '
            '($sign${_quote!.changePercent.abs().toStringAsFixed(2)}%) today',
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Fake sparkline chart ──
  Widget _buildChart(Color accent) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      height: 180,
      child: CustomPaint(
        size: const Size(double.infinity, 180),
        painter: _ChartPainter(
          color: accent,
          quote: _quote,
          seed: widget.symbol.hashCode,
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
            onTap: () => setState(() => _selectedRange = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_ranges[i],
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

  // ── Stats list (Apple style: label left, value right, dividers) ──
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
      items.add(('Market Cap', _formatCompact((mktCap as num).toDouble() * 1e6)));
    }

    final wk52High = _metrics?['52WeekHigh'];
    final wk52Low = _metrics?['52WeekLow'];
    if (wk52High != null && wk52Low != null) {
      items.add(('52 Week Range',
          '${AppTheme.currency((wk52Low as num).toDouble())} – ${AppTheme.currency((wk52High as num).toDouble())}'));
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
    if (industry.isNotEmpty) parts.add('$name operates in the $industry industry.');
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
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
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
              border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
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

// ── Sparkline chart painter ──
class _ChartPainter extends CustomPainter {
  final Color color;
  final StockQuote? quote;
  final int seed;

  _ChartPainter({required this.color, required this.quote, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (quote == null) return;

    final rng = Random(seed);
    final points = <Offset>[];
    const count = 60;
    final basePrice = quote!.prevClose;
    final endPrice = quote!.currentPrice;
    final range = (quote!.high - quote!.low).clamp(0.5, double.infinity);

    for (int i = 0; i <= count; i++) {
      final t = i / count;
      final trend = basePrice + (endPrice - basePrice) * t;
      final noise = (rng.nextDouble() - 0.5) * range * 0.3;
      final price = trend + noise;
      final x = t * size.width;
      final normalizedY = 1.0 -
          ((price - (basePrice - range * 0.3)) /
              (range * 1.6))
              .clamp(0.0, 1.0);
      final y = normalizedY * (size.height - 20) + 10;
      points.add(Offset(x, y));
    }

    // Draw gradient fill
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Draw end dot
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(points.last, 4, dotPaint);
    final glowPaint = Paint()..color = color.withValues(alpha: 0.2);
    canvas.drawCircle(points.last, 8, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
