import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────
// TRENDING STOCKS SCREEN
// ─────────────────────────────────────────
class TrendingScreen extends StatefulWidget {
  const TrendingScreen({super.key});
  @override
  State<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends State<TrendingScreen> {
  bool _isLoading = true;
  List<_TrendingStock> _stocks = [];

  static const List<String> _trendingSymbols = [
    'AAPL', 'MSFT', 'GOOGL', 'AMZN', 'NVDA', 'META', 'TSLA', 'JPM',
    'V', 'JNJ', 'UNH', 'XOM', 'PG', 'MA', 'HD', 'BAC', 'COST',
    'ABBV', 'KO', 'PEP', 'MRK', 'LLY', 'AVGO', 'CRM', 'AMD',
  ];

  static const Map<String, String> _names = {
    'AAPL': 'Apple Inc',
    'MSFT': 'Microsoft Corp',
    'GOOGL': 'Alphabet Inc',
    'AMZN': 'Amazon.com Inc',
    'NVDA': 'NVIDIA Corp',
    'META': 'Meta Platforms',
    'TSLA': 'Tesla Inc',
    'JPM': 'JPMorgan Chase',
    'V': 'Visa Inc',
    'JNJ': 'Johnson & Johnson',
    'UNH': 'UnitedHealth Group',
    'XOM': 'Exxon Mobil',
    'PG': 'Procter & Gamble',
    'MA': 'Mastercard Inc',
    'HD': 'Home Depot',
    'BAC': 'Bank of America',
    'COST': 'Costco Wholesale',
    'ABBV': 'AbbVie Inc',
    'KO': 'Coca-Cola Co',
    'PEP': 'PepsiCo Inc',
    'MRK': 'Merck & Co',
    'LLY': 'Eli Lilly & Co',
    'AVGO': 'Broadcom Inc',
    'CRM': 'Salesforce Inc',
    'AMD': 'Advanced Micro Devices',
  };

  @override
  void initState() {
    super.initState();
    _loadStocks();
  }

  Future<void> _loadStocks() async {
    setState(() => _isLoading = true);
    final prov = context.read<PortfolioProvider>();
    final results = <_TrendingStock>[];

    for (final symbol in _trendingSymbols) {
      try {
        final quote = await prov.fetchQuote(symbol);
        if (quote != null) {
          results.add(_TrendingStock(
            symbol: symbol,
            name: _names[symbol] ?? symbol,
            price: quote.currentPrice,
            change: quote.change,
            changePct: quote.changePercent,
          ));
        }
      } catch (_) {}
    }

    // Sort by absolute % change descending (most volatile first)
    results.sort((a, b) => b.changePct.abs().compareTo(a.changePct.abs()));

    if (mounted) {
      setState(() {
        _stocks = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trending Stocks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isLoading ? null : _loadStocks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.green, strokeWidth: 2))
          : _stocks.isEmpty
              ? const Center(
                  child: Text('Unable to load stocks',
                      style: TextStyle(color: AppTheme.textMuted)))
              : RefreshIndicator(
                  color: AppTheme.green,
                  onRefresh: _loadStocks,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _stocks.length,
                    itemBuilder: (_, i) => _buildRow(_stocks[i], i),
                  ),
                ),
    );
  }

  Widget _buildRow(_TrendingStock stock, int index) {
    final isPositive = stock.changePct >= 0;
    final changeColor = isPositive ? AppTheme.green : AppTheme.red;
    final sign = isPositive ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        // Rank
        SizedBox(
          width: 28,
          child: Text('${index + 1}',
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted)),
        ),
        // Ticker badge
        Container(
          width: 54,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: changeColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: changeColor.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(stock.symbol,
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: changeColor)),
          ),
        ),
        const SizedBox(width: 10),
        // Company name
        Expanded(
          child: Text(stock.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        // Price + change
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(AppTheme.currency(stock.price),
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
                '$sign${stock.changePct.toStringAsFixed(2)}%',
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: changeColor)),
          ),
        ]),
      ]),
    );
  }
}

class _TrendingStock {
  final String symbol;
  final String name;
  final double price;
  final double change;
  final double changePct;

  _TrendingStock({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changePct,
  });
}
