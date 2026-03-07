import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'i_stock_service.dart';

class ScoringService {
  final FirebaseFirestore _db;
  final IStockService _stockService;

  ScoringService({
    required IStockService stockService,
    FirebaseFirestore? firestore,
  })  : _stockService = stockService,
        _db = firestore ?? FirebaseFirestore.instance;

  /// Award points based on portfolio percentage change.
  static int pointsForPctChange(double pct) {
    if (pct >= 10) return 100;
    if (pct >= 7) return 75;
    if (pct >= 5) return 50;
    if (pct >= 3) return 35;
    if (pct >= 1) return 20;
    if (pct >= 0) return 10;
    return 5;
  }

  /// Run the weekly scoring engine for a single league.
  ///
  /// 1. Reads all draft picks from /leagues/{leagueId}/draft/state/picks/
  /// 2. Groups picks by player UID
  /// 3. Fetches current stock prices and computes each player's portfolio value
  /// 4. Calculates % change from [league.startingBalance]
  /// 5. Awards ranking points and writes results to
  ///    /leagues/{leagueId}/weeks/{weekNumber}/
  Future<void> scoreWeek(League league, int weekNumber) async {
    final leagueId = league.id;
    final startBal = league.startingBalance;

    // ── 1. Load all draft picks ──
    final picksSnap = await _db
        .collection('leagues')
        .doc(leagueId)
        .collection('draft')
        .doc('state')
        .collection('picks')
        .get();

    if (picksSnap.docs.isEmpty) {
      debugPrint('ScoringService: No picks found for league $leagueId');
      return;
    }

    final allPicks =
        picksSnap.docs.map((d) => DraftPick.fromMap(d.data(), d.id)).toList();

    // ── 2. Group picks by player UID ──
    final Map<String, List<DraftPick>> picksByPlayer = {};
    for (final pick in allPicks) {
      picksByPlayer.putIfAbsent(pick.pickedByUID, () => []).add(pick);
    }

    // ── 3. Fetch current prices for all unique symbols ──
    final uniqueSymbols = allPicks.map((p) => p.symbol).toSet();
    final Map<String, double> currentPrices = {};
    for (final symbol in uniqueSymbols) {
      final quote = await _stockService.fetchQuote(symbol);
      if (quote != null) {
        currentPrices[symbol] = quote.currentPrice;
      }
    }

    // ── 4. Calculate each player's portfolio value & % change ──
    final batch = _db.batch();
    final weekRef = _db
        .collection('leagues')
        .doc(leagueId)
        .collection('weeks')
        .doc('$weekNumber');

    final Map<String, dynamic> weekSummary = {
      'week': weekNumber,
      'scoredAt': FieldValue.serverTimestamp(),
      'leagueId': leagueId,
    };

    final List<Map<String, dynamic>> playerResults = [];

    for (final uid in picksByPlayer.keys) {
      final picks = picksByPlayer[uid]!;

      // Sum current value of all drafted stocks.
      // Each pick represents 1 share bought at priceAtDraft.
      double portfolioValue = 0;
      double costBasis = 0;
      final List<Map<String, dynamic>> holdings = [];

      for (final pick in picks) {
        final price = currentPrices[pick.symbol];
        if (price == null) continue;

        portfolioValue += price;
        costBasis += pick.priceAtDraft;

        holdings.add({
          'symbol': pick.symbol,
          'companyName': pick.companyName,
          'priceAtDraft': pick.priceAtDraft,
          'currentPrice': price,
          'change': price - pick.priceAtDraft,
          'changePct': pick.priceAtDraft > 0
              ? ((price - pick.priceAtDraft) / pick.priceAtDraft) * 100
              : 0.0,
        });
      }

      // % change relative to starting balance
      final pctChange =
          startBal > 0 ? ((portfolioValue - costBasis) / startBal) * 100 : 0.0;
      final points = pointsForPctChange(pctChange);

      final result = {
        'uid': uid,
        'username': picks.first.pickedByUsername,
        'portfolioValue': portfolioValue,
        'costBasis': costBasis,
        'pctChange': double.parse(pctChange.toStringAsFixed(4)),
        'points': points,
        'holdings': holdings,
      };

      playerResults.add(result);

      // Write individual player result as a sub-doc
      batch.set(weekRef.collection('results').doc(uid), result);
    }

    // Rank players by pctChange descending
    playerResults.sort(
        (a, b) => (b['pctChange'] as double).compareTo(a['pctChange'] as double));
    for (int i = 0; i < playerResults.length; i++) {
      playerResults[i]['rank'] = i + 1;
      // Update the sub-doc with rank
      final uid = playerResults[i]['uid'] as String;
      batch.update(weekRef.collection('results').doc(uid), {'rank': i + 1});
    }

    // Write the week summary
    weekSummary['standings'] = playerResults.map((r) => {
          'uid': r['uid'],
          'username': r['username'],
          'pctChange': r['pctChange'],
          'points': r['points'],
          'rank': r['rank'],
          'portfolioValue': r['portfolioValue'],
        }).toList();
    batch.set(weekRef, weekSummary);

    await batch.commit();
    debugPrint(
        'ScoringService: Scored week $weekNumber for league $leagueId — '
        '${playerResults.length} players');
  }

  /// Score all active leagues for their current calculated week.
  Future<void> scoreAllLeagues() async {
    final snap = await _db
        .collection('leagues')
        .where('status', isEqualTo: LeagueStatus.active.name)
        .get();

    for (final doc in snap.docs) {
      final league = League.fromMap(doc.data(), doc.id);
      final week = league.calculatedWeek;

      // Skip if this week was already scored
      final existing = await _db
          .collection('leagues')
          .doc(league.id)
          .collection('weeks')
          .doc('$week')
          .get();
      if (existing.exists) {
        debugPrint(
            'ScoringService: Week $week already scored for ${league.name}');
        continue;
      }

      await scoreWeek(league, week);
    }
  }

  /// Read stored results for a specific week.
  Future<Map<String, dynamic>?> getWeekResults(
      String leagueId, int weekNumber) async {
    final doc = await _db
        .collection('leagues')
        .doc(leagueId)
        .collection('weeks')
        .doc('$weekNumber')
        .get();
    return doc.data();
  }
}
