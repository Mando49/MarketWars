import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../services/i_stock_service.dart';
import '../../services/finnhub_stock_service.dart';

class MatchDetailScreen extends StatefulWidget {
  final Challenge challenge;
  const MatchDetailScreen({super.key, required this.challenge});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  Timer? _refreshTimer;
  bool _loading = true;
  List<_PickData> _myPicks = [];
  List<_PickData> _theirPicks = [];
  String _myUid = '';
  bool _isChallenger = false;
  final IStockService _stockService = FinnhubStockService();

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _isChallenger = widget.challenge.challengerUID == _myUid;
    _loadPicks();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshPrices());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPicks() async {
    setState(() => _loading = true);
    try {
      final challenge = widget.challenge;
      debugPrint('[MatchDetail] ========== LOADING PICKS ==========');
      debugPrint('[MatchDetail] challenge.id: ${challenge.id}');
      debugPrint('[MatchDetail] challengerUID: ${challenge.challengerUID}');
      debugPrint('[MatchDetail] opponentUID: ${challenge.opponentUID}');
      debugPrint('[MatchDetail] myUid: $_myUid | isChallenger: $_isChallenger');
      debugPrint('[MatchDetail] challenge.status: ${challenge.status}');

      final firestore = FirebaseFirestore.instance;
      final challengerSnap = await firestore
          .collection('matchmaking')
          .doc(challenge.id)
          .collection('picks')
          .doc(challenge.challengerUID)
          .get();
      final opponentSnap = await firestore
          .collection('matchmaking')
          .doc(challenge.id)
          .collection('picks')
          .doc(challenge.opponentUID)
          .get();

      debugPrint('[MatchDetail] challengerSnap exists: ${challengerSnap.exists}');
      debugPrint('[MatchDetail] challengerSnap data: ${challengerSnap.data()}');
      debugPrint('[MatchDetail] opponentSnap exists: ${opponentSnap.exists}');
      debugPrint('[MatchDetail] opponentSnap data: ${opponentSnap.data()}');

      var challengerRaw = _parsePicks(challengerSnap.data());
      var opponentRaw = _parsePicks(opponentSnap.data());

      debugPrint('[MatchDetail] Firestore subcollection — challengerRaw.length: ${challengerRaw.length}');
      debugPrint('[MatchDetail] Firestore subcollection — opponentRaw.length: ${opponentRaw.length}');

      // Fallback: read picks from the challenge document itself
      if (challengerRaw.isEmpty && challenge.challengerPicks.isNotEmpty) {
        debugPrint('[MatchDetail] FALLBACK: using challenge.challengerPicks (${challenge.challengerPicks.length} picks)');
        debugPrint('[MatchDetail] challengerPicks raw: ${challenge.challengerPicks}');
        challengerRaw = challenge.challengerPicks.map<_RawPick>((m) {
          return _RawPick(
            symbol: m['symbol'] ?? '',
            name: m['name'] ?? m['companyName'] ?? '',
            priceAtPick: (m['priceAtPick'] ?? m['price'] ?? 0).toDouble(),
            direction: m['direction'] ?? 'long',
          );
        }).toList();
      }
      if (opponentRaw.isEmpty && challenge.opponentPicks.isNotEmpty) {
        debugPrint('[MatchDetail] FALLBACK: using challenge.opponentPicks (${challenge.opponentPicks.length} picks)');
        debugPrint('[MatchDetail] opponentPicks raw: ${challenge.opponentPicks}');
        opponentRaw = challenge.opponentPicks.map<_RawPick>((m) {
          return _RawPick(
            symbol: m['symbol'] ?? '',
            name: m['name'] ?? m['companyName'] ?? '',
            priceAtPick: (m['priceAtPick'] ?? m['price'] ?? 0).toDouble(),
            direction: m['direction'] ?? 'long',
          );
        }).toList();
      }

      debugPrint('[MatchDetail] FINAL — challengerRaw.length: ${challengerRaw.length}');
      debugPrint('[MatchDetail] FINAL — opponentRaw.length: ${opponentRaw.length}');
      for (final p in challengerRaw) {
        debugPrint('[MatchDetail]   challenger pick: ${p.symbol} "${p.name}" @ \$${p.priceAtPick}');
      }
      for (final p in opponentRaw) {
        debugPrint('[MatchDetail]   opponent pick: ${p.symbol} "${p.name}" @ \$${p.priceAtPick}');
      }

      if (!mounted) return;
      final stockService = _stockService;
      final myRaw = _isChallenger ? challengerRaw : opponentRaw;
      final theirRaw = _isChallenger ? opponentRaw : challengerRaw;

      _myPicks = await _fetchCurrentPrices(myRaw, stockService);
      _theirPicks = await _fetchCurrentPrices(theirRaw, stockService);
      debugPrint('[MatchDetail] DONE — myPicks: ${_myPicks.length}, theirPicks: ${_theirPicks.length}');
      await _writeBackValues();
    } catch (e, st) {
      debugPrint('[MatchDetail] ERROR loading picks: $e');
      debugPrint('[MatchDetail] Stack trace: $st');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<_RawPick> _parsePicks(Map<String, dynamic>? data) {
    if (data == null) return [];
    // Try 'picks' array first, then try top-level list-like structure
    final picks = data['picks'];
    if (picks is List) {
      return picks.map<_RawPick>((p) {
        final m = p as Map<String, dynamic>;
        return _RawPick(
          symbol: m['symbol'] ?? '',
          name: m['name'] ?? m['companyName'] ?? '',
          priceAtPick: (m['priceAtPick'] ?? m['price'] ?? 0).toDouble(),
          direction: m['direction'] ?? 'long',
        );
      }).toList();
    }
    // Maybe the doc itself has symbol/price fields (single pick per doc)
    if (data.containsKey('symbol')) {
      return [
        _RawPick(
          symbol: data['symbol'] ?? '',
          name: data['name'] ?? data['companyName'] ?? '',
          priceAtPick: (data['priceAtPick'] ?? data['price'] ?? 0).toDouble(),
          direction: data['direction'] ?? 'long',
        ),
      ];
    }
    debugPrint('[MatchDetail] _parsePicks: unrecognized data shape: $data');
    return [];
  }

  Future<List<_PickData>> _fetchCurrentPrices(
      List<_RawPick> raw, IStockService stockService) async {
    final results = <_PickData>[];
    for (final r in raw) {
      final quote = await stockService.fetchQuote(r.symbol);
      final currentPrice = quote?.currentPrice ?? r.priceAtPick;
      var pctChange =
          r.priceAtPick > 0 ? ((currentPrice - r.priceAtPick) / r.priceAtPick) * 100 : 0.0;
      // Invert for short picks
      if (r.direction == 'short') pctChange = -pctChange;
      results.add(_PickData(
        symbol: r.symbol,
        name: r.name,
        priceAtPick: r.priceAtPick,
        currentPrice: currentPrice,
        pctChange: pctChange,
        direction: r.direction,
      ));
    }
    return results;
  }

  Future<void> _refreshPrices() async {
    if (!mounted) return;
    final stockService = _stockService;
    final myUpdated = await _fetchCurrentPrices(
      _myPicks.map((p) => _RawPick(symbol: p.symbol, name: p.name, priceAtPick: p.priceAtPick, direction: p.direction)).toList(),
      stockService,
    );
    final theirUpdated = await _fetchCurrentPrices(
      _theirPicks.map((p) => _RawPick(symbol: p.symbol, name: p.name, priceAtPick: p.priceAtPick, direction: p.direction)).toList(),
      stockService,
    );
    if (mounted) {
      setState(() {
        _myPicks = myUpdated;
        _theirPicks = theirUpdated;
      });
      await _writeBackValues();
    }
  }

  String _timeRemaining() {
    if (widget.challenge.startDate == null) return 'Picking stocks';
    final end = widget.challenge.duration == '1day'
        ? widget.challenge.startDate!.add(const Duration(days: 1))
        : widget.challenge.startDate!.add(const Duration(days: 7));
    final remaining = end.difference(DateTime.now());
    if (remaining.isNegative) return 'Ended';
    if (remaining.inDays > 0) return '${remaining.inDays}d ${remaining.inHours % 24}h left';
    if (remaining.inHours > 0) return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
    return '${remaining.inMinutes}m left';
  }

  double _totalPct(List<_PickData> picks) {
    if (picks.isEmpty) return 0;
    // Weighted average of individual % changes (which already account for short direction)
    double totalCost = 0, weightedPctSum = 0;
    for (final p in picks) {
      totalCost += p.priceAtPick;
      weightedPctSum += p.priceAtPick * p.pctChange;
    }
    return totalCost > 0 ? weightedPctSum / totalCost : 0;
  }

  double _totalCost(List<_PickData> picks) {
    double total = 0;
    for (final p in picks) {
      total += p.priceAtPick;
    }
    return total;
  }

  double _totalValue(List<_PickData> picks) {
    double total = 0;
    for (final p in picks) {
      // For short picks, the "value" reflects the inverse movement
      if (p.direction == 'short') {
        total += p.priceAtPick + (p.priceAtPick - p.currentPrice);
      } else {
        total += p.currentPrice;
      }
    }
    return total;
  }

  Future<void> _writeBackValues() async {
    if (_myPicks.isEmpty && _theirPicks.isEmpty) return;
    final challengerPicks = _isChallenger ? _myPicks : _theirPicks;
    final opponentPicks = _isChallenger ? _theirPicks : _myPicks;

    final newChallengerCost = _totalCost(challengerPicks);
    final newChallengerValue = _totalValue(challengerPicks);
    final newOpponentCost = _totalCost(opponentPicks);
    final newOpponentValue = _totalValue(opponentPicks);

    final challenge = widget.challenge;
    // Only write if values actually changed
    if (newChallengerCost == challenge.challengerCost &&
        newChallengerValue == challenge.challengerValue &&
        newOpponentCost == challenge.opponentCost &&
        newOpponentValue == challenge.opponentValue) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('challenges')
          .doc(challenge.id)
          .update({
        'challengerCost': newChallengerCost,
        'challengerValue': newChallengerValue,
        'opponentCost': newOpponentCost,
        'opponentValue': newOpponentValue,
      });
      // Update local model so subsequent checks see current values
      challenge.challengerCost = newChallengerCost;
      challenge.challengerValue = newChallengerValue;
      challenge.opponentCost = newOpponentCost;
      challenge.opponentValue = newOpponentValue;
      debugPrint('[MatchDetail] Wrote back values — cCost=$newChallengerCost cVal=$newChallengerValue oCost=$newOpponentCost oVal=$newOpponentValue');
    } catch (e) {
      debugPrint('[MatchDetail] Error writing back values: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final opponentName = widget.challenge.opponentNameOf(_myUid);
    final myPct = _totalPct(_myPicks);
    final theirPct = _totalPct(_theirPicks);
    final winning = myPct >= theirPct;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        title: Text(
          'YOU vs ${opponentName.toUpperCase()}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'Courier',
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _timeRemaining(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.green))
          : RefreshIndicator(
              color: AppTheme.green,
              backgroundColor: AppTheme.surface,
              onRefresh: _refreshPrices,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary card
                  _buildSummaryCard(myPct, theirPct, winning, opponentName),
                  const SizedBox(height: 20),
                  // My picks
                  _buildSectionHeader('YOUR PICKS'),
                  const SizedBox(height: 8),
                  ..._myPicks.map(_buildPickCard),
                  const SizedBox(height: 20),
                  // Opponent picks
                  _buildSectionHeader("${opponentName.toUpperCase()}'S PICKS"),
                  const SizedBox(height: 8),
                  ..._theirPicks.map(_buildPickCard),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(
      double myPct, double theirPct, bool winning, String opponentName) {
    final myBarFlex = myPct.abs() + theirPct.abs() > 0
        ? (myPct.abs() / (myPct.abs() + theirPct.abs())).clamp(0.15, 0.85)
        : 0.5;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: [
        // Score row
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: winning
                    ? AppTheme.green.withValues(alpha: 0.05)
                    : AppTheme.surface2,
                borderRadius: BorderRadius.circular(10),
                border: winning
                    ? Border.all(color: AppTheme.green.withValues(alpha: 0.15))
                    : null,
              ),
              child: Column(children: [
                const Text('YOU',
                    style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                        fontFamily: 'Courier')),
                const SizedBox(height: 4),
                Text(
                  '${myPct >= 0 ? '+' : ''}${myPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Courier',
                    color: myPct >= 0 ? AppTheme.green : AppTheme.red,
                  ),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(winning ? '>' : '<',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: winning ? AppTheme.green : AppTheme.red,
                    fontFamily: 'Courier')),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: !winning
                    ? AppTheme.red.withValues(alpha: 0.05)
                    : AppTheme.surface2,
                borderRadius: BorderRadius.circular(10),
                border: !winning
                    ? Border.all(color: AppTheme.red.withValues(alpha: 0.15))
                    : null,
              ),
              child: Column(children: [
                Text(opponentName.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.textMuted,
                        fontFamily: 'Courier'),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(
                  '${theirPct >= 0 ? '+' : ''}${theirPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Courier',
                    color: theirPct >= 0 ? AppTheme.green : AppTheme.red,
                  ),
                ),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        // Win bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Row(children: [
              Flexible(
                flex: (myBarFlex * 100).round(),
                child: Container(color: winning ? AppTheme.green : AppTheme.red),
              ),
              Flexible(
                flex: ((1 - myBarFlex) * 100).round(),
                child: Container(color: !winning ? AppTheme.green : AppTheme.red),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        fontFamily: 'Courier',
        color: AppTheme.textMuted,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildPickCard(_PickData pick) {
    final positive = pick.pctChange >= 0;
    final isShort = pick.direction == 'short';
    final dirColor = isShort ? AppTheme.red : AppTheme.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        // Symbol badge
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (positive ? AppTheme.green : AppTheme.red).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            pick.symbol.length > 4 ? pick.symbol.substring(0, 4) : pick.symbol,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFamily: 'Courier',
              color: positive ? AppTheme.green : AppTheme.red,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Name + direction + prices
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(pick.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: dirColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isShort ? '▼ SHORT' : '▲ LONG',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Courier',
                      color: dirColor,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                '\$${pick.priceAtPick.toStringAsFixed(2)} → \$${pick.currentPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'Courier',
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        // % change
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (positive ? AppTheme.green : AppTheme.red).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${positive ? '+' : ''}${pick.pctChange.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFamily: 'Courier',
              color: positive ? AppTheme.green : AppTheme.red,
            ),
          ),
        ),
      ]),
    );
  }
}

class _RawPick {
  final String symbol, name, direction;
  final double priceAtPick;
  _RawPick({required this.symbol, required this.name, required this.priceAtPick, this.direction = 'long'});
}

class _PickData {
  final String symbol, name, direction;
  final double priceAtPick, currentPrice, pctChange;
  _PickData({
    required this.symbol,
    required this.name,
    required this.priceAtPick,
    required this.currentPrice,
    required this.pctChange,
    this.direction = 'long',
  });
}
