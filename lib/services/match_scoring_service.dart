import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'i_stock_service.dart';

// ─────────────────────────────────────────
// 1v1 MATCH SCORING SERVICE
// Handles Daily Duel, Weekly War, and
// 1v1 Ranked match scoring.
// ─────────────────────────────────────────
class MatchScoringService {
  final FirebaseFirestore _db;
  final IStockService _stockService;
  Timer? _periodicTimer;

  MatchScoringService({
    required IStockService stockService,
    FirebaseFirestore? firestore,
  })  : _stockService = stockService,
        _db = firestore ?? FirebaseFirestore.instance;

  // ── Scoring table ──────────────────────

  /// Award ranking points based on portfolio % change.
  static int pointsForPctChange(double pct) {
    if (pct >= 10) return 100;
    if (pct >= 7) return 75;
    if (pct >= 5) return 50;
    if (pct >= 3) return 35;
    if (pct >= 1) return 20;
    if (pct >= 0) return 10;
    return 5; // negative
  }

  // ── Score a single match ───────────────

  /// Score a completed 1v1 match.
  ///
  /// 1. Reads match data from /challenges/{matchId}
  /// 2. Reads both players' picks from /matchmaking/{matchId}/picks/{uid}
  /// 3. Fetches current stock prices
  /// 4. Calculates each player's portfolio % change
  /// 5. Determines winner and awards ranking points
  /// 6. Updates match status to 'complete' with final results
  /// 7. Updates user win/loss record in rankedProfiles
  Future<void> scoreMatch(String matchId) async {
    try {
      // ── 1. Read match data ──
      final matchDoc = await _db.collection('challenges').doc(matchId).get();
      if (!matchDoc.exists) {
        debugPrint('MatchScoring: Challenge $matchId not found');
        return;
      }
      final match = matchDoc.data()!;
      if (match['status'] == 'complete') {
        debugPrint('MatchScoring: $matchId already scored');
        return;
      }

      final challengerUID = match['challengerUID'] as String;
      final opponentUID = match['opponentUID'] as String;

      // ── 2. Read picks from /matchmaking/{matchId}/picks/{uid} ──
      final picksSnap = await _db
          .collection('matchmaking')
          .doc(matchId)
          .collection('picks')
          .get();

      // Build picks map by UID
      final Map<String, List<Map<String, dynamic>>> picksByUid = {};
      final Map<String, double> costByUid = {};

      for (final doc in picksSnap.docs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? doc.id;
        final picks = List<Map<String, dynamic>>.from(data['picks'] ?? []);
        final totalCost = (data['totalCost'] ?? 0).toDouble();
        picksByUid[uid] = picks;
        costByUid[uid] = totalCost;
      }

      // If picks aren't in matchmaking subcollection, fall back to challenge doc
      if (!picksByUid.containsKey(challengerUID)) {
        final cPicks =
            List<Map<String, dynamic>>.from(match['challengerPicks'] ?? []);
        if (cPicks.isNotEmpty) {
          picksByUid[challengerUID] = cPicks;
          costByUid[challengerUID] = (match['challengerCost'] ?? 0).toDouble();
        }
      }
      if (!picksByUid.containsKey(opponentUID)) {
        final oPicks =
            List<Map<String, dynamic>>.from(match['opponentPicks'] ?? []);
        if (oPicks.isNotEmpty) {
          picksByUid[opponentUID] = oPicks;
          costByUid[opponentUID] = (match['opponentCost'] ?? 0).toDouble();
        }
      }

      if (!picksByUid.containsKey(challengerUID) ||
          !picksByUid.containsKey(opponentUID)) {
        debugPrint('MatchScoring: Missing picks for one or both players in $matchId');
        return;
      }

      // ── 3. Fetch current prices for all unique symbols ──
      final allSymbols = <String>{};
      for (final picks in picksByUid.values) {
        for (final p in picks) {
          allSymbols.add(p['symbol'] as String);
        }
      }

      final Map<String, double> currentPrices = {};
      for (final symbol in allSymbols) {
        try {
          final quote = await _stockService.fetchQuote(symbol);
          if (quote != null) {
            currentPrices[symbol] = quote.currentPrice;
          }
        } catch (e) {
          debugPrint('MatchScoring: Error fetching $symbol: $e');
        }
      }
      debugPrint('MatchScoring: Fetched ${currentPrices.length}/${allSymbols.length} prices');

      // ── 4. Calculate each player's portfolio % change ──
      final results = <String, _PlayerResult>{};

      for (final uid in [challengerUID, opponentUID]) {
        final picks = picksByUid[uid]!;
        final costBasis = costByUid[uid] ?? 0.0;
        double currentValue = 0;

        final holdings = <Map<String, dynamic>>[];
        for (final pick in picks) {
          final symbol = pick['symbol'] as String;
          final priceAtPick = (pick['priceAtPick'] ?? 0).toDouble();
          final nowPrice = currentPrices[symbol] ?? priceAtPick;

          currentValue += nowPrice;
          holdings.add({
            'symbol': symbol,
            'companyName': pick['companyName'] ?? symbol,
            'priceAtPick': priceAtPick,
            'currentPrice': nowPrice,
            'change': nowPrice - priceAtPick,
            'changePct': priceAtPick > 0
                ? ((nowPrice - priceAtPick) / priceAtPick) * 100
                : 0.0,
          });
        }

        final pctChange =
            costBasis > 0 ? ((currentValue - costBasis) / costBasis) * 100 : 0.0;
        final pts = pointsForPctChange(pctChange);

        results[uid] = _PlayerResult(
          uid: uid,
          costBasis: costBasis,
          currentValue: currentValue,
          pctChange: double.parse(pctChange.toStringAsFixed(4)),
          points: pts,
          holdings: holdings,
        );

        debugPrint('MatchScoring: $uid — cost: \$${costBasis.toStringAsFixed(2)}, '
            'value: \$${currentValue.toStringAsFixed(2)}, '
            'pct: ${pctChange.toStringAsFixed(2)}%, pts: $pts');
      }

      // ── 5. Determine winner ──
      final cResult = results[challengerUID]!;
      final oResult = results[opponentUID]!;

      String? winnerId;
      String? loserId;
      if (cResult.pctChange > oResult.pctChange) {
        winnerId = challengerUID;
        loserId = opponentUID;
      } else if (oResult.pctChange > cResult.pctChange) {
        winnerId = opponentUID;
        loserId = challengerUID;
      }
      // If tied, winnerId stays null (draw)

      // ── 6. Update match status to 'complete' ──
      await _db.collection('challenges').doc(matchId).update({
        'status': 'complete',
        'winnerId': winnerId,
        'challengerValue': cResult.currentValue,
        'opponentValue': oResult.currentValue,
        'completedAt': DateTime.now().toIso8601String(),
      });

      debugPrint('MatchScoring: $matchId complete — winner: ${winnerId ?? 'draw'}');

      // ── 7. Award ranking points and update win/loss records ──
      final batch = _db.batch();

      for (final uid in [challengerUID, opponentUID]) {
        final r = results[uid]!;
        final isWinner = uid == winnerId;
        final isLoser = uid == loserId;

        final profileRef = _db.collection('rankedProfiles').doc(uid);
        final profileDoc = await profileRef.get();
        if (!profileDoc.exists) continue;

        final profile = profileDoc.data()!;
        final currentSeasonPts = (profile['seasonPoints'] ?? 0) as int;
        final currentTotalPts = (profile['totalPoints'] ?? 0) as int;
        final currentWins = (profile['wins'] ?? 0) as int;
        final currentLosses = (profile['losses'] ?? 0) as int;

        final newSeasonPts = (currentSeasonPts + r.points).clamp(0, 999999);
        final newTotalPts = currentTotalPts + r.points;

        final updates = <String, dynamic>{
          'seasonPoints': newSeasonPts,
          'totalPoints': newTotalPts,
          'lastUpdated': DateTime.now().toIso8601String(),
        };

        if (isWinner) {
          updates['wins'] = currentWins + 1;
        } else if (isLoser) {
          updates['losses'] = currentLosses + 1;
        }

        // Recalculate tier from new season points
        updates['tier'] = _tierFromPoints(newSeasonPts);

        // Track best week ROI
        final bestROI = (profile['bestWeekROI'] ?? 0).toDouble();
        if (r.pctChange > bestROI) {
          updates['bestWeekROI'] = r.pctChange;
        }

        batch.update(profileRef, updates);
      }

      await batch.commit();
      debugPrint('MatchScoring: Ranking points awarded for $matchId');
    } catch (e, st) {
      debugPrint('MatchScoring: ERROR scoring $matchId: $e');
      debugPrint('MatchScoring: $st');
    }
  }

