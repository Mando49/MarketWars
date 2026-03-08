import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class RankedProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  RankedProfile? myProfile;
  Season? currentSeason;
  List<LeaderboardEntry> leaderboard = [];
  List<Challenge> challenges = [];
  bool isLoading = false;
  bool isMatchmaking = false;
  int matchmakingPlayerCount = 1;
  String matchmakingStatus = 'Searching...';
  StreamSubscription? _mmSub;
  StreamSubscription? _challengeSub;

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get username => FirebaseAuth.instance.currentUser?.displayName ?? 'Player';

  Future<void> load() async {
    if (uid.isEmpty) { isLoading = false; notifyListeners(); return; }
    isLoading = true; notifyListeners();
    try {
      await Future.wait([_loadMyProfile(), _loadCurrentSeason(), _loadLeaderboard(), loadChallenges()]);
    } catch (e) {
      debugPrint('RankedProvider.load() error: $e');
    }
    isLoading = false; notifyListeners();
    _listenChallenges();
  }

  Future<void> _loadMyProfile() async {
    final doc = await _db.collection('rankedProfiles').doc(uid).get();
    if (doc.exists) {
      myProfile = RankedProfile.fromMap(doc.data()!, uid);
    } else {
      myProfile = RankedProfile(
        uid: uid, username: username, totalPoints: 0, seasonPoints: 0,
        globalRank: 9999, wins: 0, losses: 0, leagueWins: 0, bestWeekROI: 0,
        seasonId: currentSeason?.id ?? 'season_3', lastUpdated: DateTime.now(),
      );
      await _db.collection('rankedProfiles').doc(uid).set(myProfile!.toMap());
    }
  }

  Future<void> _loadCurrentSeason() async {
    final snap = await _db.collection('seasons').where('isActive', isEqualTo: true).limit(1).get();
    if (snap.docs.isNotEmpty) currentSeason = Season.fromMap(snap.docs.first.data(), snap.docs.first.id);
  }

  Future<void> _loadLeaderboard({RankTier? tier}) async {
    Query q = _db.collection('rankedProfiles').orderBy('seasonPoints', descending: true).limit(100);
    if (tier != null) q = q.where('tier', isEqualTo: tier.name);
    final snap = await q.get();
    leaderboard = snap.docs.asMap().entries.map((e) {
      final entry = LeaderboardEntry.fromMap(e.value.data() as Map<String, dynamic>, e.value.id);
      return LeaderboardEntry(
        uid: entry.uid, username: entry.username, rank: e.key + 1,
        points: entry.points, pointsDelta: entry.pointsDelta,
        tier: entry.tier, wins: entry.wins, losses: entry.losses,
      );
    }).toList();
    notifyListeners();
  }

  Future<void> filterLeaderboard(RankTier? tier) => _loadLeaderboard(tier: tier);

  Stream<List<LeaderboardEntry>> leaderboardStream() {
    return _db.collection('rankedProfiles').orderBy('seasonPoints', descending: true).limit(100)
        .snapshots().map((s) => s.docs.asMap().entries.map((e) {
          final entry = LeaderboardEntry.fromMap(e.value.data(), e.value.id);
          return LeaderboardEntry(uid: entry.uid, username: entry.username, rank: e.key + 1,
            points: entry.points, pointsDelta: entry.pointsDelta, tier: entry.tier,
            wins: entry.wins, losses: entry.losses);
        }).toList());
  }

  Future<void> addPoints(int points, {bool wonMatchup = false, bool wonLeague = false}) async {
    if (uid.isEmpty || myProfile == null) return;
    myProfile!.seasonPoints = (myProfile!.seasonPoints + points).clamp(0, 999999);
    myProfile!.totalPoints += points.clamp(0, 999999);
    if (wonMatchup) myProfile!.wins++;
    if (!wonMatchup && points < 0) myProfile!.losses++;
    if (wonLeague) myProfile!.leagueWins++;
    myProfile!.lastUpdated = DateTime.now();
    await _db.collection('rankedProfiles').doc(uid).update({
      'seasonPoints': myProfile!.seasonPoints, 'totalPoints': myProfile!.totalPoints,
      'wins': myProfile!.wins, 'losses': myProfile!.losses,
      'leagueWins': myProfile!.leagueWins, 'tier': myProfile!.tier.name,
      'lastUpdated': DateTime.now(),
    });
    notifyListeners();
  }

  Future<void> startQuickMatch() async {
    if (uid.isEmpty || myProfile == null) return;
    isMatchmaking = true;
    matchmakingPlayerCount = 1;
    matchmakingStatus = 'Finding ${myProfile!.tier.label} players...';
    notifyListeners();

    await _db.collection('matchmaking').doc(uid).set(MatchmakingRequest(
      uid: uid, username: username, tier: myProfile!.tier,
      createdAt: DateTime.now(), status: 'searching',
    ).toMap());

    _mmSub = _db.collection('matchmaking')
        .where('tier', isEqualTo: myProfile!.tier.name)
        .where('status', isEqualTo: 'searching')
        .snapshots().listen((snap) {
      matchmakingPlayerCount = snap.docs.length;
      matchmakingStatus = matchmakingPlayerCount >= 6
          ? 'Almost there — filling last spots...'
          : 'Finding ${myProfile!.tier.label} players...';
      notifyListeners();
      if (matchmakingPlayerCount >= 8) _finalizeMatch(snap.docs.map((d) => d.id).toList());
    });
  }

  Future<void> _finalizeMatch(List<String> playerUIDs) async {
    _mmSub?.cancel();
    final batch = _db.batch();
    final leagueId = _db.collection('leagues').doc().id;
    for (final p in playerUIDs) {
      batch.update(_db.collection('matchmaking').doc(p), {'status': 'matched', 'leagueId': leagueId});
    }
    await batch.commit();
    isMatchmaking = false;
    matchmakingStatus = 'Match found!';
    await addPoints(PointsSystem.quickMatchBonus);
    notifyListeners();
  }

  Future<void> cancelMatchmaking() async {
    _mmSub?.cancel();
    await _db.collection('matchmaking').doc(uid).update({'status': 'cancelled'});
    isMatchmaking = false;
    matchmakingPlayerCount = 1;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> fetchPublicLeagues({
    RankTier? tier, bool openSpotsOnly = false, bool withDraft = false, int? weekLength,
  }) async {
    Query q = _db.collection('leagues').where('isPublic', isEqualTo: true)
        .where('status', isEqualTo: 'pending').limit(20);
    if (tier != null) q = q.where('tier', isEqualTo: tier.name);
    if (weekLength != null) q = q.where('totalWeeks', isEqualTo: weekLength);
    final snap = await q.get();
    final leagues = snap.docs.map((d) { final m = d.data() as Map<String, dynamic>; m['id'] = d.id; return m; }).toList();
    if (openSpotsOnly) return leagues.where((l) => (l['members'] as List).length < (l['maxPlayers'] as int)).toList();
    return leagues;
  }

  // ── 1v1 CHALLENGES ──

  Future<void> loadChallenges() async {
    if (uid.isEmpty) return;
    // Challenges where I'm challenger or opponent
    final snap1 = await _db.collection('challenges')
        .where('challengerUID', isEqualTo: uid)
        .orderBy('createdAt', descending: true).limit(50).get();
    final snap2 = await _db.collection('challenges')
        .where('opponentUID', isEqualTo: uid)
        .orderBy('createdAt', descending: true).limit(50).get();
    final Map<String, Challenge> map = {};
    for (final d in snap1.docs) map[d.id] = Challenge.fromMap(d.data(), d.id);
    for (final d in snap2.docs) map[d.id] = Challenge.fromMap(d.data(), d.id);
    challenges = map.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  void _listenChallenges() {
    _challengeSub?.cancel();
    if (uid.isEmpty) return;
    // Listen to challenges involving me
    _challengeSub = _db.collection('challenges')
        .where('challengerUID', isEqualTo: uid)
        .snapshots().listen((_) => loadChallenges());
    // Also listen as opponent
    _db.collection('challenges')
        .where('opponentUID', isEqualTo: uid)
        .snapshots().listen((_) => loadChallenges());
  }

  List<Challenge> get pendingIncoming => challenges
      .where((c) => c.status == ChallengeStatus.pending && c.opponentUID == uid)
      .toList();

  List<Challenge> get pendingOutgoing => challenges
      .where((c) => c.status == ChallengeStatus.pending && c.challengerUID == uid)
      .toList();

  List<Challenge> get activeChallenges => challenges
      .where((c) => c.status == ChallengeStatus.active || c.status == ChallengeStatus.picking)
      .toList();

  List<Challenge> get completedChallenges => challenges
      .where((c) => c.status == ChallengeStatus.complete)
      .toList();

  /// Find a user by email or phone number. Returns {uid, username} or null.
  Future<Map<String, String>?> findUserByContact(String contact) async {
    // Try email first
    final byEmail = await _db.collection('users')
        .where('email', isEqualTo: contact.trim().toLowerCase())
        .limit(1).get();
    if (byEmail.docs.isNotEmpty) {
      final d = byEmail.docs.first;
      return {'uid': d.id, 'username': d.data()['username'] ?? 'Player'};
    }
    // Try phone
    final byPhone = await _db.collection('users')
        .where('phone', isEqualTo: contact.trim())
        .limit(1).get();
    if (byPhone.docs.isNotEmpty) {
      final d = byPhone.docs.first;
      return {'uid': d.id, 'username': d.data()['username'] ?? 'Player'};
    }
    return null;
  }

  /// Create a new 1v1 challenge.
  Future<String?> createChallenge({
    required String opponentUID,
    required String opponentUsername,
    required String opponentContact,
    required String duration,
    required int rosterSize,
  }) async {
    if (uid.isEmpty) return 'Not signed in';
    if (opponentUID == uid) return 'You cannot challenge yourself';

    final docRef = _db.collection('challenges').doc();
    final challenge = Challenge(
      id: docRef.id,
      challengerUID: uid,
      challengerUsername: username,
      opponentUID: opponentUID,
      opponentUsername: opponentUsername,
      opponentContact: opponentContact,
      duration: duration,
      rosterSize: rosterSize,
      status: ChallengeStatus.pending,
      createdAt: DateTime.now(),
    );
    await docRef.set(challenge.toMap());
    challenges.insert(0, challenge);
    notifyListeners();
    return null; // success
  }

  /// Accept a challenge — moves to picking status.
  Future<void> acceptChallenge(String challengeId) async {
    await _db.collection('challenges').doc(challengeId).update({
      'status': ChallengeStatus.picking.name,
    });
    final idx = challenges.indexWhere((c) => c.id == challengeId);
    if (idx >= 0) challenges[idx].status = ChallengeStatus.picking;
    notifyListeners();
  }

  /// Decline a challenge.
  Future<void> declineChallenge(String challengeId) async {
    await _db.collection('challenges').doc(challengeId).delete();
    challenges.removeWhere((c) => c.id == challengeId);
    notifyListeners();
  }

  /// Submit picks for a challenge. If both players have picked, move to active.
  Future<String?> submitPicks(String challengeId, List<Map<String, dynamic>> picks) async {
    if (uid.isEmpty) return 'Not signed in';
    final idx = challenges.indexWhere((c) => c.id == challengeId);
    if (idx < 0) return 'Challenge not found';
    final challenge = challenges[idx];

    final isChallenger = challenge.challengerUID == uid;
    final picksField = isChallenger ? 'challengerPicks' : 'opponentPicks';
    final costField = isChallenger ? 'challengerCost' : 'opponentCost';
    final valueField = isChallenger ? 'challengerValue' : 'opponentValue';

    final totalCost = picks.fold<double>(0, (s, p) => s + (p['priceAtPick'] as double));

    final updates = <String, dynamic>{
      picksField: picks,
      costField: totalCost,
      valueField: totalCost, // Initially value = cost
    };

    // Check if the other player already submitted picks
    final doc = await _db.collection('challenges').doc(challengeId).get();
    final data = doc.data()!;
    final otherPicks = isChallenger
        ? List.from(data['opponentPicks'] ?? [])
        : List.from(data['challengerPicks'] ?? []);

    if (otherPicks.isNotEmpty) {
      // Both players have picked — go active
      updates['status'] = ChallengeStatus.active.name;
      updates['startDate'] = DateTime.now().toIso8601String();
    }

    await _db.collection('challenges').doc(challengeId).update(updates);
    await loadChallenges();
    return null;
  }

  @override
  void dispose() { _mmSub?.cancel(); _challengeSub?.cancel(); super.dispose(); }
}
