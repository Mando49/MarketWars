import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/league_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'league_screen.dart';

class DraftRoomScreen extends StatefulWidget {
  final String leagueId;
  final String leagueName;
  final int rosterSize;
  final String draftMode;

  const DraftRoomScreen({
    super.key,
    required this.leagueId,
    required this.leagueName,
    required this.rosterSize,
    required this.draftMode,
  });

  @override
  State<DraftRoomScreen> createState() => _DraftRoomScreenState();
}

class _DraftRoomScreenState extends State<DraftRoomScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _boardScrollCtrl = ScrollController();
  late TabController _tabCtrl;
  Timer? _debounce;

  // Search
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _lastQuery = '';
  String _activeSector = 'All';

  // Timer
  int _timerSecs = 60;
  Timer? _timer;

  // Draft state from Firestore
  List<DraftPick> _picks = [];
  StreamSubscription? _picksSub;
  Map<String, dynamic>? _draftState;
  StreamSubscription? _stateSub;

  // Members
  List<LeagueMember> _members = [];
  List<String> _memberUids = [];

  bool _draftComplete = false;
  double _startingBalance = 10000.0;

  static const _sectors = [
    'All', 'Information Technology', 'Health Care', 'Financials',
    'Consumer Discretionary', 'Communication Services', 'Industrials',
    'Consumer Staples', 'Energy', 'Utilities', 'Real Estate', 'Materials',
  ];
  static const Map<String, Color> _sectorBg = {
    'Information Technology': Color(0xFF0E1F30),
    'Health Care': Color(0xFF0A1E1E),
    'Financials': Color(0xFF201800),
    'Consumer Discretionary': Color(0xFF200A0A),
    'Communication Services': Color(0xFF140A28),
    'Industrials': Color(0xFF141418),
    'Consumer Staples': Color(0xFF0A1E0A),
    'Energy': Color(0xFF0A1E14),
    'Utilities': Color(0xFF0A141E),
    'Real Estate': Color(0xFF1A140A),
    'Materials': Color(0xFF141A0A),
  };
  static const Map<String, Color> _sectorFg = {
    'Information Technology': Color(0xFF4FC3F7),
    'Health Care': Color(0xFF00BFA5),
    'Financials': Color(0xFFFFC947),
    'Consumer Discretionary': Color(0xFFFF6B6B),
    'Communication Services': Color(0xFFB388FF),
    'Industrials': Color(0xFF90A4AE),
    'Consumer Staples': Color(0xFFFF9F43),
    'Energy': Color(0xFF26DE81),
    'Utilities': Color(0xFF4DD0E1),
    'Real Estate': Color(0xFFD4A574),
    'Materials': Color(0xFFAED581),
  };

  String get _uid => context.read<LeagueProvider>().uid;
  int get _totalPicks => _memberUids.length * widget.rosterSize;
  bool get _isUnique => widget.draftMode == 'unique';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadMembers();
    _runSearch('');
  }

  Future<void> _loadMembers() async {
    final db = FirebaseFirestore.instance;
    final leagueDoc = await db.collection('leagues').doc(widget.leagueId).get();
    if (!mounted) return;
    _memberUids = List<String>.from(leagueDoc.data()?['members'] ?? []);
    _startingBalance = (leagueDoc.data()?['startingBalance'] ?? 10000).toDouble();

    final memberSnap = await db
        .collection('leagues')
        .doc(widget.leagueId)
        .collection('members')
        .get();
    _members = memberSnap.docs
        .map((d) => LeagueMember.fromMap(d.data(), d.id))
        .toList();
    _members.sort((a, b) =>
        _memberUids.indexOf(a.id).compareTo(_memberUids.indexOf(b.id)));

    await _initDraftState();
    _subscribeToPicks();
    _subscribeToState();
    _startTimer();
    if (mounted) setState(() {});
  }

  Future<void> _initDraftState() async {
    final db = FirebaseFirestore.instance;
    final stateRef = db
        .collection('leagues')
        .doc(widget.leagueId)
        .collection('draft')
        .doc('state');
    final stateDoc = await stateRef.get();
    if (!stateDoc.exists) {
      // Clear any old picks from previous drafts for this league
      final oldPicks = await stateRef.collection('picks').get();
      for (final doc in oldPicks.docs) {
        await doc.reference.delete();
      }
      await stateRef.set({
        'currentPick': 1,
        'currentRound': 1,
        'isComplete': false,
        'secondsRemaining': 60,
        'totalRounds': widget.rosterSize,
        'pickOrder': List<String>.from(_memberUids),
        'draftMode': widget.draftMode,
      });
    }
  }

  void _subscribeToPicks() {
    final prov = context.read<LeagueProvider>();
    _picksSub = prov.draftPicksStream(widget.leagueId).listen((picks) {
      if (!mounted) return;
      setState(() {
        _picks = picks;
        if (picks.length >= _totalPicks && _totalPicks > 0) {
          _draftComplete = true;
          _timer?.cancel();
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_boardScrollCtrl.hasClients) {
          _boardScrollCtrl.animateTo(
            _boardScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _subscribeToState() {
    final prov = context.read<LeagueProvider>();
    _stateSub = prov.draftStream(widget.leagueId).listen((snap) {
      if (!mounted || !snap.exists) return;
      setState(() {
        _draftState = snap.data() as Map<String, dynamic>?;
        if (_draftState?['isComplete'] == true) {
          _draftComplete = true;
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _boardScrollCtrl.dispose();
    _debounce?.cancel();
    _timer?.cancel();
    _picksSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  // ══════════════════════════════════════
  // TIMER
  // ══════════════════════════════════════
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _draftComplete) return;
      if (_timerSecs > 0) {
        setState(() => _timerSecs--);
      } else {
        _autoPick();
        _resetTimer();
      }
    });
  }

  void _resetTimer() => setState(() => _timerSecs = 60);

  // ══════════════════════════════════════
  // SNAKE DRAFT LOGIC
  // ══════════════════════════════════════
  int _currentTurnIndex() {
    if (_memberUids.isEmpty) return -1;
    final n = _memberUids.length;
    final pickNum = _picks.length;
    final round = pickNum ~/ n;
    final pos = pickNum % n;
    return round % 2 == 0 ? pos : (n - 1 - pos);
  }

  String _currentTurnUid() {
    final idx = _currentTurnIndex();
    if (idx < 0 || idx >= _memberUids.length) return '';
    return _memberUids[idx];
  }

  String _currentTurnName() {
    final uid = _currentTurnUid();
    if (uid == _uid) return 'Your turn!';
    final m = _memberForUid(uid);
    return "${m.username}'s turn";
  }

  int _currentRound() {
    if (_memberUids.isEmpty) return 1;
    return (_picks.length ~/ _memberUids.length) + 1;
  }

  bool _isMyTurn() => _currentTurnUid() == _uid;
  Set<String> get _takenSymbols => _picks.map((p) => p.symbol).toSet();

  bool _isTaken(String symbol) {
    if (!_isUnique) return false;
    return _takenSymbols.contains(symbol);
  }

  List<DraftPick> _picksFor(String uid) =>
      _picks.where((p) => p.pickedByUID == uid).toList();

  LeagueMember _memberForUid(String uid) => _members.firstWhere(
      (m) => m.id == uid,
      orElse: () => LeagueMember(
          id: uid, username: 'Player', leagueId: widget.leagueId,
          wins: 0, losses: 0, totalValue: 10000, cashBalance: 10000,
          seed: 1, isEliminated: false));

  // ══════════════════════════════════════
  // AUTO PICK
  // ══════════════════════════════════════
  Future<void> _autoPick() async {
    // Fetch latest drafted symbols from Firestore to avoid duplicates
    Set<String> taken = _takenSymbols;
    if (_isUnique) {
      final prov = context.read<LeagueProvider>();
      taken = await prov.getDraftedSymbols(widget.leagueId);
    }
    final available = _defaultPool()
        .where((s) => !taken.contains(s['symbol'] as String))
        .toList();
    if (available.isEmpty) return;
    final stock = available[Random().nextInt(available.length)];
    _doMakePick(stock, auto: true);
  }

  Future<void> _doMakePick(Map<String, dynamic> stock, {bool auto = false}) async {
    if (_draftComplete) return;
    final state = _draftState ?? {
      'draftMode': widget.draftMode,
      'currentRound': _currentRound(),
      'currentPick': _picks.length + 1,
      'pickOrder': _memberUids,
      'totalRounds': widget.rosterSize,
    };

    if (auto && !_isMyTurn()) {
      await _autoPickForCurrentPlayer(stock);
      return;
    }

    final prov = context.read<LeagueProvider>();
    final sym = stock['symbol'] as String;
    final err = await prov.makePick(
      widget.leagueId, sym, stock['name'] as String? ?? sym,
      (stock['price'] as num?)?.toDouble() ?? 0.0, state,
    );

    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: AppTheme.red));
      return;
    }

    _resetTimer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auto ? "Time's up! Auto-drafted $sym" : 'You drafted $sym!'),
        backgroundColor: auto ? AppTheme.red : AppTheme.green,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _autoPickForCurrentPlayer(Map<String, dynamic> stock) async {
    final db = FirebaseFirestore.instance;
    final turnUid = _currentTurnUid();
    final member = _memberForUid(turnUid);
    final sym = stock['symbol'] as String;
    final n = _memberUids.length;
    final pickNum = _picks.length + 1;
    final currentRound = (pickNum - 1) ~/ n + 1;

    final pickId = db.collection('x').doc().id;
    await db.collection('leagues').doc(widget.leagueId)
        .collection('draft').doc('state')
        .collection('picks').doc(pickId).set({
      'id': pickId, 'leagueId': widget.leagueId,
      'round': currentRound, 'pickNumber': pickNum,
      'pickedByUID': member.id, 'pickedByUsername': member.username,
      'symbol': sym, 'companyName': stock['name'] as String? ?? sym,
      'priceAtDraft': (stock['price'] as num?)?.toDouble() ?? 0.0,
      'timestamp': DateTime.now(),
    });

    final nextPick = pickNum + 1;
    final nextRound = ((nextPick - 1) ~/ n) + 1;
    final done = nextRound > widget.rosterSize;

    await db.collection('leagues').doc(widget.leagueId)
        .collection('draft').doc('state').set({
      'currentPick': nextPick, 'currentRound': nextRound,
      'isComplete': done, 'secondsRemaining': 60,
    }, SetOptions(merge: true));

    if (done) {
      await db.collection('leagues').doc(widget.leagueId)
          .update({
        'status': 'active',
        'currentWeek': 1,
        'startDate': DateTime.now().toIso8601String(),
        'startingBalance': _startingBalance,
      });
    }

    _resetTimer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("${member.username} ran out of time — auto-drafted $sym"),
        backgroundColor: AppTheme.red, duration: const Duration(seconds: 2),
      ));
    }
  }

  // ══════════════════════════════════════
  // CONFIRM PICK
  // ══════════════════════════════════════
  void _openConfirm(Map<String, dynamic> stock) {
    if (!_isMyTurn()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not your turn!'), backgroundColor: AppTheme.red,
          duration: Duration(seconds: 2)));
      return;
    }
    if (_isTaken(stock['symbol'] as String)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${stock['symbol']} is already drafted!'),
          backgroundColor: AppTheme.red));
      return;
    }
    _showConfirmSheet(stock);
  }

  void _showConfirmSheet(Map<String, dynamic> stock) {
    final sym = stock['symbol'] as String;
    final name = stock['name'] as String;
    final price = (stock['price'] as num).toDouble();
    final pct = (stock['changePct'] as num).toDouble();
    final up = pct >= 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1117),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.border2,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Confirm Draft Pick',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              border: Border.all(color: AppTheme.greenBorder.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppTheme.greenDim,
                    border: Border.all(color: AppTheme.greenBorder),
                    borderRadius: BorderRadius.circular(9)),
                child: Text(sym, style: const TextStyle(fontFamily: 'Courier',
                    fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.green)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(_isUnique ? 'Unique Draft' : 'Open Draft',
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 10,
                        color: AppTheme.textMuted)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(price > 0 ? AppTheme.currency(price) : '—',
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text('${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
                    style: TextStyle(fontFamily: 'Courier', fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: up ? AppTheme.green : AppTheme.red)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: AppTheme.border)),
                child: const Text('Cancel'))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(context); _doMakePick(stock); },
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    backgroundColor: AppTheme.green, foregroundColor: Colors.black),
                child: const Text('Draft It!',
                    style: TextStyle(fontWeight: FontWeight.w800)))),
          ]),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════
  // SEARCH
  // ══════════════════════════════════════
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() { _isSearching = true; _lastQuery = query; });
    final prov = context.read<PortfolioProvider>();
    if (query.trim().isEmpty) {
      if (!mounted) return;
      setState(() { _searchResults = _defaultPool(); _isSearching = false; });
      return;
    }
    try {
      final results = await prov.searchStocks(query);
      if (!mounted || _lastQuery != query) return;
      final withPrices = await Future.wait(results.take(10).map((r) async {
        try {
          final q = await prov.fetchQuote(r.symbol);
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': q?.currentPrice ?? 0.0,
            'changePct': q?.changePercent ?? 0.0,
            'sector': _guessSector(r.symbol),
          };
        } catch (_) {
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': 0.0, 'changePct': 0.0, 'sector': 'Other',
          };
        }
      }));
      if (!mounted) return;
      setState(() { _searchResults = withPrices; _isSearching = false; });
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  List<Map<String, dynamic>> _defaultPool() => const [
    {'symbol': 'NVDA', 'name': 'NVIDIA Corp.', 'price': 875.40, 'changePct': 3.21, 'sector': 'Information Technology'},
    {'symbol': 'AAPL', 'name': 'Apple Inc.', 'price': 189.30, 'changePct': 1.42, 'sector': 'Information Technology'},
    {'symbol': 'MSFT', 'name': 'Microsoft Corp.', 'price': 415.20, 'changePct': 0.83, 'sector': 'Information Technology'},
    {'symbol': 'AMD', 'name': 'Adv. Micro Devices', 'price': 178.90, 'changePct': 2.88, 'sector': 'Information Technology'},
    {'symbol': 'PLTR', 'name': 'Palantir Technologies', 'price': 24.82, 'changePct': 5.14, 'sector': 'Information Technology'},
    {'symbol': 'GOOGL', 'name': 'Alphabet Inc.', 'price': 172.30, 'changePct': -0.42, 'sector': 'Communication Services'},
    {'symbol': 'META', 'name': 'Meta Platforms', 'price': 519.80, 'changePct': 1.95, 'sector': 'Communication Services'},
    {'symbol': 'NFLX', 'name': 'Netflix Inc.', 'price': 628.50, 'changePct': 1.10, 'sector': 'Communication Services'},
    {'symbol': 'AMZN', 'name': 'Amazon.com', 'price': 198.45, 'changePct': 0.55, 'sector': 'Consumer Discretionary'},
    {'symbol': 'TSLA', 'name': 'Tesla Inc.', 'price': 248.10, 'changePct': -2.31, 'sector': 'Consumer Discretionary'},
    {'symbol': 'RIVN', 'name': 'Rivian Automotive', 'price': 11.42, 'changePct': -5.80, 'sector': 'Consumer Discretionary'},
    {'symbol': 'JPM', 'name': 'JPMorgan Chase', 'price': 196.50, 'changePct': 0.35, 'sector': 'Financials'},
    {'symbol': 'GS', 'name': 'Goldman Sachs', 'price': 478.20, 'changePct': 0.92, 'sector': 'Financials'},
    {'symbol': 'V', 'name': 'Visa Inc.', 'price': 282.40, 'changePct': 0.45, 'sector': 'Financials'},
    {'symbol': 'UNH', 'name': 'UnitedHealth Group', 'price': 524.80, 'changePct': -0.32, 'sector': 'Health Care'},
    {'symbol': 'JNJ', 'name': 'Johnson & Johnson', 'price': 158.90, 'changePct': 0.18, 'sector': 'Health Care'},
    {'symbol': 'LLY', 'name': 'Eli Lilly', 'price': 782.60, 'changePct': 2.45, 'sector': 'Health Care'},
    {'symbol': 'XOM', 'name': 'Exxon Mobil', 'price': 113.20, 'changePct': -0.85, 'sector': 'Energy'},
    {'symbol': 'CVX', 'name': 'Chevron Corp.', 'price': 157.30, 'changePct': -0.62, 'sector': 'Energy'},
    {'symbol': 'CAT', 'name': 'Caterpillar Inc.', 'price': 342.10, 'changePct': 1.24, 'sector': 'Industrials'},
    {'symbol': 'HON', 'name': 'Honeywell Intl.', 'price': 198.50, 'changePct': 0.38, 'sector': 'Industrials'},
    {'symbol': 'PG', 'name': 'Procter & Gamble', 'price': 162.40, 'changePct': 0.22, 'sector': 'Consumer Staples'},
    {'symbol': 'KO', 'name': 'Coca-Cola Co.', 'price': 60.80, 'changePct': 0.15, 'sector': 'Consumer Staples'},
    {'symbol': 'NEE', 'name': 'NextEra Energy', 'price': 68.90, 'changePct': 0.42, 'sector': 'Utilities'},
    {'symbol': 'AMT', 'name': 'American Tower', 'price': 198.70, 'changePct': -0.28, 'sector': 'Real Estate'},
    {'symbol': 'LIN', 'name': 'Linde plc', 'price': 452.30, 'changePct': 0.65, 'sector': 'Materials'},
  ];

  static String _guessSector(String sym) {
    const map = {
      'Information Technology': ['NVDA','AAPL','MSFT','AMD','PLTR','SHOP','DDOG','CRWD','SNAP','RBLX','CRM','ORCL','INTC','AVGO','ADBE','CSCO','QCOM','TXN','NOW','INTU','COIN','MSTR','HOOD','SOFI','PYPL'],
      'Communication Services': ['GOOGL','GOOG','META','NFLX','DIS','SPOT','T','VZ','TMUS','EA','TTWO'],
      'Consumer Discretionary': ['AMZN','TSLA','RIVN','NIO','F','GM','UBER','ABNB','BABA','HD','MCD','NKE','SBUX','TGT','LOW'],
      'Financials': ['JPM','BAC','GS','V','MA','SPY','BRK.B','C','WFC','AXP','BLK','MS','SCHW'],
      'Health Care': ['UNH','JNJ','LLY','PFE','ABBV','MRK','TMO','ABT','BMY','AMGN','GILD','ISRG','MDT'],
      'Industrials': ['CAT','HON','BA','GE','RTX','UPS','FDX','DE','LMT','MMM','UNP','WM'],
      'Consumer Staples': ['PG','KO','PEP','WMT','COST','PM','MO','CL','MDLZ','EL','KHC'],
      'Energy': ['XOM','CVX','COP','SLB','EOG','MPC','PSX','VLO','OXY'],
      'Utilities': ['NEE','DUK','SO','D','AEP','EXC','SRE','XEL','ED','WEC'],
      'Real Estate': ['AMT','PLD','CCI','EQIX','SPG','O','WELL','DLR','PSA','AVB'],
      'Materials': ['LIN','APD','SHW','FCX','NEM','ECL','DD','NUE','VMC','MLM'],
    };
    for (final entry in map.entries) {
      if (entry.value.contains(sym)) return entry.key;
    }
    return 'Other';
  }

  static String _initials(String name) {
    if (name.isEmpty) return '??';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_draftComplete) return _buildDraftComplete();

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: Column(
          children: [
            // 1) Header
            _buildHeader(),
            // 2) Draft board with player columns
            Expanded(flex: 4, child: _buildDraftBoard()),
            // 3) On the clock bar
            _buildClockBar(),
            // 4) Tab bar
            _buildTabBar(),
            // 5) Tab content
            Expanded(flex: 5, child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildStocksTab(),
                _buildMyPicksTab(),
                _buildChatTab(),
              ],
            )),
          ],
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.border)),
    ),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back_ios, size: 16, color: AppTheme.green),
      ),
      const SizedBox(width: 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DRAFT ROOM', style: TextStyle(
              fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.w800,
              color: AppTheme.green, letterSpacing: 1)),
          Text(widget.leagueName, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      )),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          border: Border.all(color: AppTheme.border2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('RD ${_currentRound()}/${widget.rosterSize}',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 10,
                fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
      ),
    ]),
  );

  // ══════════════════════════════════════
  // DRAFT BOARD — 5-column grid with player columns
  // ══════════════════════════════════════
  Widget _buildDraftBoard() {
    // Pad to 5 columns minimum for visual consistency
    final cols = _memberUids.length.clamp(1, 10);
    final displayCols = cols < 5 ? 5 : cols;
    final rounds = widget.rosterSize;

    // Build pick lookup: pickNumber → DraftPick
    final pickMap = <int, DraftPick>{};
    for (final p in _picks) {
      pickMap[p.pickNumber] = p;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF050810),
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 2)),
      ),
      child: Column(
        children: [
          // Player name headers
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(displayCols, (c) {
                  final hasPlayer = c < _members.length;
                  final name = hasPlayer ? _members[c].username : '';
                  final uid = hasPlayer ? _members[c].id : '';
                  final isMe = uid == _uid;
                  final isTurn = _memberUids.isNotEmpty &&
                      _currentTurnIndex() >= 0 &&
                      c < _memberUids.length &&
                      _memberUids[_currentTurnIndex()] == uid;

                  return SizedBox(
                    width: 76,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color: isTurn ? AppTheme.greenDim : AppTheme.surface2,
                            border: Border.all(
                              color: isTurn ? AppTheme.green
                                  : isMe ? AppTheme.green.withValues(alpha: 0.3)
                                  : AppTheme.border,
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Center(child: Text(
                            hasPlayer ? _initials(name) : '',
                            style: TextStyle(fontFamily: 'SpaceGrotesk',
                                fontSize: 8, fontWeight: FontWeight.w900,
                                color: isTurn ? AppTheme.green : Colors.white),
                          )),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasPlayer ? (isMe ? 'You' : (name.length > 8
                              ? '${name.substring(0, 7)}.' : name)) : '',
                          style: TextStyle(fontFamily: 'Courier', fontSize: 8,
                              color: isTurn ? AppTheme.green : AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ),
          // Grid of picks
          Expanded(
            child: SingleChildScrollView(
              controller: _boardScrollCtrl,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: List.generate(rounds, (r) {
                    return Row(
                      children: List.generate(displayCols, (c) {
                        // Snake: even rounds (0,2,4..) forward, odd reverse
                        final snakeC = r % 2 == 1 && c < cols
                            ? (cols - 1 - c)
                            : c;
                        final pickNum = c < cols ? r * cols + snakeC + 1 : -1;
                        final pick = pickNum > 0 ? pickMap[pickNum] : null;

                        if (pick != null) {
                          final sec = _guessSector(pick.symbol);
                          final bg = _sectorBg[sec] ?? const Color(0xFF111827);
                          final fg = _sectorFg[sec] ?? AppTheme.textMuted;
                          return Container(
                            width: 76, height: 44,
                            margin: const EdgeInsets.all(1),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            decoration: BoxDecoration(
                              color: bg,
                              border: Border.all(color: fg.withValues(alpha: 0.25)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${r + 1}.${(c < cols ? snakeC : c) + 1}',
                                    style: TextStyle(fontFamily: 'Courier',
                                        fontSize: 7, color: fg.withValues(alpha: 0.5))),
                                Text(pick.symbol,
                                    style: const TextStyle(fontFamily: 'SpaceGrotesk',
                                        fontSize: 12, fontWeight: FontWeight.w900,
                                        color: Colors.white, height: 1.1)),
                              ],
                            ),
                          );
                        }

                        // Empty slot or phantom column
                        final isReal = c < cols && pickNum > 0;
                        return Container(
                          width: 76, height: 44,
                          margin: const EdgeInsets.all(1),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0E18),
                            border: Border.all(
                                color: AppTheme.border.withValues(alpha: isReal ? 0.3 : 0.1)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: isReal
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${r + 1}.${snakeC + 1}',
                                        style: TextStyle(fontFamily: 'Courier', fontSize: 7,
                                            color: AppTheme.textMuted.withValues(alpha: 0.4))),
                                    Text('—', style: TextStyle(fontFamily: 'SpaceGrotesk',
                                        fontSize: 12, fontWeight: FontWeight.w900,
                                        color: AppTheme.textMuted.withValues(alpha: 0.15))),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  // CLOCK BAR
  // ══════════════════════════════════════
  Widget _buildClockBar() {
    final isMe = _isMyTurn();
    final turnUid = _currentTurnUid();
    final turnMember = _memberForUid(turnUid);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.green.withValues(alpha: 0.04) : AppTheme.surface,
        border: Border(
          bottom: BorderSide(
              color: isMe ? AppTheme.green.withValues(alpha: 0.12) : AppTheme.border),
        ),
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: isMe ? AppTheme.greenDim : AppTheme.surface2,
            border: Border.all(
                color: isMe ? AppTheme.green : AppTheme.border2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(
            isMe ? 'YOU' : _initials(turnMember.username),
            style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 10,
                fontWeight: FontWeight.w900,
                color: isMe ? AppTheme.green : AppTheme.textMuted),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ON THE CLOCK · RD ${_currentRound()} · PICK #${_picks.length + 1}',
              style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                  color: isMe ? AppTheme.green : AppTheme.textMuted,
                  fontWeight: FontWeight.w700),
            ),
            Text(_currentTurnName(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        )),
        // Timer
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('PICK TIMER', style: TextStyle(fontFamily: 'Courier',
              fontSize: 9, color: AppTheme.textMuted)),
          Text('$_timerSecs',
              style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 24,
                  fontWeight: FontWeight.w900, letterSpacing: -0.5,
                  color: _timerSecs <= 10 ? AppTheme.red : AppTheme.green)),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════
  // TAB BAR
  // ══════════════════════════════════════
  Widget _buildTabBar() => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.border)),
    ),
    child: TabBar(
      controller: _tabCtrl,
      indicatorColor: AppTheme.green,
      indicatorWeight: 2,
      labelColor: AppTheme.green,
      unselectedLabelColor: AppTheme.textMuted,
      labelStyle: const TextStyle(fontFamily: 'Courier', fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.5),
      tabs: const [
        Tab(text: 'STOCKS'),
        Tab(text: 'MY PICKS'),
        Tab(text: 'CHAT'),
      ],
    ),
  );

  // ══════════════════════════════════════
  // STOCKS TAB
  // ══════════════════════════════════════
  Widget _buildStocksTab() => Column(
    children: [
      // Search bar
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Search stocks to draft...',
              hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          )),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () { _searchCtrl.clear(); _runSearch(''); },
              child: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
            ),
        ]),
      ),
      // Sector chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: _sectors.map((s) {
            final on = s == _activeSector;
            final fg = _sectorFg[s] ?? AppTheme.green;
            final bg = _sectorBg[s] ?? AppTheme.surface2;
            return GestureDetector(
              onTap: () => setState(() => _activeSector = s),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: on ? (s == 'All' ? AppTheme.green : bg) : AppTheme.surface1,
                  border: Border.all(
                    color: on ? (s == 'All' ? AppTheme.green
                        : fg.withValues(alpha: 0.5)) : AppTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(s, style: TextStyle(fontFamily: 'Courier', fontSize: 9,
                    color: on ? (s == 'All' ? Colors.black : fg) : AppTheme.textMuted)),
              ),
            );
          }).toList(),
        ),
      ),
      // Stock list
      Expanded(
        child: _isSearching
            ? const Center(child: CircularProgressIndicator(
                color: AppTheme.green, strokeWidth: 2))
            : _buildStockList(),
      ),
    ],
  );

  Widget _buildStockList() {
    var list = _searchResults;
    if (_activeSector != 'All') {
      list = list.where((s) => s['sector'] == _activeSector).toList();
    }
    if (list.isEmpty) {
      return const Center(child: Text('No stocks found',
          style: TextStyle(fontFamily: 'Courier', fontSize: 12,
              color: AppTheme.textMuted)));
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final s = list[i];
        final sym = s['symbol'] as String;
        final taken = _isTaken(sym);
        final pct = (s['changePct'] as num).toDouble();
        final up = pct >= 0;
        final sec = s['sector'] as String? ?? 'Other';
        final fg = _sectorFg[sec] ?? AppTheme.textMuted;
        final bg = _sectorBg[sec] ?? AppTheme.surface2;

        return GestureDetector(
          onTap: () => _openConfirm(s),
          child: Opacity(
            opacity: taken ? 0.3 : 1.0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(children: [
                // Sector-colored ticker badge
                SizedBox(
                  width: 54,
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(color: fg.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(sym, textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Courier', fontSize: 11,
                              fontWeight: FontWeight.w700, color: fg)),
                    ),
                    const SizedBox(height: 2),
                    Text(sec.length > 10 ? '${sec.substring(0, 9)}.' : sec,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Courier', fontSize: 6, color: fg)),
                  ]),
                ),
                const SizedBox(width: 8),
                // Company name
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'] as String, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(taken ? 'Already drafted'
                        : AppTheme.currency((s['price'] as num).toDouble()),
                        style: TextStyle(fontFamily: 'Courier', fontSize: 9,
                            color: taken ? AppTheme.red : AppTheme.textMuted)),
                  ],
                )),
                // Price + change
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(AppTheme.currency((s['price'] as num).toDouble()),
                      style: const TextStyle(fontFamily: 'Courier', fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  Text('${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
                      style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: up ? AppTheme.green : AppTheme.red)),
                ]),
                const SizedBox(width: 8),
                // DRAFT / TAKEN button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: taken ? AppTheme.redDim : AppTheme.green,
                    border: taken
                        ? Border.all(color: AppTheme.red.withValues(alpha: 0.3))
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(taken ? 'TAKEN' : 'DRAFT',
                      style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: taken ? AppTheme.red : Colors.black)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════
  // MY PICKS TAB
  // ══════════════════════════════════════
  Widget _buildMyPicksTab() {
    final myPicks = _picksFor(_uid);
    if (myPicks.isEmpty) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: AppTheme.textMuted),
          SizedBox(height: 8),
          Text('No picks yet', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Draft a stock to see it here',
              style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                  color: AppTheme.textMuted)),
        ],
      ));
    }

    return ListView.builder(
      itemCount: myPicks.length,
      itemBuilder: (_, i) {
        final p = myPicks[i];
        final sec = _guessSector(p.symbol);
        final fg = _sectorFg[sec] ?? AppTheme.textMuted;
        final bg = _sectorBg[sec] ?? AppTheme.surface2;

        return Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: fg.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(p.symbol, style: TextStyle(fontFamily: 'Courier',
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.companyName, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
                Text('Rd ${p.round} · Pick #${p.pickNumber}',
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 9,
                        color: AppTheme.textMuted)),
              ],
            )),
            Text(AppTheme.currency(p.priceAtDraft),
                style: const TextStyle(fontFamily: 'Courier', fontSize: 12,
                    fontWeight: FontWeight.w700, color: AppTheme.green)),
          ]),
        );
      },
    );
  }

  // ══════════════════════════════════════
  // CHAT TAB
  // ══════════════════════════════════════
  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('leagues')
                .doc(widget.leagueId)
                .collection('chat')
                .orderBy('timestamp')
                .limitToLast(50)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 36,
                        color: AppTheme.textMuted),
                    SizedBox(height: 8),
                    Text('Draft room chat', style: TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Messages will appear here',
                        style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                            color: AppTheme.textMuted)),
                  ],
                ));
              }

              final msgs = snap.data!.docs;
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final data = msgs[i].data() as Map<String, dynamic>;
                  final senderUid = data['senderUID'] as String? ?? '';
                  final senderName = data['senderUsername'] as String? ?? 'System';
                  final text = data['text'] as String? ?? '';
                  final isMe = senderUid == _uid;
                  final isSystem = data['isSystemEvent'] == true;

                  if (isSystem) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Center(child: Text(text,
                          style: const TextStyle(fontFamily: 'Courier',
                              fontSize: 10, color: AppTheme.textMuted))),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisAlignment: isMe
                          ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe) ...[
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              color: AppTheme.surface2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(child: Text(_initials(senderName),
                                style: const TextStyle(fontFamily: 'SpaceGrotesk',
                                    fontSize: 9, fontWeight: FontWeight.w900,
                                    color: Colors.white))),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(isMe ? 'You' : senderName,
                                style: TextStyle(fontFamily: 'Courier', fontSize: 10,
                                    color: isMe ? AppTheme.green : AppTheme.textMuted)),
                            const SizedBox(height: 2),
                            Container(
                              constraints: const BoxConstraints(maxWidth: 220),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isMe ? AppTheme.green : AppTheme.surface2,
                                border: isMe ? null
                                    : Border.all(color: AppTheme.border),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(text, style: TextStyle(fontSize: 13,
                                  color: isMe ? Colors.black : AppTheme.text,
                                  fontWeight: isMe ? FontWeight.w600
                                      : FontWeight.normal)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════
  // DRAFT COMPLETE
  // ══════════════════════════════════════
  Widget _buildDraftComplete() {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.greenDim,
                    border: Border.all(color: AppTheme.greenBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.check_rounded, size: 44,
                      color: AppTheme.green),
                ),
                const SizedBox(height: 24),
                const Text('Draft Complete!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(widget.leagueName, style: const TextStyle(fontFamily: 'Courier',
                    fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 24),
                ..._memberUids.map((uid) {
                  final m = _memberForUid(uid);
                  final picks = _picksFor(uid);
                  final isMe = uid == _uid;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? AppTheme.greenDim : AppTheme.surface2,
                      border: Border.all(
                          color: isMe ? AppTheme.greenBorder : AppTheme.border2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(isMe ? 'Your Roster' : m.username,
                              style: TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isMe ? AppTheme.green : AppTheme.text)),
                          const Spacer(),
                          Text('${picks.length} stocks',
                              style: const TextStyle(fontFamily: 'Courier',
                                  fontSize: 10, color: AppTheme.textMuted)),
                        ]),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4,
                          children: picks.map((p) {
                            final sec = _guessSector(p.symbol);
                            final fg = _sectorFg[sec] ?? AppTheme.textMuted;
                            final bg = _sectorBg[sec] ?? AppTheme.surface2;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: bg,
                                border: Border.all(color: fg.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(p.symbol, style: TextStyle(
                                  fontFamily: 'Courier', fontSize: 10,
                                  fontWeight: FontWeight.w700, color: fg)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context)
                        .pushReplacement(MaterialPageRoute(
                            builder: (_) =>
                                LeagueScreen(leagueId: widget.leagueId))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Go to League',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