  // ── Check expired matches ──────────────

  /// Query all active matches and score any whose endDate has passed.
  Future<void> checkExpiredMatches() async {
    try {
      final snap = await _db
          .collection('challenges')
          .where('status', isEqualTo: 'active')
          .get();

      final now = DateTime.now();
      int scored = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final endDate = _parseEndDate(data);
        if (endDate == null) continue;

        if (now.isAfter(endDate)) {
          debugPrint('MatchScoring: Match ${doc.id} expired (end: $endDate)');
          await scoreMatch(doc.id);
          scored++;
        }
      }

      debugPrint('MatchScoring: checkExpiredMatches — scored $scored/${snap.docs.length} active matches');
    } catch (e) {
      debugPrint('MatchScoring: ERROR in checkExpiredMatches: $e');
    }
  }

  /// Compute end date from startDate + duration.
  DateTime? _parseEndDate(Map<String, dynamic> data) {
    DateTime? start;
    final raw = data['startDate'];
    if (raw is Timestamp) {
      start = raw.toDate();
    } else if (raw is String) {
      start = DateTime.tryParse(raw);
    }
    if (start == null) return null;

    final duration = data['duration'] as String? ?? '1week';
    return duration == '1day'
        ? start.add(const Duration(days: 1))
        : start.add(const Duration(days: 7));
  }

  /// Map season points to tier name string.
  static String _tierFromPoints(int pts) {
    if (pts >= 4000) return 'champion';
    if (pts >= 3000) return 'diamond';
    if (pts >= 2000) return 'gold';
    if (pts >= 1000) return 'silver';
    return 'bronze';
  }

  // ── Lifecycle ──────────────────────────

  /// Start the periodic expired-match checker.
  /// Runs immediately, then every 15 minutes.
  void startPeriodicCheck() {
    // Run once immediately
    checkExpiredMatches();
    // Then every 15 minutes
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => checkExpiredMatches(),
    );
    debugPrint('MatchScoring: Periodic check started (every 15 min)');
  }

  /// Stop the periodic checker.
  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}

// ── Internal helper ──────────────────────

class _PlayerResult {
  final String uid;
  final double costBasis;
  final double currentValue;
  final double pctChange;
  final int points;
  final List<Map<String, dynamic>> holdings;

  _PlayerResult({
    required this.uid,
    required this.costBasis,
    required this.currentValue,
    required this.pctChange,
    required this.points,
    required this.holdings,
  });
}
