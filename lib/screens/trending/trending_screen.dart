import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';
import '../search/stock_detail_screen.dart';

// ─────────────────────────────────────────
// TRENDING STOCKS SCREEN
// ─────────────────────────────────────────
class TrendingScreen extends StatefulWidget {
  const TrendingScreen({super.key});
  @override
  State<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends State<TrendingScreen> {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _isLoading = true;
  List<_TrendingStock> _stocks = [];
  // symbol -> Firestore doc ID for removal
  Map<String, String> _watchlistDocs = {};

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
    _loadWatchlistDocs();
  }

  Future<void> _loadWatchlistDocs() async {
    if (_uid.isEmpty) return;
    try {
      final snap = await _db
          .collection('users')
          .doc(_uid)
          .collection('watchlist')
          .get();
      if (mounted) {
        setState(() {
          _watchlistDocs = {
            for (final d in snap.docs) (d.data()['symbol'] ?? '') as String: d.id,
          };
        });
      }
    } catch (_) {}
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

    results.sort((a, b) => b.changePct.abs().compareTo(a.changePct.abs()));

    if (mounted) {
      setState(() {
        _stocks = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleWatchlist(_TrendingStock stock) async {
    if (_uid.isEmpty) return;
    final docId = _watchlistDocs[stock.symbol];

    if (docId != null) {
      // Remove from watchlist
      try {
        await _db
            .collection('users')
            .doc(_uid)
            .collection('watchlist')
            .doc(docId)
            .delete();
        if (mounted) {
          setState(() => _watchlistDocs.remove(stock.symbol));
          context.read<PortfolioProvider>().loadWatchlist();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${stock.symbol} removed from watchlist'),
              backgroundColor: AppTheme.surface2,
            ),
          );
        }
      } catch (_) {}
      return;
    }

    // Check watchlist count before adding
    if (_watchlistDocs.length >= 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Watchlist is full (10/10)'),
            backgroundColor: AppTheme.surface2,
          ),
        );
      }
      return;
    }

    try {
      final docRef =
          await _db.collection('users').doc(_uid).collection('watchlist').add({
        'symbol': stock.symbol,
        'companyName': stock.name,
        'costBasis': stock.price,
        'shares': 100.0,
        'addedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _watchlistDocs[stock.symbol] = docRef.id);
        context.read<PortfolioProvider>().loadWatchlist();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${stock.symbol} added to watchlist'),
            backgroundColor: AppTheme.surface2,
          ),
        );
      }
    } catch (_) {}
  }

  void _openStockInfo(_TrendingStock stock) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StockDetailScreen(symbol: stock.symbol, companyName: stock.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: const Text('Trending'),
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
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      // Section header
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Top Movers',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                      // Card container
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: _stocks.asMap().entries.map((e) {
                            return _buildRow(e.value, e.key);
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRow(_TrendingStock stock, int index) {
    final isPositive = stock.changePct >= 0;
    final changeColor = isPositive ? AppTheme.green : AppTheme.red;
    final sign = isPositive ? '+' : '';
    final isLast = index == _stocks.length - 1;
    final inWatchlist = _watchlistDocs.containsKey(stock.symbol);

    return GestureDetector(
      onTap: () => _openStockInfo(stock),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: AppTheme.border, width: 0.5)),
        ),
        child: Row(children: [
          // Left: symbol + name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stock.symbol,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(stock.name,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Middle: price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(AppTheme.currency(stock.price),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Courier')),
          ),
          // Right: change badge (Apple style fixed-width pill)
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: changeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$sign${stock.changePct.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Courier',
                ),
              ),
            ),
          ),
          // Watchlist add button
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _toggleWatchlist(stock),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: inWatchlist
                    ? AppTheme.green.withValues(alpha: 0.08)
                    : AppTheme.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                inWatchlist ? Icons.check : Icons.add,
                size: 18,
                color: inWatchlist ? AppTheme.green : AppTheme.textMuted,
              ),
            ),
          ),
        ]),
      ),
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
