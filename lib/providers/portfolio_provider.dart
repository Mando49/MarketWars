import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../services/i_stock_service.dart';
import '../services/finnhub_stock_service.dart';

class PortfolioProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final IStockService _stockService;

  PortfolioProvider({IStockService? stockService})
      : _stockService = stockService ?? FinnhubStockService();

  // Stocks shown in the Trending section — refreshed with live prices on load
  static const List<Map<String, String>> _trendingSymbols = [
    {'symbol': 'NVDA', 'name': 'NVIDIA Corp.'},
    {'symbol': 'AAPL', 'name': 'Apple Inc.'},
    {'symbol': 'TSLA', 'name': 'Tesla Inc.'},
    {'symbol': 'META', 'name': 'Meta Platforms'},
    {'symbol': 'AMZN', 'name': 'Amazon.com'},
    {'symbol': 'MSFT', 'name': 'Microsoft Corp.'},
    {'symbol': 'GOOGL', 'name': 'Alphabet Inc.'},
    {'symbol': 'AMD', 'name': 'Advanced Micro Devices'},
    {'symbol': 'PLTR', 'name': 'Palantir Technologies'},
    {'symbol': 'SOFI', 'name': 'SoFi Technologies'},
    {'symbol': 'RIVN', 'name': 'Rivian Automotive'},
    {'symbol': 'COIN', 'name': 'Coinbase Global'},
  ];

  // ── State ──
  UserProfile? userProfile;
  List<PortfolioHolding> holdings = [];
  List<ShortPosition> shortPositions = [];
  List<Trade> trades = [];
  List<TrendingStock> trendingStocks = [];
  List<Map<String, dynamic>> watchlist = [];
  bool isLoading = false;
  bool isTrendingLoading = false;
  String errorMessage = '';

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Total value = cash + long holdings + short P&L
  double get totalPortfolioValue =>
      (userProfile?.cashBalance ?? 0) +
      holdings.fold(0.0, (s, h) => s + h.totalValue) +
      shortPositions.fold(0.0, (s, p) => s + p.gainLoss);

  double get totalGainLoss => totalPortfolioValue - UserProfile.startingBalance;
  double get totalGainLossPercent =>
      (totalGainLoss / UserProfile.startingBalance) * 100;

  // ─────────────────────────────────────────
  // LOAD
  // ─────────────────────────────────────────
  Future<void> loadPortfolio() async {
    if (uid.isEmpty) return;
    isLoading = true;
    notifyListeners();

    final profileDoc = await _db.collection('users').doc(uid).get();
    if (profileDoc.exists) {
      userProfile = UserProfile.fromMap(profileDoc.data()!, uid);
    }

    final holdingsSnap =
        await _db.collection('users').doc(uid).collection('holdings').get();
    holdings = holdingsSnap.docs
        .map((d) => PortfolioHolding.fromMap(d.data()))
        .toList();

    final shortsSnap =
        await _db.collection('users').doc(uid).collection('shorts').get();
    shortPositions =
        shortsSnap.docs.map((d) => ShortPosition.fromMap(d.data())).toList();

    final tradesSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('trades')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    trades = tradesSnap.docs.map((d) => Trade.fromMap(d.data(), d.id)).toList();

    isLoading = false;
    notifyListeners();
    await refreshPrices();
    await loadWatchlist();
    await loadTrending();
  }

  // ─────────────────────────────────────────
  // WATCHLIST
  // ─────────────────────────────────────────
  Future<void> loadWatchlist() async {
    if (uid.isEmpty) return;
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .orderBy('addedAt', descending: true)
          .get();
      watchlist = snap.docs.map((d) {
        final data = d.data();
        data['docId'] = d.id;
        return data;
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> removeFromWatchlist(String docId) async {
    if (uid.isEmpty) return;
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(docId)
          .delete();
      watchlist.removeWhere((w) => w['docId'] == docId);
      notifyListeners();
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // TRENDING
  // ─────────────────────────────────────────
  Future<void> loadTrending() async {
    isTrendingLoading = true;
    notifyListeners();

    final results = <TrendingStock>[];
    for (int i = 0; i < _trendingSymbols.length; i++) {
      final entry = _trendingSymbols[i];
      final q = await fetchQuote(entry['symbol']!);
      if (q != null) {
        results.add(TrendingStock.fromFinnhub(
          rank: i + 1,
          symbol: entry['symbol']!,
          companyName: entry['name']!,
          price: q.currentPrice,
          changePercent: q.changePercent,
        ));
      }
      // Small delay to respect Finnhub free-tier rate limit
      await Future.delayed(const Duration(milliseconds: 120));
    }

    // Sort biggest movers first, then re-rank
    results
        .sort((a, b) => b.changePercent.abs().compareTo(a.changePercent.abs()));
    for (int i = 0; i < results.length; i++) {
      results[i] = TrendingStock(
        rank: i + 1,
        symbol: results[i].symbol,
        companyName: results[i].companyName,
        price: results[i].price,
        changePercent: results[i].changePercent,
        isUp: results[i].isUp,
        sparkline: results[i].sparkline,
      );
    }

    trendingStocks = results;
    isTrendingLoading = false;
    notifyListeners();
  }

  // ─────────────────────────────────────────
  // STOCK API (delegated to IStockService)
  // ─────────────────────────────────────────
  Future<StockQuote?> fetchQuote(String symbol) =>
      _stockService.fetchQuote(symbol);

  Future<List<StockResult>> searchStocks(String query) =>
      _stockService.searchStocks(query);

  Future<Map<String, dynamic>?> fetchCompanyProfile(String symbol) =>
      _stockService.fetchCompanyProfile(symbol);

  Future<Map<String, dynamic>?> fetchBasicFinancials(String symbol) =>
      _stockService.fetchBasicFinancials(symbol);

  Future<List<double>?> fetchCandles(
          String symbol, String resolution, int from, int to) =>
      _stockService.fetchCandles(symbol, resolution, from, to);

  Future<void> refreshPrices() async {
    for (int i = 0; i < holdings.length; i++) {
      final q = await fetchQuote(holdings[i].symbol);
      if (q != null) holdings[i].currentPrice = q.currentPrice;
    }
    // Also update open short positions
    for (int i = 0; i < shortPositions.length; i++) {
      final q = await fetchQuote(shortPositions[i].symbol);
      if (q != null) shortPositions[i].currentPrice = q.currentPrice;
    }
    _syncTotalValue();
    notifyListeners();
  }

  // ─────────────────────────────────────────
  // BUY (long position)
  // ─────────────────────────────────────────
  Future<bool> buyStock(
      String symbol, String companyName, double shares, double price) async {
    final cost = shares * price;
    if ((userProfile?.cashBalance ?? 0) < cost) {
      errorMessage = 'Insufficient funds';
      notifyListeners();
      return false;
    }
    errorMessage = '';
    userProfile!.cashBalance -= cost;

    final idx = holdings.indexWhere((h) => h.symbol == symbol);
    if (idx >= 0) {
      final e = holdings[idx];
      final newShares = e.shares + shares;
      holdings[idx].shares = newShares;
      holdings[idx].averageCost =
          ((e.shares * e.averageCost) + cost) / newShares;
      holdings[idx].currentPrice = price;
    } else {
      holdings.add(PortfolioHolding(
        symbol: symbol,
        companyName: companyName,
        shares: shares,
        averageCost: price,
        currentPrice: price,
      ));
    }

    final trade = Trade(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      companyName: companyName,
      type: TradeType.buy,
      shares: shares,
      pricePerShare: price,
      totalAmount: cost,
      timestamp: DateTime.now(),
    );
    trades.insert(0, trade);
    _syncTotalValue();
    notifyListeners();
    await _persistLong(trade);
    return true;
  }

  // ─────────────────────────────────────────
  // SELL (close long position)
  // ─────────────────────────────────────────
  Future<bool> sellStock(String symbol, double shares, double price) async {
    final idx = holdings.indexWhere((h) => h.symbol == symbol);
    if (idx < 0 || holdings[idx].shares < shares) {
      errorMessage = 'Not enough shares';
      notifyListeners();
      return false;
    }
    errorMessage = '';
    final gain = shares * price;
    final companyName = holdings[idx].companyName;
    userProfile!.cashBalance += gain;
    holdings[idx].shares -= shares;
    if (holdings[idx].shares <= 0) holdings.removeAt(idx);

    final trade = Trade(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      companyName: companyName,
      type: TradeType.sell,
      shares: shares,
      pricePerShare: price,
      totalAmount: gain,
      timestamp: DateTime.now(),
    );
    trades.insert(0, trade);
    _syncTotalValue();
    notifyListeners();
    await _persistLong(trade);
    return true;
  }

  // ─────────────────────────────────────────
  // SHORT — bet stock goes DOWN
  // Player receives cash now and owes shares back later.
  // Profit = price dropped below priceAtShort.
  // ─────────────────────────────────────────
  Future<bool> shortStock(
      String symbol, String companyName, double shares, double price) async {
    errorMessage = '';
    final proceeds = shares * price;
    // Credit cash immediately ("sold borrowed shares")
    userProfile!.cashBalance += proceeds;

    final idx = shortPositions.indexWhere((p) => p.symbol == symbol);
    if (idx >= 0) {
      // Average into existing short
      final existing = shortPositions[idx];
      final totalShares = existing.shares + shares;
      shortPositions[idx].priceAtShort =
          ((existing.shares * existing.priceAtShort) + proceeds) / totalShares;
      shortPositions[idx].shares = totalShares;
      shortPositions[idx].currentPrice = price;
    } else {
      shortPositions.add(ShortPosition(
        symbol: symbol,
        companyName: companyName,
        shares: shares,
        priceAtShort: price,
        currentPrice: price,
      ));
    }

    final trade = Trade(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      companyName: companyName,
      type: TradeType.short,
      shares: shares,
      pricePerShare: price,
      totalAmount: proceeds,
      timestamp: DateTime.now(),
    );
    trades.insert(0, trade);
    _syncTotalValue();
    notifyListeners();
    await _persistShort(trade);
    return true;
  }

  // ─────────────────────────────────────────
  // COVER — buy back shares to close a short
  // ─────────────────────────────────────────
  Future<bool> coverShort(String symbol, double shares, double price) async {
    final idx = shortPositions.indexWhere((p) => p.symbol == symbol);
    if (idx < 0 || shortPositions[idx].shares < shares) {
      errorMessage = 'No short position to cover';
      notifyListeners();
      return false;
    }
    final cost = shares * price;
    if ((userProfile?.cashBalance ?? 0) < cost) {
      errorMessage = 'Insufficient funds to cover';
      notifyListeners();
      return false;
    }
    errorMessage = '';
    final companyName = shortPositions[idx].companyName;
    userProfile!.cashBalance -= cost;
    shortPositions[idx].shares -= shares;
    if (shortPositions[idx].shares <= 0) shortPositions.removeAt(idx);

    final trade = Trade(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      companyName: companyName,
      type: TradeType.coverShort,
      shares: shares,
      pricePerShare: price,
      totalAmount: cost,
      timestamp: DateTime.now(),
    );
    trades.insert(0, trade);
    _syncTotalValue();
    notifyListeners();
    await _persistShort(trade);
    return true;
  }

  // Update a single short's current price (called during price refresh)
  void updateShortPrice(String symbol, double newPrice) {
    final idx = shortPositions.indexWhere((p) => p.symbol == symbol);
    if (idx >= 0) {
      shortPositions[idx].currentPrice = newPrice;
      _syncTotalValue();
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────
  // INTERNAL HELPERS
  // ─────────────────────────────────────────
  void _syncTotalValue() {
    userProfile?.totalValue = totalPortfolioValue;
    if (uid.isNotEmpty) {
      _db
          .collection('users')
          .doc(uid)
          .update({'totalValue': totalPortfolioValue});
    }
  }

  Future<void> _persistLong(Trade trade) async {
    if (uid.isEmpty) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('trades')
        .doc(trade.id)
        .set(trade.toMap());
    final batch = _db.batch();
    for (final h in holdings) {
      batch.set(
        _db.collection('users').doc(uid).collection('holdings').doc(h.symbol),
        h.toMap(),
      );
    }
    batch.update(_db.collection('users').doc(uid), {
      'cashBalance': userProfile?.cashBalance,
      'totalValue': totalPortfolioValue,
    });
    await batch.commit();
  }

  Future<void> _persistShort(Trade trade) async {
    if (uid.isEmpty) return;
    await _db
        .collection('users')
        .doc(uid)
        .collection('trades')
        .doc(trade.id)
        .set(trade.toMap());

    final batch = _db.batch();
    // Write all currently open short positions
    for (final p in shortPositions) {
      batch.set(
        _db.collection('users').doc(uid).collection('shorts').doc(p.symbol),
        p.toMap(),
      );
    }
    // Delete any covered positions that no longer exist locally
    if (trade.type == TradeType.coverShort) {
      final stillOpen = shortPositions.map((p) => p.symbol).toSet();
      final existing =
          await _db.collection('users').doc(uid).collection('shorts').get();
      for (final doc in existing.docs) {
        if (!stillOpen.contains(doc.id)) batch.delete(doc.reference);
      }
    }
    batch.update(_db.collection('users').doc(uid), {
      'cashBalance': userProfile?.cashBalance,
      'totalValue': totalPortfolioValue,
    });
    await batch.commit();
  }
}
