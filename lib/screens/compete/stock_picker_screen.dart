import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────
// STOCK PICKER SCREEN
// ─────────────────────────────────────────
class StockPickerScreen extends StatefulWidget {
  final Challenge challenge;
  const StockPickerScreen({super.key, required this.challenge});
  @override
  State<StockPickerScreen> createState() => _StockPickerScreenState();
}

class _StockPickerScreenState extends State<StockPickerScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _countdownTimer;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isSubmitting = false;
  int _secondsLeft = 300; // 5 minutes

  // Picked stocks: {symbol, companyName, priceAtPick, sector}
  final List<Map<String, dynamic>> _picks = [];

  static const List<String> _gicsSectors = [
    'Technology',
    'Healthcare',
    'Financials',
    'Consumer Discretionary',
    'Consumer Staples',
    'Energy',
    'Industrials',
    'Materials',
    'Utilities',
    'Real Estate',
    'Communication Services',
  ];

  // Popular stocks for auto-pick fallback
  static const List<Map<String, String>> _popularStocks = [
    {'symbol': 'AAPL', 'name': 'Apple Inc', 'sector': 'Technology'},
    {'symbol': 'MSFT', 'name': 'Microsoft Corp', 'sector': 'Technology'},
    {'symbol': 'GOOGL', 'name': 'Alphabet Inc', 'sector': 'Technology'},
    {'symbol': 'AMZN', 'name': 'Amazon.com Inc', 'sector': 'Consumer Discretionary'},
    {'symbol': 'NVDA', 'name': 'NVIDIA Corp', 'sector': 'Technology'},
    {'symbol': 'META', 'name': 'Meta Platforms Inc', 'sector': 'Technology'},
    {'symbol': 'TSLA', 'name': 'Tesla Inc', 'sector': 'Consumer Discretionary'},
    {'symbol': 'JPM', 'name': 'JPMorgan Chase', 'sector': 'Financials'},
    {'symbol': 'V', 'name': 'Visa Inc', 'sector': 'Financials'},
    {'symbol': 'JNJ', 'name': 'Johnson & Johnson', 'sector': 'Healthcare'},
    {'symbol': 'UNH', 'name': 'UnitedHealth Group', 'sector': 'Healthcare'},
    {'symbol': 'XOM', 'name': 'Exxon Mobil Corp', 'sector': 'Energy'},
    {'symbol': 'PG', 'name': 'Procter & Gamble', 'sector': 'Consumer Staples'},
    {'symbol': 'BA', 'name': 'Boeing Co', 'sector': 'Industrials'},
    {'symbol': 'LIN', 'name': 'Linde plc', 'sector': 'Materials'},
    {'symbol': 'NEE', 'name': 'NextEra Energy', 'sector': 'Utilities'},
    {'symbol': 'AMT', 'name': 'American Tower', 'sector': 'Real Estate'},
    {'symbol': 'T', 'name': 'AT&T Inc', 'sector': 'Communication Services'},
    {'symbol': 'KO', 'name': 'Coca-Cola Co', 'sector': 'Consumer Staples'},
    {'symbol': 'CAT', 'name': 'Caterpillar Inc', 'sector': 'Industrials'},
    {'symbol': 'GS', 'name': 'Goldman Sachs', 'sector': 'Financials'},
  ];

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _autoPickAndSubmit();
      }
    });
  }

  String get _timerDisplay {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _timerColor {
    if (_secondsLeft <= 30) return AppTheme.red;
    if (_secondsLeft <= 60) return AppTheme.gold;
    return AppTheme.textMuted;
  }

  int get _maxPicks => widget.challenge.rosterSize;
  bool get _isSectorMode => widget.challenge.isSectorMode;
  Set<String> get _pickedSectors =>
      _picks.map((p) => p['sector'] as String).toSet();

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final prov = context.read<PortfolioProvider>();
      final results = await prov.searchStocks(query);
      if (!mounted) return;

      // Fetch prices for top 10
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
            'sector': _guessSector(r.symbol),
          };
        } catch (_) {
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': 0.0,
            'change': 0.0,
            'changePct': 0.0,
            'sector': 'Other',
          };
        }
      }));

      if (!mounted) return;
      setState(() {
        _searchResults = withPrices;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  void _addPick(Map<String, dynamic> stock) {
    if (_picks.length >= _maxPicks) return;
    if (_picks.any((p) => p['symbol'] == stock['symbol'])) return;

    final sector = stock['sector'] as String;
    if (_isSectorMode && _pickedSectors.contains(sector) && sector != 'Other') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Already picked from $sector sector'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    _showDirectionDialog(stock, sector);
  }

  void _showDirectionDialog(Map<String, dynamic> stock, String sector) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(stock['symbol'] ?? stock['name'] ?? '',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Courier',
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(stock['name'] ?? '',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _commitPick(stock, sector, 'long');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.green.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(children: [
                    Text('▲', style: TextStyle(fontSize: 22, color: AppTheme.green)),
                    SizedBox(height: 4),
                    Text('LONG',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Courier',
                            color: AppTheme.green)),
                    SizedBox(height: 2),
                    Text('Bet it goes UP',
                        style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _commitPick(stock, sector, 'short');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.red.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(children: [
                    Text('▼', style: TextStyle(fontSize: 22, color: AppTheme.red)),
                    SizedBox(height: 4),
                    Text('SHORT',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Courier',
                            color: AppTheme.red)),
                    SizedBox(height: 2),
                    Text('Bet it goes DOWN',
                        style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  void _commitPick(Map<String, dynamic> stock, String sector, String direction) {
    if (_picks.length >= _maxPicks) return;
    if (_picks.any((p) => p['symbol'] == stock['symbol'])) return;
    setState(() {
      _picks.add({
        'symbol': stock['symbol'],
        'companyName': stock['name'],
        'priceAtPick': stock['price'],
        'sector': sector,
        'direction': direction,
      });
    });
  }

  void _removePick(int index) {
    setState(() => _picks.removeAt(index));
  }

  Future<void> _autoPickAndSubmit() async {
    if (_isSubmitting) return;

    // Fill remaining slots with random popular stocks
    final rng = Random();
    final available = List<Map<String, String>>.from(_popularStocks);
    // Remove already-picked symbols
    available.removeWhere(
        (s) => _picks.any((p) => p['symbol'] == s['symbol']));

    final prov = context.read<PortfolioProvider>();

    while (_picks.length < _maxPicks && available.isNotEmpty) {
      final idx = rng.nextInt(available.length);
      final stock = available.removeAt(idx);
      final sector = stock['sector'] ?? 'Other';

      // In sector mode, skip if sector already taken
      if (_isSectorMode && _pickedSectors.contains(sector) && sector != 'Other') {
        continue;
      }

      // Try to get current price
      double price = 0.0;
      try {
        final q = await prov.fetchQuote(stock['symbol']!);
        price = q?.currentPrice ?? 0.0;
      } catch (_) {}

      _picks.add({
        'symbol': stock['symbol'],
        'companyName': stock['name'],
        'priceAtPick': price,
        'sector': sector,
        'direction': 'long',
      });
    }

    if (mounted) setState(() {});
    await _submitPicks();
  }

  Future<void> _submitPicks() async {
    print('[StockPicker] _submitPicks called, picks count: ${_picks.length}, maxPicks: $_maxPicks');
    if (_picks.length < _maxPicks) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick $_maxPicks stocks to continue'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    _countdownTimer?.cancel();
    final ranked = context.read<RankedProvider>();
    print('[StockPicker] Calling ranked.submitPicks for challenge: ${widget.challenge.id}');
    print('[StockPicker] Picks: ${_picks.map((p) => p['symbol']).toList()}');
    final err = await ranked.submitPicks(widget.challenge.id, _picks);
    print('[StockPicker] submitPicks returned, err: $err');
    if (!mounted) return;

    if (err != null) {
      print('[StockPicker] Error from submitPicks: $err');
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    print('[StockPicker] Success — navigating back');
    // Pop back to the Compete screen (pop all pushed routes)
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Picks locked in!'),
      backgroundColor: AppTheme.green,
    ));
  }

  String _guessSector(String sym) {
    const map = {
      'Technology': [
        'NVDA', 'AAPL', 'MSFT', 'META', 'GOOGL', 'AMD', 'PLTR', 'SHOP',
        'DDOG', 'CRWD', 'SNAP', 'RBLX', 'CRM', 'ORCL', 'INTC', 'QCOM',
        'AVGO', 'TSM', 'MU', 'ADBE',
      ],
      'Financials': [
        'JPM', 'BAC', 'GS', 'V', 'MA', 'HOOD', 'SOFI', 'PYPL', 'SPY',
        'BRK.B', 'WFC', 'C', 'AXP', 'SCHW',
      ],
      'Consumer Discretionary': [
        'AMZN', 'TSLA', 'RIVN', 'NIO', 'F', 'GM', 'NFLX', 'DIS', 'UBER',
        'SPOT', 'BABA', 'ABNB', 'SBUX', 'NKE', 'MCD',
      ],
      'Consumer Staples': ['WMT', 'COST', 'PG', 'KO', 'PEP', 'CL', 'MDLZ'],
      'Energy': ['XOM', 'CVX', 'SLB', 'COP', 'EOG', 'OXY', 'MPC'],
      'Healthcare': [
        'JNJ', 'UNH', 'PFE', 'ABBV', 'MRK', 'LLY', 'TMO', 'ABT', 'MRNA',
      ],
      'Communication Services': ['GOOG', 'T', 'VZ', 'TMUS', 'CMCSA', 'NFLX'],
      'Industrials': ['BA', 'CAT', 'HON', 'UPS', 'GE', 'RTX', 'LMT', 'DE'],
      'Materials': ['LIN', 'APD', 'ECL', 'SHW', 'NEM', 'FCX', 'DOW'],
      'Utilities': ['NEE', 'DUK', 'SO', 'D', 'AEP', 'EXC', 'SRE'],
      'Real Estate': ['AMT', 'PLD', 'CCI', 'SPG', 'EQIX', 'O', 'PSA'],
    };
    for (final entry in map.entries) {
      if (entry.value.contains(sym)) return entry.key;
    }
    return 'Other';
  }

  static const Map<String, Color> _sectorColors = {
    'Technology': Color(0xFF4FC3F7),
    'Healthcare': Color(0xFF81C784),
    'Financials': Color(0xFFFFD54F),
    'Consumer Discretionary': Color(0xFFFF8A65),
    'Consumer Staples': Color(0xFFA5D6A7),
    'Energy': Color(0xFFE57373),
    'Industrials': Color(0xFF90A4AE),
    'Materials': Color(0xFFCE93D8),
    'Utilities': Color(0xFF4DB6AC),
    'Real Estate': Color(0xFFFFAB91),
    'Communication Services': Color(0xFF7986CB),
    'Other': Color(0xFF78909C),
  };

  static const List<Map<String, String>> _displayPopular = [
    {'symbol': 'AAPL', 'name': 'Apple', 'sector': 'Technology'},
    {'symbol': 'MSFT', 'name': 'Microsoft', 'sector': 'Technology'},
    {'symbol': 'GOOGL', 'name': 'Alphabet', 'sector': 'Technology'},
    {'symbol': 'AMZN', 'name': 'Amazon', 'sector': 'Consumer Discretionary'},
    {'symbol': 'TSLA', 'name': 'Tesla', 'sector': 'Consumer Discretionary'},
    {'symbol': 'NVDA', 'name': 'NVIDIA', 'sector': 'Technology'},
    {'symbol': 'META', 'name': 'Meta Platforms', 'sector': 'Technology'},
    {'symbol': 'NFLX', 'name': 'Netflix', 'sector': 'Consumer Discretionary'},
    {'symbol': 'DIS', 'name': 'Disney', 'sector': 'Consumer Discretionary'},
    {'symbol': 'AMD', 'name': 'AMD', 'sector': 'Technology'},
    {'symbol': 'BA', 'name': 'Boeing', 'sector': 'Industrials'},
    {'symbol': 'JPM', 'name': 'JPMorgan Chase', 'sector': 'Financials'},
  ];

  Future<void> _onPopularTap(Map<String, String> stock) async {
    if (_picks.length >= _maxPicks) return;
    if (_picks.any((p) => p['symbol'] == stock['symbol'])) return;

    final prov = context.read<PortfolioProvider>();
    double price = 0.0;
    try {
      final q = await prov.fetchQuote(stock['symbol']!);
      price = q?.currentPrice ?? 0.0;
    } catch (_) {}

    _addPick({
      'symbol': stock['symbol'],
      'name': stock['name'],
      'price': price,
      'sector': stock['sector'] ?? 'Other',
    });
  }

  Widget _buildPopularStocks() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('POPULAR STOCKS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMuted,
                fontFamily: 'Courier',
                letterSpacing: 1.2,
              )),
        ),
        ..._displayPopular.map((stock) {
          final alreadyPicked =
              _picks.any((p) => p['symbol'] == stock['symbol']);
          final sector = stock['sector'] ?? 'Other';
          final sectorTaken = _isSectorMode &&
              _pickedSectors.contains(sector) &&
              sector != 'Other' &&
              !alreadyPicked;
          final disabled =
              alreadyPicked || _picks.length >= _maxPicks || sectorTaken;
          final c = _sectorColors[sector] ?? AppTheme.textMuted;

          return GestureDetector(
            onTap: disabled ? null : () => _onPopularTap(stock),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Opacity(
                opacity: disabled ? 0.4 : 1.0,
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.1),
                      border:
                          Border.all(color: c.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(stock['symbol']!,
                        style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: c)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(stock['name']!,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (alreadyPicked)
                    const Icon(Icons.check_circle,
                        size: 18, color: AppTheme.green)
                  else if (sectorTaken)
                    const Icon(Icons.block,
                        size: 18, color: AppTheme.textMuted)
                  else
                    const Icon(Icons.add_circle_outline,
                        size: 18, color: AppTheme.green),
                ]),
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pick $_maxPicks ${_isSectorMode ? 'Sectors' : 'Stocks'}'),
        actions: [
          // Countdown timer
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _timerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _timerColor.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer, size: 14, color: _timerColor),
                  const SizedBox(width: 4),
                  Text(_timerDisplay,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.w800,
                        color: _timerColor,
                      )),
                ]),
              ),
            ),
          ),
          // Pick counter
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text('${_picks.length}/$_maxPicks',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w800,
                    color: _picks.length == _maxPicks
                        ? AppTheme.green
                        : AppTheme.textMuted,
                  )),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Timer warning bar
          if (_secondsLeft <= 60)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: (_secondsLeft <= 30 ? AppTheme.red : AppTheme.gold)
                  .withValues(alpha: 0.15),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16,
                    color: _secondsLeft <= 30 ? AppTheme.red : AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  _secondsLeft <= 30
                      ? 'Hurry! Auto-picking in $_secondsLeft seconds...'
                      : 'Less than 1 minute remaining!',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    color: _secondsLeft <= 30 ? AppTheme.red : AppTheme.gold,
                  ),
                ),
              ]),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search stocks...',
                  hintStyle:
                      TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: AppTheme.textMuted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),

          // Sector hints for sector mode
          if (_isSectorMode)
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _gicsSectors.map((s) {
                  final picked = _pickedSectors.contains(s);
                  final c = _sectorColors[s] ?? AppTheme.textMuted;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: picked
                          ? c.withValues(alpha: 0.2)
                          : AppTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: picked
                              ? c.withValues(alpha: 0.4)
                              : AppTheme.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (picked)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.check, size: 12, color: AppTheme.green),
                        ),
                      Text(s,
                          style: TextStyle(
                              fontSize: 9,
                              color: picked ? c : AppTheme.textMuted,
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.w600)),
                    ]),
                  );
                }).toList(),
              ),
            ),

          // My picks chips
          if (_picks.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _picks.length,
                itemBuilder: (_, i) {
                  final pick = _picks[i];
                  final isShort = pick['direction'] == 'short';
                  final dirColor = isShort ? AppTheme.red : AppTheme.green;
                  final c = _sectorColors[pick['sector']] ?? AppTheme.textMuted;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (isShort ? AppTheme.red : c).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: (isShort ? AppTheme.red : c).withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(isShort ? '▼' : '▲',
                          style: TextStyle(fontSize: 12, color: dirColor)),
                      const SizedBox(width: 4),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(pick['symbol'],
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Courier',
                                    color: isShort ? AppTheme.red : c)),
                            if (_isSectorMode)
                              Text(pick['sector'],
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: c.withValues(alpha: 0.7),
                                      fontFamily: 'Courier')),
                          ]),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _removePick(i),
                        child: const Icon(Icons.close,
                            size: 14,
                            color: AppTheme.textMuted),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 4),

          // Search results / Popular stocks
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.green, strokeWidth: 2))
                : _searchResults.isEmpty && _searchCtrl.text.isNotEmpty
                    ? const Center(
                        child: Text(
                          'No results found',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                        ),
                      )
                : _searchResults.isEmpty && _searchCtrl.text.isEmpty
                    ? _buildPopularStocks()
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (_, i) {
                          final stock = _searchResults[i];
                          final alreadyPicked = _picks
                              .any((p) => p['symbol'] == stock['symbol']);
                          final sector = stock['sector'] as String;
                          final sectorTaken = _isSectorMode &&
                              _pickedSectors.contains(sector) &&
                              sector != 'Other' &&
                              !alreadyPicked;
                          final disabled =
                              alreadyPicked || _picks.length >= _maxPicks || sectorTaken;
                          final c =
                              _sectorColors[sector] ?? AppTheme.textMuted;

                          return GestureDetector(
                            onTap: disabled ? null : () => _addPick(stock),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: AppTheme.border)),
                              ),
                              child: Opacity(
                                opacity: disabled ? 0.4 : 1.0,
                                child: Row(children: [
                                  // Sector badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: c.withValues(alpha: 0.1),
                                      border: Border.all(
                                          color:
                                              c.withValues(alpha: 0.3)),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(stock['symbol'],
                                        style: TextStyle(
                                            fontFamily: 'Courier',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: c)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(stock['name'],
                                              style: const TextStyle(
                                                  fontSize: 12),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          if (_isSectorMode)
                                            Text(sector,
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    color: c,
                                                    fontFamily: 'Courier')),
                                        ]),
                                  ),
                                  Text(
                                      AppTheme.currency(
                                          stock['price'] as double),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'Courier',
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  if (alreadyPicked)
                                    const Icon(Icons.check_circle,
                                        size: 18, color: AppTheme.green)
                                  else if (sectorTaken)
                                    const Icon(Icons.block,
                                        size: 18,
                                        color: AppTheme.textMuted)
                                  else
                                    const Icon(Icons.add_circle_outline,
                                        size: 18, color: AppTheme.green),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Submit button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _picks.length == _maxPicks && !_isSubmitting
                        ? _submitPicks
                        : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        _picks.length == _maxPicks
                            ? 'Lock In Picks'
                            : '${_picks.length}/$_maxPicks Picked',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
