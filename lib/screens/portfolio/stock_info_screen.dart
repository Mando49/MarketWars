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
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.symbol),
          Text(widget.companyName,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.normal)),
        ]),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.green, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _buildPriceCard(),
                if (_quote != null) _buildStatsGrid(),
                _buildFinancials(),
                _buildDescription(),
              ],
            ),
    );
  }

  Widget _buildPriceCard() {
    if (_quote == null) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('Unable to load quote',
                  style: TextStyle(color: AppTheme.textMuted))));
    }
    final isUp = _quote!.isPositive;
    final changeColor = isUp ? AppTheme.green : AppTheme.red;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF101520), Color(0xFF0B0E17)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.08)),
      ),
      child: Column(children: [
        Text(AppTheme.currency(_quote!.currentPrice),
            style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isUp ? AppTheme.greenDim : AppTheme.redDim,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: changeColor.withValues(alpha: 0.2)),
          ),
          child: Text(
            '${isUp ? "+" : ""}${AppTheme.currency(_quote!.change.abs())} '
            '(${_quote!.changePercent.abs().toStringAsFixed(2)}%) today',
            style: TextStyle(
              color: changeColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFamily: 'Courier',
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      ('OPEN', AppTheme.currency(_quote!.open), AppTheme.textPrimary),
      ('PREV CLOSE', AppTheme.currency(_quote!.prevClose), AppTheme.textPrimary),
      ('HIGH', AppTheme.currency(_quote!.high), AppTheme.green),
      ('LOW', AppTheme.currency(_quote!.low), AppTheme.red),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.6,
        children: stats
            .map((s) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s.$1,
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.textMuted,
                                fontFamily: 'Courier',
                                letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(s.$2,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Courier',
                                color: s.$3)),
                      ]),
                ))
            .toList(),
      ),
    );
  }

  String _formatLargeNumber(double value) {
    if (value >= 1e12) return '\$${(value / 1e12).toStringAsFixed(2)}T';
    if (value >= 1e9) return '\$${(value / 1e9).toStringAsFixed(2)}B';
    if (value >= 1e6) return '\$${(value / 1e6).toStringAsFixed(2)}M';
    return '\$${value.toStringAsFixed(0)}';
  }

  Widget _buildFinancials() {
    final items = <(String, String)>[];

    // Volume from metrics
    final vol = _metrics?['10DayAverageTradingVolume'];
    if (vol != null) {
      final v = (vol as num).toDouble() * 1e6;
      items.add(('VOLUME (10D AVG)', _formatLargeNumber(v)));
    }

    // Market cap from profile
    final mktCap = _profile?['marketCapitalization'];
    if (mktCap != null) {
      items.add(
          ('MARKET CAP', _formatLargeNumber((mktCap as num).toDouble() * 1e6)));
    }

    // 52-week high/low from metrics
    final wk52High = _metrics?['52WeekHigh'];
    final wk52Low = _metrics?['52WeekLow'];
    if (wk52High != null) {
      items.add(('52W HIGH', AppTheme.currency((wk52High as num).toDouble())));
    }
    if (wk52Low != null) {
      items.add(('52W LOW', AppTheme.currency((wk52Low as num).toDouble())));
    }

    // P/E ratio
    final pe = _metrics?['peBasicExclExtraTTM'] ?? _metrics?['peTTM'];
    if (pe != null) {
      items.add(('P/E RATIO', (pe as num).toDouble().toStringAsFixed(2)));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.6,
        children: items
            .map((s) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s.$1,
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.textMuted,
                                fontFamily: 'Courier',
                                letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(s.$2,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Courier')),
                      ]),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildDescription() {
    // Finnhub profile doesn't have a long description, but we can show
    // industry, exchange, and IPO date as context
    if (_profile == null) return const SizedBox.shrink();

    final industry = _profile!['finnhubIndustry'] ?? '';
    final exchange = _profile!['exchange'] ?? '';
    final ipo = _profile!['ipo'] ?? '';
    final weburl = _profile!['weburl'] ?? '';
    final country = _profile!['country'] ?? '';

    if (industry.isEmpty && exchange.isEmpty) return const SizedBox.shrink();

    final parts = <String>[];
    final name = _profile!['name'] ?? widget.companyName;
    if (industry.isNotEmpty) {
      parts.add('$name operates in the $industry industry.');
    }
    if (exchange.isNotEmpty && country.isNotEmpty) {
      parts.add('Listed on $exchange ($country).');
    } else if (exchange.isNotEmpty) {
      parts.add('Listed on $exchange.');
    }
    if (ipo.isNotEmpty) {
      parts.add('IPO date: $ipo.');
    }
    if (weburl.isNotEmpty) {
      parts.add(weburl);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ABOUT',
            style: TextStyle(
                fontSize: 9,
                color: AppTheme.textMuted,
                fontFamily: 'Courier',
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(parts.join(' '),
            style: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.8),
                fontSize: 12,
                height: 1.5)),
      ]),
    );
  }
}
