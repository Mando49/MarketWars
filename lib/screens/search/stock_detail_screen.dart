import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  final String companyName;

  const StockDetailScreen({
    super.key,
    required this.symbol,
    required this.companyName,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  StockQuote? _quote;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _metrics;
  bool _loading = true;

  int _selectedRange = 0;
  List<double>? _candles;
  bool _candlesLoading = false;

  static const _ranges = [
    ('1D', 'D', 5),
    ('1W', 'D', 10),
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

    if (rangeIndex == 0 && _quote != null) {
      data = _generateIntradayFromQuote(_quote!);
    }

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

  List<double> _generateIntradayFromQuote(StockQuote q) {
    final rng = Random(widget.symbol.hashCode + DateTime.now().day);
    const points = 78;
    final open = q.open > 0 ? q.open : q.prevClose;
    final current = q.currentPrice;
    final dayRange = (q.high - q.low).clamp(0.01, double.infinity);
    final prices = <double>[];

    for (int i = 0; i <= points; i++) {
      final t = i / points;
      final trend = open + (current - open) * t;
      final noise = (rng.nextDouble() - 0.5) * dayRange * 0.25;
      final price = (trend + noise).clamp(q.low, q.high);
      prices.add(price);
    }
    prices[prices.length - 1] = current;
    return prices;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<PortfolioProvider>();
    final holding = prov.holdings.firstWhere(
        (h) => h.symbol == widget.symbol,
        orElse: () => PortfolioHolding(
            symbol: '', companyName: '', shares: 0, averageCost: 0, currentPrice: 0));
    final shortPos = prov.shortPositions.firstWhere(
        (p) => p.symbol == widget.symbol,
        orElse: () => ShortPosition(
            symbol: '', companyName: '', shares: 0, priceAtShort: 0, currentPrice: 0));

    final hasLong = holding.symbol.isNotEmpty && holding.shares > 0;
    final hasShort = shortPos.symbol.isNotEmpty && shortPos.shares > 0;

    Color accent;
    if (_candles != null && _candles!.length >= 2) {
      accent = _candles!.last >= _candles!.first ? AppTheme.green : AppTheme.red;
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.green))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // ── Header: company name, symbol, price ──
                _buildHeader(accent),

                // ── Interactive chart ──
                _buildChart(accent),
                _buildTimeRangeSelector(accent),
                const SizedBox(height: 8),

                // ── Disclaimer ──
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Price data is for simulation purposes only and may be delayed. Not financial advice.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),

                // ── Stats grid ──
                if (_quote != null) _StatsGrid(quote: _quote!),

                // ── Trade buttons ──
                _TradeButtons(
                  symbol: widget.symbol,
                  companyName: widget.companyName,
                  quote: _quote,
                  hasLong: hasLong,
                  hasShort: hasShort,
                  holdingShares: holding.shares,
                  shortShares: shortPos.shares,
                ),

                // ── Short explanation ──
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('\u{1F4C9} Short Selling',
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppTheme.purple, fontFamily: 'Courier',
                        )),
                    const SizedBox(height: 4),
                    const Text(
                      'Bet this stock goes DOWN. You profit if the price drops '
                      'after you short it. Tap Cover to close your position and '
                      'lock in gains (or losses).',
                      style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 11,
                        fontFamily: 'Courier', height: 1.5,
                      )),
                    if (hasShort) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Open: ${shortPos.shares.toStringAsFixed(4)} shares @ '
                        '${AppTheme.currency(shortPos.priceAtShort)} \u{00B7} '
                        'P&L: ${shortPos.gainLoss >= 0 ? "+" : ""}'
                        '${AppTheme.currency(shortPos.gainLoss)}',
                        style: TextStyle(
                          color: shortPos.gainLoss >= 0 ? AppTheme.green : AppTheme.red,
                          fontSize: 11, fontFamily: 'Courier', fontWeight: FontWeight.w700,
                        )),
                    ],
                  ]),
                ),

                // ── About section ──
                if (_profile != null) _buildAboutSection(),

                if (prov.errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(prov.errorMessage,
                        style: const TextStyle(color: AppTheme.red, fontSize: 13),
                        textAlign: TextAlign.center),
                  ),
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

  // ── Chart ──
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
            ),
            child: Row(children: [
              Text(e.value.$1,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(e.value.$2,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
        const SizedBox(height: 4),
      ]),
    );
  }
}

