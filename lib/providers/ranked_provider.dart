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
  bool isLoading = false;
  bool isMatchmaking = false;
  int matchmakingPlayerCount = 1;
  String matchmakingStatus = 'Searching...';
  StreamSubscription? _mmSub;

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get username => FirebaseAuth.instance.currentUser?.displayName ?? 'Player';

  Future<void> load() async {
    if (uid.isEmpty) return;
    isLoading = true; notifyListeners();
    await Future.wait([_loadMyProfile(), _loadCurrentSeason(), _loadLeaderboard()]);
    isLoading = false; notifyListeners();
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

  @override
  void dispose() { _mmSub?.cancel(); super.dispose(); }
}
