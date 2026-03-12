import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/portfolio_provider.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────
// MATCHMAKING STOCK PICKER SCREEN
// ─────────────────────────────────────────
class MmStockPickerScreen extends StatefulWidget {
  final String matchId;
  final int rosterSize; // 3, 5, or 11
  const MmStockPickerScreen({
    super.key,
    required this.matchId,
    required this.rosterSize,
  });
  @override
  State<MmStockPickerScreen> createState() => _MmStockPickerScreenState();
}

class _MmStockPickerScreenState extends State<MmStockPickerScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _countdownTimer;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isSubmitting = false;
  int _secondsLeft = 300; // 5 minutes

  // Picked stocks: {symbol, companyName, priceAtPick, sector}
  final List<Map<String, dynamic>> _picks = [];

  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _isSectorMode => widget.rosterSize == 11;

  static const List<String> _gicsSectors = [
    'Technology', 'Healthcare', 'Financials', 'Consumer Discretionary',
    'Consumer Staples', 'Energy', 'Industrials', 'Materials',
    'Utilities', 'Real Estate', 'Communication Services',
  ];

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

  // ── Timer ──────────────────────────────

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        if (!_isSubmitting) _forfeitMatch();
      }
    });
  }

  Future<void> _forfeitMatch() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      // Read the challenge doc to find opponent
      final challengeDoc =
          await _db.collection('challenges').doc(widget.matchId).get();
      if (!challengeDoc.exists) {
        debugPrint('Forfeit: challenge doc not found');
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      final data = challengeDoc.data()!;
      final isChallenger = data['challengerUID'] == _uid;
      final opponentUID =
          isChallenger ? data['opponentUID'] as String : data['challengerUID'] as String;

      // Mark challenge as complete with forfeit
      await _db.collection('challenges').doc(widget.matchId).update({
        'status': 'complete',
        'winnerId': opponentUID,
        'forfeitedBy': _uid,
        'completedAt': DateTime.now().toIso8601String(),
      });

      // Update win/loss records
      final batch = _db.batch();
      final opponentRef = _db.collection('rankedProfiles').doc(opponentUID);
      final myRef = _db.collection('rankedProfiles').doc(_uid);
      final opponentDoc = await opponentRef.get();
      final myDoc = await myRef.get();

      if (opponentDoc.exists) {
        final wins = (opponentDoc.data()?['wins'] ?? 0) as int;
        batch.update(opponentRef, {'wins': wins + 1});
      }
      if (myDoc.exists) {
        final losses = (myDoc.data()?['losses'] ?? 0) as int;
        batch.update(myRef, {'losses': losses + 1});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Forfeit error: $e');
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Time expired! You forfeited this match.'),
      backgroundColor: AppTheme.red,
      duration: Duration(seconds: 3),
    ));

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Match?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: const Text(
            'This will forfeit the match and count as a loss.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep Playing',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // close dialog
              _countdownTimer?.cancel();
              setState(() => _isSubmitting = true);

              // Forfeit via direct Firestore update
              try {
                final challengeDoc =
                    await _db.collection('challenges').doc(widget.matchId).get();
                if (challengeDoc.exists) {
                  final data = challengeDoc.data()!;
                  final isChallenger = data['challengerUID'] == _uid;
                  final opponentUID = isChallenger
                      ? data['opponentUID'] as String
                      : data['challengerUID'] as String;

                  await _db
                      .collection('challenges')
                      .doc(widget.matchId)
                      .update({
                    'status': 'complete',
                    'winnerId': opponentUID,
                    'forfeitedBy': _uid,
                    'completedAt': DateTime.now().toIso8601String(),
                  });

                  final batch = _db.batch();
                  final opponentRef =
                      _db.collection('rankedProfiles').doc(opponentUID);
                  final myRef = _db.collection('rankedProfiles').doc(_uid);
                  final opponentDoc = await opponentRef.get();
                  final myDoc = await myRef.get();
                  if (opponentDoc.exists) {
                    final wins = (opponentDoc.data()?['wins'] ?? 0) as int;
                    batch.update(opponentRef, {'wins': wins + 1});
                  }
                  if (myDoc.exists) {
                    final losses = (myDoc.data()?['losses'] ?? 0) as int;
                    batch.update(myRef, {'losses': losses + 1});
                  }
                  await batch.commit();
                }
              } catch (e) {
                debugPrint('Cancel match error: $e');
              }

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Match cancelled.'),
                backgroundColor: AppTheme.red,
              ));
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Forfeit',
                style: TextStyle(
                    color: AppTheme.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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

  // ── Search ─────────────────────────────

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
            'sector': _guessSector(r.symbol),
          };
        } catch (_) {
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': 0.0, 'change': 0.0, 'changePct': 0.0, 'sector': 'Other',
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

  // ── Pick management ────────────────────

  void _addPick(Map<String, dynamic> stock) {
    if (_picks.length >= widget.rosterSize) return;
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
    if (_picks.length >= widget.rosterSize) return;
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

  // ── Auto-pick ──────────────────────────

  Future<void> _autoPickAndSubmit() async {
    if (_isSubmitting) return;

    final rng = Random();
    final available = List<Map<String, String>>.from(_popularStocks);
    available.removeWhere((s) => _picks.any((p) => p['symbol'] == s['symbol']));

    final prov = context.read<PortfolioProvider>();

    while (_picks.length < widget.rosterSize && available.isNotEmpty) {
      final idx = rng.nextInt(available.length);
      final stock = available.removeAt(idx);
      final sector = stock['sector'] ?? 'Other';

      if (_isSectorMode && _pickedSectors.contains(sector) && sector != 'Other') {
        continue;
      }

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

  // ── Submit picks to Firestore ──────────

  Future<void> _submitPicks() async {
    if (_picks.length < widget.rosterSize) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick ${widget.rosterSize} stocks to continue'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    _countdownTimer?.cancel();

    try {
      final totalCost =
          _picks.fold<double>(0, (s, p) => s + (p['priceAtPick'] as double));

      // Save picks to /matchmaking/{matchId}/picks/{uid}
      await _db
          .collection('matchmaking')
          .doc(widget.matchId)
          .collection('picks')
          .doc(_uid)
          .set({
        'uid': _uid,
        'picks': _picks,
        'totalCost': totalCost,
        'submittedAt': DateTime.now().toIso8601String(),
      });

      // Also update the challenge doc with picks
      final challengeDoc =
          await _db.collection('challenges').doc(widget.matchId).get();
      if (challengeDoc.exists) {
        final data = challengeDoc.data()!;
        final isChallenger = data['challengerUID'] == _uid;
        final picksField =
            isChallenger ? 'challengerPicks' : 'opponentPicks';
        final costField =
            isChallenger ? 'challengerCost' : 'opponentCost';
        final valueField =
            isChallenger ? 'challengerValue' : 'opponentValue';

        final updates = <String, dynamic>{
          picksField: _picks,
          costField: totalCost,
          valueField: totalCost,
        };

        // Check if opponent already submitted picks
        final otherPicks = isChallenger
            ? List.from(data['opponentPicks'] ?? [])
            : List.from(data['challengerPicks'] ?? []);

        if (otherPicks.isNotEmpty) {
          updates['status'] = 'active';
          updates['startDate'] = DateTime.now().toIso8601String();
        }

        await _db
            .collection('challenges')
            .doc(widget.matchId)
            .update(updates);
      }

      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Picks locked in!'),
        backgroundColor: AppTheme.green,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save picks: $e'),
        backgroundColor: AppTheme.red,
      ));
    }
  }

  // ── Sector guessing ────────────────────

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

  // ── Build ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxPicks = widget.rosterSize;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pick $maxPicks ${_isSectorMode ? 'Sectors' : 'Stocks'}'),
        actions: [
          // Cancel match
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppTheme.red),
            tooltip: 'Cancel Match',
            onPressed: _isSubmitting ? null : _showCancelDialog,
          ),
          // Countdown timer
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _timerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: _timerColor.withValues(alpha: 0.3)),
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
              child: Text('${_picks.length}/$maxPicks',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w800,
                    color: _picks.length == maxPicks
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: (_secondsLeft <= 30 ? AppTheme.red : AppTheme.gold)
                  .withValues(alpha: 0.15),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16,
                    color:
                        _secondsLeft <= 30 ? AppTheme.red : AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  _secondsLeft <= 30
                      ? 'Hurry! Auto-picking in $_secondsLeft seconds...'
                      : 'Less than 1 minute remaining!',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    color:
                        _secondsLeft <= 30 ? AppTheme.red : AppTheme.gold,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
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
                          child: Icon(Icons.check,
                              size: 12, color: AppTheme.green),
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

          // Selected picks chips
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
                  final c =
                      _sectorColors[pick['sector']] ?? AppTheme.textMuted;
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
                            size: 14, color: AppTheme.textMuted),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 4),

          // Search results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.green, strokeWidth: 2))
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty
                              ? 'Search for stocks to add to your roster'
                              : 'No results found',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                        ),
                      )
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
                          final disabled = alreadyPicked ||
                              _picks.length >= maxPicks ||
                              sectorTaken;
                          final c =
                              _sectorColors[sector] ?? AppTheme.textMuted;

                          return GestureDetector(
                            onTap:
                                disabled ? null : () => _addPick(stock),
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
                                              overflow: TextOverflow
                                                  .ellipsis),
                                          if (_isSectorMode)
                                            Text(sector,
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    color: c,
                                                    fontFamily:
                                                        'Courier')),
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

          // Lock In Picks button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _picks.length == maxPicks && !_isSubmitting
                    ? _submitPicks
                    : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        _picks.length == maxPicks
                            ? 'Lock In Picks'
                            : '${_picks.length}/$maxPicks Picked',
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
