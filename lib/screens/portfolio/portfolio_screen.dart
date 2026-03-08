import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';
import 'stock_info_screen.dart';

// ─────────────────────────────────────────
// PORTFOLIO SCREEN — Watchlist Tracker
// ─────────────────────────────────────────
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  // Trending stocks shown by default below search bar
  List<Map<String, dynamic>> _trendingStocks = [];
  bool _isTrendingLoading = false;

  // Watchlist: {symbol, companyName, costBasis, shares, currentPrice}
  List<Map<String, dynamic>> _watchlist = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  StreamSubscription? _watchlistSub;

  static const int _maxWatchlist = 10;
  static const double _sharesPerAdd = 100;

  @override
  void initState() {
    super.initState();
    _listenWatchlist();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _watchlistSub?.cancel();
    super.dispose();
  }

  // ── Firestore real-time listener ──────────────

  void _listenWatchlist() {
    if (_uid.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    _watchlistSub = _db
        .collection('users')
        .doc(_uid)
        .collection('watchlist')
        .orderBy('addedAt', descending: false)
        .snapshots()
        .listen((snap) {
      final items = snap.docs.map((d) {
        final data = d.data();
        // Preserve existing currentPrice if we already have it
        final existing = _watchlist.cast<Map<String, dynamic>?>().firstWhere(
            (w) => w?['id'] == d.id,
            orElse: () => null);
        final existingPrice = existing?['currentPrice'] as double?;

        return {
          'id': d.id,
          'symbol': data['symbol'] ?? '',
          'companyName': data['companyName'] ?? '',
          'costBasis': (data['costBasis'] ?? 0).toDouble(),
          'shares': (data['shares'] ?? _sharesPerAdd).toDouble(),
          'currentPrice':
              existingPrice ?? (data['costBasis'] ?? 0).toDouble(),
        };
      }).toList();

      if (mounted) {
        final oldLen = _watchlist.length;
        setState(() {
          _watchlist = items;
          _isLoading = false;
        });
        // Refresh prices on first load or when items added
        if (oldLen == 0 || items.length > oldLen) {
          _refreshPrices();
        }
      }
    }, onError: (_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _refreshPrices() async {
    if (_watchlist.isEmpty) return;
    setState(() => _isRefreshing = true);

    final prov = context.read<PortfolioProvider>();
    for (int i = 0; i < _watchlist.length; i++) {
      try {
        final quote = await prov.fetchQuote(_watchlist[i]['symbol']);
        if (quote != null && mounted) {
          setState(() => _watchlist[i]['currentPrice'] = quote.currentPrice);
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadTrending() async {
    setState(() => _isTrendingLoading = true);
    final prov = context.read<PortfolioProvider>();

    // Wait for provider's trending data if not yet loaded
    if (prov.trendingStocks.isEmpty && !prov.isTrendingLoading) {
      await prov.loadTrending();
    } else if (prov.isTrendingLoading) {
      // Wait for in-progress load to finish
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 200));
        return prov.isTrendingLoading;
      });
    }

    if (!mounted) return;
    final trending = prov.trendingStocks.take(10).map((t) => {
          'symbol': t.symbol,
          'name': t.companyName,
          'price': t.price,
          'change': 0.0,
          'changePct': t.changePercent,
        }).toList();

    setState(() {
      _trendingStocks = trending;
      _isTrendingLoading = false;
    });
  }

  void _openStockInfo(String symbol, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockInfoScreen(symbol: symbol, companyName: name),
      ),
    );
  }

  Future<void> _addToWatchlist(Map<String, dynamic> stock) async {
    if (_uid.isEmpty || _watchlist.length >= _maxWatchlist) return;
    if (_watchlist.any((w) => w['symbol'] == stock['symbol'])) return;

    final price = (stock['price'] as double?) ?? 0.0;
    final entry = {
      'symbol': stock['symbol'],
      'companyName': stock['name'],
      'costBasis': price,
      'shares': _sharesPerAdd,
      'addedAt': FieldValue.serverTimestamp(),
    };

    try {
      final docRef = await _db
          .collection('users')
          .doc(_uid)
          .collection('watchlist')
          .add(entry);

      setState(() {
        _watchlist.add({
          'id': docRef.id,
          'symbol': stock['symbol'],
          'companyName': stock['name'],
          'costBasis': price,
          'shares': _sharesPerAdd,
          'currentPrice': price,
        });
      });
    } catch (_) {}
  }

  Future<void> _removeFromWatchlist(int index) async {
    if (_uid.isEmpty) return;
    final item = _watchlist[index];
    final docId = item['id'] as String?;

    setState(() => _watchlist.removeAt(index));

    if (docId != null) {
      try {
        await _db
            .collection('users')
            .doc(_uid)
            .collection('watchlist')
            .doc(docId)
            .delete();
      } catch (_) {}
    }
  }

  // ── Portfolio value calculations ───────

  // Total P&L = sum of (currentPrice - costBasis) * shares for each stock
  double get _totalGainLoss {
    double total = 0;
    for (final w in _watchlist) {
      final current = (w['currentPrice'] as double);
      final cost = (w['costBasis'] as double);
      final shares = (w['shares'] as double);
      total += (current - cost) * shares;
    }
    return total;
  }

  // Total cost basis for % calculation
  double get _totalCostBasis {
    double total = 0;
    for (final w in _watchlist) {
      total += (w['costBasis'] as double) * (w['shares'] as double);
    }
    return total;
  }

  double get _portfolioPctChange {
    if (_watchlist.isEmpty || _totalCostBasis == 0) return 0;
    return (_totalGainLoss / _totalCostBasis) * 100;
  }

  // ── Search ─────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final prov = context.read<PortfolioProvider>();
      final results = await prov.searchStocks(query);
      if (!mounted) return;

      final limited = results.take(10).toList();
      final withPrices = await Future.wait(limited.map((r) async {
        try {
          final q = await prov.fetchQuote(r.symbol);
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': q?.currentPrice ?? 0.0,
            'change': q?.change ?? 0.0,
            'changePct': q?.changePercent ?? 0.0,
          };
        } catch (_) {
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': 0.0, 'change': 0.0, 'changePct': 0.0,
          };
        }
      }));

      if (!mounted) return;
      setState(() { _searchResults = withPrices; _isSearching = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  // ── Build ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.green))
                : const Icon(Icons.refresh, size: 20),
            onPressed: _isRefreshing ? null : _refreshPrices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.green, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _buildValueCard(),
                _buildWatchlistSection(),
                _buildSearchSection(),
              ],
            ),
    );
  }

  // ── Portfolio value header card ────────

  Widget _buildValueCard() {
    final gainLoss = _totalGainLoss;
    final pct = _portfolioPctChange;
    final isUp = gainLoss >= 0;
    final changeColor = _watchlist.isEmpty
        ? AppTheme.textMuted
        : (isUp ? AppTheme.green : AppTheme.red);
    final sign = isUp ? '+' : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0F1A), Color(0xFF060810)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: changeColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: changeColor.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(children: [
        Text(_watchlist.isEmpty ? 'PORTFOLIO P&L' : 'TOTAL P&L',
            style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 2,
                fontFamily: 'Courier')),
        const SizedBox(height: 6),
        Text('$sign${AppTheme.currency(gainLoss)}',
            style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
                color: _watchlist.isEmpty ? AppTheme.textPrimary : changeColor)),
        const SizedBox(height: 8),
        if (_watchlist.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: changeColor.withValues(alpha: 0.2)),
            ),
            child: Text(
              '$sign${pct.toStringAsFixed(2)}% since added',
              style: TextStyle(
                color: changeColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                fontFamily: 'Courier',
              ),
            ),
          )
        else
          const Text('Add stocks to start tracking',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'Courier')),
      ]),
    );
  }

  // ── Watchlist section ──────────────────

  Widget _buildWatchlistSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            const Text('WATCHLIST',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontFamily: 'Courier',
                    letterSpacing: 2)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('${_watchlist.length}/$_maxWatchlist',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.green,
                      fontFamily: 'Courier')),
            ),
          ]),
        ),
        if (_watchlist.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(children: [
                Text('No stocks in your watchlist',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                SizedBox(height: 4),
                Text('Search below to add stocks',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ]),
            ),
          )
        else
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: _watchlist
                    .asMap()
                    .entries
                    .map((e) => _buildWatchlistRow(e.value, e.key))
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWatchlistRow(Map<String, dynamic> item, int index) {
    final costBasis = (item['costBasis'] as double);
    final currentPrice = (item['currentPrice'] as double);
    final pctChange =
        costBasis > 0 ? ((currentPrice - costBasis) / costBasis) * 100 : 0.0;
    final isUp = pctChange >= 0;
    final changeColor = isUp ? AppTheme.green : AppTheme.red;
    final sign = isUp ? '+' : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        // Color indicator
        Container(
          width: 3,
          height: 40,
          decoration: BoxDecoration(
            color: changeColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        // Stock info
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['symbol'],
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            Text(item['companyName'],
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                overflow: TextOverflow.ellipsis),
            Text(
                '${(item['shares'] as double).toStringAsFixed(0)} shares @ ${AppTheme.currency(costBasis)}',
                style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Courier')),
          ]),
        ),
        // Price + change
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(AppTheme.currency(currentPrice),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: changeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$sign${pctChange.toStringAsFixed(2)}%',
                style: TextStyle(
                    color: changeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    fontFamily: 'Courier')),
          ),
        ]),
        const SizedBox(width: 8),
        // Delete button
        GestureDetector(
          onTap: () => _removeFromWatchlist(index),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.close, size: 14, color: AppTheme.red),
          ),
        ),
      ]),
    );
  }

  // ── Search section ─────────────────────

  Widget _buildSearchSection() {
    final isFull = _watchlist.length >= _maxWatchlist;
    final hasQuery = _searchCtrl.text.isNotEmpty;
    final showTrending = !hasQuery && !_isSearching;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('SEARCH STOCKS',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  letterSpacing: 2)),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: isFull
                    ? 'Watchlist full (10/10)'
                    : 'Ticker or company name...',
                hintStyle:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AppTheme.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                suffixIcon: hasQuery
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchResults = []);
                        },
                        child: const Icon(Icons.close,
                            size: 16, color: AppTheme.textMuted),
                      )
                    : null,
              ),
            ),
          ),
        ),
        // Trending / Search results
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: CircularProgressIndicator(
                    color: AppTheme.green, strokeWidth: 2)),
          )
        else if (hasQuery && _searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: _searchResults
                    .map((s) => _buildSearchRow(s, isFull))
                    .toList(),
              ),
            ),
          )
        else if (hasQuery && _searchResults.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: Text('No results found',
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 12))),
          )
        else if (showTrending) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(children: [
              Icon(Icons.trending_up, size: 14, color: AppTheme.green),
              SizedBox(width: 6),
              Text('TRENDING',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier',
                      letterSpacing: 2)),
            ]),
          ),
          if (_isTrendingLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.green, strokeWidth: 2)),
            )
          else if (_trendingStocks.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: _trendingStocks
                      .map((s) => _buildSearchRow(s, isFull))
                      .toList(),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSearchRow(Map<String, dynamic> stock, bool isFull) {
    final alreadyAdded =
        _watchlist.any((w) => w['symbol'] == stock['symbol']);
    final price = (stock['price'] as double?) ?? 0.0;
    final changePct = (stock['changePct'] as double?) ?? 0.0;
    final isUp = changePct >= 0;
    final changeColor = isUp ? AppTheme.green : AppTheme.red;
    final sign = isUp ? '+' : '';

    return GestureDetector(
      onTap: () => _openStockInfo(
        stock['symbol'] as String,
        stock['name'] as String,
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
        ),
        child: Row(children: [
          // Left: symbol + name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stock['symbol'],
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(stock['name'],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          // Middle: price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(AppTheme.currency(price),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Courier')),
          ),
          // Right: change badge (Apple style)
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: changeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$sign${changePct.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Courier',
                ),
              ),
            ),
          ),
          // Add / check / full button
          const SizedBox(width: 10),
          if (alreadyAdded)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check, size: 18, color: AppTheme.green),
            )
          else if (isFull)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.block, size: 18, color: AppTheme.textMuted),
            )
          else
            GestureDetector(
              onTap: () => _addToWatchlist(stock),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, size: 18, color: AppTheme.textMuted),
              ),
            ),
        ]),
      ),
    );
  }
}