// ── Stats grid ──
class _StatsGrid extends StatelessWidget {
  final StockQuote quote;
  const _StatsGrid({required this.quote});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('OPEN', AppTheme.currency(quote.open), AppTheme.textPrimary),
      ('PREV CLOSE', AppTheme.currency(quote.prevClose), AppTheme.textPrimary),
      ('HIGH', AppTheme.currency(quote.high), AppTheme.green),
      ('LOW', AppTheme.currency(quote.low), AppTheme.red),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.6,
        children: stats.map((s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(s.$1, style: const TextStyle(
              fontSize: 9, color: AppTheme.textMuted,
              fontFamily: 'Courier', letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(s.$2, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              fontFamily: 'Courier', color: s.$3)),
          ]),
        )).toList(),
      ),
    );
  }
}

// ── Buy / Sell / Short / Cover buttons ──
class _TradeButtons extends StatelessWidget {
  final String symbol, companyName;
  final StockQuote? quote;
  final bool hasLong, hasShort;
  final double holdingShares, shortShares;

  const _TradeButtons({
    required this.symbol, required this.companyName, required this.quote,
    required this.hasLong, required this.hasShort,
    required this.holdingShares, required this.shortShares,
  });

  void _open(BuildContext context, String mode) {
    if (quote == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _TradeModal(
        symbol: symbol, companyName: companyName,
        price: quote!.currentPrice, mode: mode,
        maxShares: mode == 'sell' ? holdingShares
                 : mode == 'cover' ? shortShares
                 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(children: [
        Row(children: [
          Expanded(child: _Btn(
            label: 'Buy', color: AppTheme.green, textColor: Colors.black,
            onTap: () => _open(context, 'buy'))),
          const SizedBox(width: 10),
          Expanded(child: _Btn(
            label: hasLong ? 'Sell (${holdingShares.toStringAsFixed(2)})' : 'Sell',
            color: AppTheme.redDim, textColor: AppTheme.red,
            border: AppTheme.red.withValues(alpha: 0.3),
            onTap: hasLong ? () => _open(context, 'sell') : null)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _Btn(
            label: '\u{1F4C9} Short', color: AppTheme.purple.withValues(alpha: 0.08),
            textColor: AppTheme.purple, border: AppTheme.purple.withValues(alpha: 0.3),
            onTap: () => _open(context, 'short'))),
          const SizedBox(width: 10),
          Expanded(child: _Btn(
            label: hasShort ? '\u{2705} Cover (${shortShares.toStringAsFixed(2)})' : '\u{2705} Cover',
            color: AppTheme.purple.withValues(alpha: 0.15), textColor: AppTheme.purple,
            border: AppTheme.purple.withValues(alpha: 0.3),
            onTap: hasShort ? () => _open(context, 'cover') : null)),
        ]),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color, textColor;
  final Color? border;
  final VoidCallback? onTap;

  const _Btn({
    required this.label, required this.color,
    required this.textColor, this.border, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: disabled ? AppTheme.surface2 : color,
          borderRadius: BorderRadius.circular(14),
          border: border != null
              ? Border.all(color: disabled ? AppTheme.border : border!)
              : null,
        ),
        child: Center(child: Text(label,
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: disabled ? AppTheme.textMuted : textColor,
          ))),
      ),
    );
  }
}

// ── Trade modal ──
class _TradeModal extends StatefulWidget {
  final String symbol, companyName, mode;
  final double price;
  final double? maxShares;

  const _TradeModal({
    required this.symbol, required this.companyName,
    required this.price, required this.mode, this.maxShares,
  });

  @override
  State<_TradeModal> createState() => _TradeModalState();
}

class _TradeModalState extends State<_TradeModal> {
  final _ctrl = TextEditingController(text: '1');
  bool _busy = false;

  double get _shares => double.tryParse(_ctrl.text) ?? 0;
  double get _total  => _shares * widget.price;

  Color get _accentColor =>
      widget.mode == 'buy'   ? AppTheme.green
    : widget.mode == 'sell'  ? AppTheme.red
    : AppTheme.purple;

  String get _actionLabel =>
      widget.mode == 'buy'        ? 'Confirm Buy'
    : widget.mode == 'sell'       ? 'Confirm Sell'
    : widget.mode == 'short'      ? 'Confirm Short'
    : 'Confirm Cover';

  String? get _infoText =>
      widget.mode == 'short'
        ? '\u{1F4C9} You profit if the price goes DOWN. You lose if it goes UP.'
        : widget.mode == 'cover'
        ? '\u{2705} Buying back shares to close your short position.'
        : null;

  Future<void> _confirm() async {
    final prov = context.read<PortfolioProvider>();
    setState(() => _busy = true);
    bool ok = false;
    switch (widget.mode) {
      case 'buy':
        ok = await prov.buyStock(widget.symbol, widget.companyName, _shares, widget.price);
        break;
      case 'sell':
        ok = await prov.sellStock(widget.symbol, _shares, widget.price);
        break;
      case 'short':
        ok = await prov.shortStock(widget.symbol, widget.companyName, _shares, widget.price);
        break;
      case 'cover':
        ok = await prov.coverShort(widget.symbol, _shares, widget.price);
        break;
    }
    if (mounted) {
      setState(() => _busy = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = {
      'buy': 'Buy ${widget.symbol}', 'sell': 'Sell ${widget.symbol}',
      'short': '\u{1F4C9} Short ${widget.symbol}', 'cover': '\u{2705} Cover ${widget.symbol}',
    };

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          Text(titles[widget.mode]!,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Current price: ${AppTheme.currency(widget.price)}',
            style: const TextStyle(color: AppTheme.textMuted, fontFamily: 'Courier', fontSize: 12)),
          if (_infoText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
              ),
              child: Text(_infoText!,
                style: const TextStyle(
                  color: AppTheme.purple, fontSize: 11,
                  fontFamily: 'Courier', height: 1.4),
                textAlign: TextAlign.center),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.08)),
            ),
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Courier'),
              decoration: const InputDecoration(
                border: InputBorder.none, hintText: '0.0000',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                suffixText: 'shares',
                suffixStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
            ),
            child: Center(child: Text('Total: ${AppTheme.currency(_total)}',
              style: TextStyle(
                color: _accentColor, fontWeight: FontWeight.w700,
                fontSize: 14, fontFamily: 'Courier',
              ))),
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _busy ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: widget.mode == 'buy' ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: _busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(_actionLabel,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ]),
      ),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
}

// ── Chart painter ──
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

    final points = <Offset>[];
    for (int i = 0; i < prices.length; i++) {
      final x = (i / (prices.length - 1)) * size.width;
      final normalized = (prices[i] - minPrice) / priceRange;
      final y = (1.0 - normalized) * (size.height - padding * 2) + padding;
      points.add(Offset(x, y));
    }

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

    final last = points.last;
    canvas.drawCircle(last, 4, Paint()..color = color);
    canvas.drawCircle(last, 8, Paint()..color = color.withValues(alpha: 0.2));

    final textStyle = TextStyle(
      color: color.withValues(alpha: 0.5),
      fontSize: 10,
      fontFamily: 'Courier',
    );
    _drawText(canvas, AppTheme.currency(maxPrice), const Offset(4, padding - 2), textStyle);
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
