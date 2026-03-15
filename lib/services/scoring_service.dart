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

    try {
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
    debugPrint('ScoringService: Loaded ${allPicks.length} picks for league $leagueId');

    // ── 2. Group picks by player UID ──
    final Map<String, List<DraftPick>> picksByPlayer = {};
    for (final pick in allPicks) {
      picksByPlayer.putIfAbsent(pick.pickedByUID, () => []).add(pick);
    }
    debugPrint('ScoringService: ${picksByPlayer.length} players with picks');

    // ── 3. Fetch current prices for all unique symbols ──
    final uniqueSymbols = allPicks.map((p) => p.symbol).toSet();
    final Map<String, double> currentPrices = {};
    for (final symbol in uniqueSymbols) {
      try {
        final quote = await _stockService.fetchQuote(symbol);
        if (quote != null) {
          currentPrices[symbol] = quote.currentPrice;
        } else {
          debugPrint('ScoringService: WARNING — fetchQuote returned null for $symbol');
        }
      } catch (e) {
        debugPrint('ScoringService: ERROR fetching quote for $symbol: $e');
      }
    }
    debugPrint('ScoringService: Fetched prices for ${currentPrices.length}/${uniqueSymbols.length} symbols');

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
      debugPrint('ScoringService: Player ${picks.first.pickedByUsername} — '
          'value: \$${portfolioValue.toStringAsFixed(2)}, '
          'cost: \$${costBasis.toStringAsFixed(2)}, '
          'pct: ${pctChange.toStringAsFixed(4)}%, '
          'pts: $points');

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
    } catch (e, st) {
      debugPrint('ScoringService: FATAL ERROR in scoreWeek(): $e');
      debugPrint('ScoringService: Stack trace:\n$st');
      rethrow;
    }
  }

  // ══════════════════════════════════════
  // SCHEDULE GENERATION
  // ══════════════════════════════════════

  /// Generate the full season schedule (regular season + playoff placeholders).
  /// Returns all matchup maps and writes them to Firestore.
  static Future<List<Map<String, dynamic>>> generateFullSchedule({
    required List<String> memberUIDs,
    required Map<String, String> usernames,
    required String leagueId,
    required int totalWeeks,
    required int playoffTeams,
    required double startingBalance,
  }) async {
    final db = FirebaseFirestore.instance;
    final matchups = <Map<String, dynamic>>[];

    // ── Round-robin regular season ──
    final players = List<String>.from(memberUIDs);
    final n = players.length;
    // If odd, add a "BYE" placeholder
    final hasBye = n.isOdd;
    if (hasBye) players.add('BYE');
    final total = players.length;
    final half = total ~/ 2;

    // Circle method: fix player[0], rotate the rest
    final rotating = players.sublist(1);

    for (int week = 1; week <= totalWeeks; week++) {
      final pairs = <List<String>>[];

      // Pair first with last, second with second-to-last, etc.
      pairs.add([players[0], rotating[rotating.length - 1]]);
      for (int i = 1; i < half; i++) {
        pairs.add([rotating[i - 1], rotating[rotating.length - 1 - i]]);
      }

      for (final pair in pairs) {
        // Skip BYE matchups
        if (pair[0] == 'BYE' || pair[1] == 'BYE') continue;

        final homeUID = pair[0];
        final awayUID = pair[1];
        matchups.add({
          'leagueId': leagueId,
          'week': week,
          'homeUID': homeUID,
          'awayUID': awayUID,
          'homeUsername': usernames[homeUID] ?? 'Player',
          'awayUsername': usernames[awayUID] ?? 'Player',
          'homeValue': startingBalance,
          'awayValue': startingBalance,
          'isPlayoff': false,
          'playoffRound': null,
          'playoffSeed': null,
          'winnerId': null,
        });
      }

      // Rotate: move last element to the front
      rotating.insert(0, rotating.removeLast());
    }

    // ── Playoff placeholders ──
    List<String> rounds;
    if (playoffTeams >= 8) {
      rounds = ['quarterfinal', 'semifinal', 'championship'];
    } else if (playoffTeams >= 4) {
      rounds = ['semifinal', 'championship'];
    } else {
      rounds = ['championship'];
    }

    int matchesInRound = playoffTeams ~/ 2;
    for (int r = 0; r < rounds.length; r++) {
      final week = totalWeeks + r + 1;
      for (int m = 0; m < matchesInRound; m++) {
        matchups.add({
          'leagueId': leagueId,
          'week': week,
          'homeUID': '',
          'awayUID': '',
          'homeUsername': '',
          'awayUsername': '',
          'homeValue': startingBalance,
          'awayValue': startingBalance,
          'isPlayoff': true,
          'playoffRound': rounds[r],
          'playoffSeed': null,
          'winnerId': null,
        });
      }
      matchesInRound = matchesInRound ~/ 2;
      if (matchesInRound < 1) matchesInRound = 1;
    }

    // ── Write to Firestore ──
    final batch = db.batch();
    final matchupsRef =
        db.collection('leagues').doc(leagueId).collection('matchups');
    for (final m in matchups) {
      batch.set(matchupsRef.doc(), m);
    }
    await batch.commit();

    debugPrint('ScoringService: Generated ${matchups.length} matchups '
        '(${matchups.where((m) => !m['isPlayoff']).length} regular + '
        '${matchups.where((m) => m['isPlayoff']).length} playoff) '
        'for league $leagueId');

    return matchups;
  }

  /// Fill in playoff bracket based on final regular season standings.
  /// [rankedMembers] must be sorted by record (wins desc, then totalValue desc).
  static Future<void> seedPlayoffs({
    required String leagueId,
    required List<LeagueMember> rankedMembers,
    required int playoffTeams,
  }) async {
    final db = FirebaseFirestore.instance;

    // Get all playoff matchups
    final snap = await db
        .collection('leagues')
        .doc(leagueId)
        .collection('matchups')
        .where('isPlayoff', isEqualTo: true)
        .orderBy('week')
        .get();

    if (snap.docs.isEmpty) return;

    // Get the first round matchups (lowest week number among playoffs)
    final firstWeek = snap.docs.first.data()['week'] as int;
    final firstRoundDocs =
        snap.docs.where((d) => d.data()['week'] == firstWeek).toList();

    // Seed: #1 vs #N, #2 vs #N-1, etc.
    final qualifiers = rankedMembers.take(playoffTeams).toList();
    final batch = db.batch();

    for (int i = 0; i < firstRoundDocs.length && i < qualifiers.length ~/ 2; i++) {
      final home = qualifiers[i];
      final away = qualifiers[qualifiers.length - 1 - i];
      batch.update(firstRoundDocs[i].reference, {
        'homeUID': home.id,
        'awayUID': away.id,
        'homeUsername': home.username,
        'awayUsername': away.username,
        'playoffSeed': i + 1,
      });
    }

    await batch.commit();
    debugPrint('ScoringService: Seeded ${firstRoundDocs.length} '
        'first-round playoff matchups for league $leagueId');
  }

  /// Advance winners from a completed playoff week into the next round.
  /// [completedWeek] is the week number that just finished.
  /// Reads matchups for that week, determines winners by portfolio value,
  /// and writes them into the next week's empty matchup slots.
  static Future<void> advancePlayoffWinners({
    required String leagueId,
    required int completedWeek,
  }) async {
    final db = FirebaseFirestore.instance;
    final matchupsRef =
        db.collection('leagues').doc(leagueId).collection('matchups');

    // Get completed week's playoff matchups
    final completedSnap = await matchupsRef
        .where('week', isEqualTo: completedWeek)
        .where('isPlayoff', isEqualTo: true)
        .get();

    if (completedSnap.docs.isEmpty) return;

    // Determine winners (higher portfolio value wins)
    final winners = <Map<String, String>>[];
    final batch = db.batch();

    for (final doc in completedSnap.docs) {
      final data = doc.data();
      final homeValue = (data['homeValue'] ?? 0).toDouble();
      final awayValue = (data['awayValue'] ?? 0).toDouble();
      final homeUID = data['homeUID'] as String? ?? '';
      final awayUID = data['awayUID'] as String? ?? '';

      if (homeUID.isEmpty || awayUID.isEmpty) continue;

      String winnerUID;
      String winnerUsername;
      if (homeValue >= awayValue) {
        winnerUID = homeUID;
        winnerUsername = data['homeUsername'] as String? ?? '';
      } else {
        winnerUID = awayUID;
        winnerUsername = data['awayUsername'] as String? ?? '';
      }

      // Mark winner on the completed matchup
      batch.update(doc.reference, {'winnerId': winnerUID});
      winners.add({'uid': winnerUID, 'username': winnerUsername});
    }

    // Get next week's playoff matchups
    final nextWeek = completedWeek + 1;
    final nextSnap = await matchupsRef
        .where('week', isEqualTo: nextWeek)
        .where('isPlayoff', isEqualTo: true)
        .get();

    // Fill in next round: pair winners in order (winner of match 1 vs winner of match 2, etc.)
    if (nextSnap.docs.isNotEmpty && winners.length >= 2) {
      for (int i = 0; i < nextSnap.docs.length && i * 2 + 1 < winners.length; i++) {
        final home = winners[i * 2];
        final away = winners[i * 2 + 1];
        batch.update(nextSnap.docs[i].reference, {
          'homeUID': home['uid'],
          'awayUID': away['uid'],
          'homeUsername': home['username'],
          'awayUsername': away['username'],
        });
      }
    }

    await batch.commit();

    // If no next round matchups exist, this was the championship — check for league completion
    if (nextSnap.docs.isEmpty && winners.isNotEmpty) {
      // Championship winner — update league status
      await db.collection('leagues').doc(leagueId).update({
        'status': 'complete',
        'championUID': winners.first['uid'],
        'championUsername': winners.first['username'],
      });
      debugPrint('ScoringService: League $leagueId complete! '
          'Champion: ${winners.first['username']}');
    } else {
      debugPrint('ScoringService: Advanced ${winners.length} winners '
          'from week $completedWeek to week $nextWeek for league $leagueId');
    }
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
