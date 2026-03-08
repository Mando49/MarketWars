import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class LeagueProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<League> leagues = [];
  Map<String, List<LeagueMember>> members = {};
  Map<String, Matchup?> currentMatchups = {};
  bool isLoading = false;
  String errorMessage = '';

  String get uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get username => FirebaseAuth.instance.currentUser?.displayName ?? 'Player';

  Future<void> loadLeagues() async {
    if (uid.isEmpty) return;
    isLoading = true; notifyListeners();
    final snap = await _db.collection('leagues').where('members', arrayContains: uid).get();
    leagues = snap.docs.map((d) => League.fromMap(d.data(), d.id)).toList();
    for (final l in leagues) {
      await _loadMembers(l.id);
      await _loadMyMatchup(l);
    }
    isLoading = false; notifyListeners();
  }

  Future<void> _loadMembers(String leagueId) async {
    final snap = await _db.collection('leagues').doc(leagueId)
        .collection('members').orderBy('totalValue', descending: true).get();
    members[leagueId] = snap.docs.map((d) => LeagueMember.fromMap(d.data(), d.id)).toList();
  }

  Future<void> _loadMyMatchup(League league) async {
    final snap = await _db.collection('leagues').doc(league.id)
        .collection('matchups').where('week', isEqualTo: league.currentWeek).get();
    final all = snap.docs.map((d) => Matchup.fromMap(d.data(), d.id)).toList();
    currentMatchups[league.id] = all.firstWhere(
      (m) => m.homeUID == uid || m.awayUID == uid,
      orElse: () => all.isNotEmpty ? all.first : Matchup(
        id: '', leagueId: league.id, week: league.currentWeek,
        homeUID: uid, awayUID: '', homeValue: league.startingBalance,
        awayValue: league.startingBalance,
        homeUsername: username, awayUsername: 'TBD', isPlayoff: false,
      ),
    );
  }

  Future<League?> createLeague({
    required String name, required bool isPublic,
    required int maxPlayers, required int totalWeeks,
    String draftMode = 'unique', // 'unique' or 'open'
  }) async {
    final code = _generateCode();
    final leagueId = _db.collection('leagues').doc().id;
    final league = League(
      id: leagueId, name: name, commissionerUID: uid,
      inviteCode: code, isPublic: isPublic, maxPlayers: maxPlayers,
      currentWeek: 0, totalWeeks: totalWeeks, playoffWeeks: 3,
      playoffTeams: 4, status: LeagueStatus.pending,
      createdAt: DateTime.now(), members: [uid],
      draftMode: draftMode,
    );
    await _db.collection('leagues').doc(leagueId).set(league.toMap());
    final bal = league.startingBalance;
    final member = LeagueMember(
      id: uid, username: username, leagueId: leagueId,
      wins: 0, losses: 0, totalValue: bal,
      cashBalance: bal, seed: 1, isEliminated: false,
    );
    await _db.collection('leagues').doc(leagueId).collection('members').doc(uid).set(member.toMap());
    await _db.collection('leagueCodes').doc(code).set({'leagueId': leagueId});
    leagues.insert(0, league);
    members[leagueId] = [member];
    notifyListeners();
    return league;
  }

  Future<String?> joinLeague(String code) async {
    final codeDoc = await _db.collection('leagueCodes').doc(code.toUpperCase()).get();
    if (!codeDoc.exists) return 'Invalid invite code';
    final leagueId = codeDoc.data()!['leagueId'] as String;
    final leagueDoc = await _db.collection('leagues').doc(leagueId).get();
    if (!leagueDoc.exists) return 'League not found';
    final league = League.fromMap(leagueDoc.data()!, leagueId);
    if (league.members.length >= league.maxPlayers) return 'League is full';
    if (league.status != LeagueStatus.pending) return 'League already started';
    final bal = league.startingBalance;
    final member = LeagueMember(
      id: uid, username: username, leagueId: leagueId,
      wins: 0, losses: 0, totalValue: bal,
      cashBalance: bal,
      seed: league.members.length + 1, isEliminated: false,
    );
    await _db.collection('leagues').doc(leagueId).collection('members').doc(uid).set(member.toMap());
    await _db.collection('leagues').doc(leagueId).update({'members': FieldValue.arrayUnion([uid])});
    leagues.add(league);
    members[leagueId] = [member];
    notifyListeners();
    return null;
  }

  /// Join a league by looking up a pending invite matching the user's
  /// email or phone number across all leagues.
  Future<String?> joinByContact(String contact) async {
    final normalized = contact.trim().toLowerCase();

    // Query all leagues for a pending invite matching this contact
    final leaguesSnap = await _db.collection('leagues').get();

    for (final leagueDoc in leaguesSnap.docs) {
      final invitesSnap = await _db
          .collection('leagues')
          .doc(leagueDoc.id)
          .collection('invites')
          .where('contact', isEqualTo: normalized)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (invitesSnap.docs.isEmpty) {
        // Also try the original casing (phones may have +, etc.)
        final invitesSnap2 = await _db
            .collection('leagues')
            .doc(leagueDoc.id)
            .collection('invites')
            .where('contact', isEqualTo: contact.trim())
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get();
        if (invitesSnap2.docs.isEmpty) continue;
        // Found with original casing
        return _joinFromInvite(leagueDoc.id, invitesSnap2.docs.first.id);
      }

      return _joinFromInvite(leagueDoc.id, invitesSnap.docs.first.id);
    }

    return 'No pending invite found for "$contact"';
  }

  Future<String?> _joinFromInvite(String leagueId, String inviteDocId) async {
    final leagueDoc = await _db.collection('leagues').doc(leagueId).get();
    if (!leagueDoc.exists) return 'League not found';
    final league = League.fromMap(leagueDoc.data()!, leagueId);

    if (league.members.contains(uid)) return 'You are already in this league';
    if (league.members.length >= league.maxPlayers) return 'League is full';
    if (league.status != LeagueStatus.pending) return 'League already started';

    final bal = league.startingBalance;
    final member = LeagueMember(
      id: uid, username: username, leagueId: leagueId,
      wins: 0, losses: 0, totalValue: bal,
      cashBalance: bal,
      seed: league.members.length + 1, isEliminated: false,
    );
    await _db.collection('leagues').doc(leagueId)
        .collection('members').doc(uid).set(member.toMap());
    await _db.collection('leagues').doc(leagueId)
        .update({'members': FieldValue.arrayUnion([uid])});

    // Mark the invite as joined
    await _db.collection('leagues').doc(leagueId)
        .collection('invites').doc(inviteDocId)
        .update({'status': 'joined'});

    leagues.add(league);
    members[leagueId] = [member];
    notifyListeners();
    return null;
  }

  Future<void> deleteLeague(String leagueId) async {
    await _db.collection('leagues').doc(leagueId).delete();
    leagues.removeWhere((l) => l.id == leagueId);
    members.remove(leagueId);
    currentMatchups.remove(leagueId);
    notifyListeners();
  }

  Future<void> leaveLeague(String leagueId) async {
    await _db.collection('leagues').doc(leagueId).update({
      'members': FieldValue.arrayRemove([uid]),
    });
    await _db.collection('leagues').doc(leagueId)
        .collection('members').doc(uid).delete();
    leagues.removeWhere((l) => l.id == leagueId);
    members.remove(leagueId);
    currentMatchups.remove(leagueId);
    notifyListeners();
  }

  Stream<List<LeagueMember>> membersStream(String leagueId) {
    return _db.collection('leagues').doc(leagueId)
        .collection('members').orderBy('totalValue', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => LeagueMember.fromMap(d.data(), d.id)).toList());
  }

  Stream<List<ChatMessage>> chatStream(String leagueId) {
    return _db.collection('leagues').doc(leagueId)
        .collection('chat').orderBy('timestamp').limitToLast(100)
        .snapshots()
        .map((s) => s.docs.map((d) => ChatMessage.fromMap(d.data(), d.id)).toList());
  }

  Future<void> sendMessage(String leagueId, String text) async {
    final id = _db.collection('x').doc().id;
    final msg = ChatMessage(id: id, leagueId: leagueId, senderUID: uid,
        senderUsername: username, text: text, reactions: {}, isSystemEvent: false, timestamp: DateTime.now());
    await _db.collection('leagues').doc(leagueId).collection('chat').doc(id).set(msg.toMap());
  }

  Future<void> postSystemEvent(String leagueId, String text) async {
    final id = _db.collection('x').doc().id;
    final msg = ChatMessage(id: id, leagueId: leagueId, senderUID: 'system',
        senderUsername: 'MarketWars', text: text, reactions: {}, isSystemEvent: true, timestamp: DateTime.now());
    await _db.collection('leagues').doc(leagueId).collection('chat').doc(id).set(msg.toMap());
  }

  Future<void> addReaction(String leagueId, String messageId, String emoji) async {
    await _db.collection('leagues').doc(leagueId).collection('chat').doc(messageId)
        .update({'reactions.$emoji': FieldValue.increment(1)});
  }

  Stream<DocumentSnapshot> draftStream(String leagueId) {
    return _db.collection('leagues').doc(leagueId).collection('draft').doc('state').snapshots();
  }

  /// Stream of all draft picks for the board, ordered by pickNumber
  Stream<List<DraftPick>> draftPicksStream(String leagueId) {
    return _db
        .collection('leagues')
        .doc(leagueId)
        .collection('draft')
        .doc('state')
        .collection('picks')
        .orderBy('pickNumber')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DraftPick.fromMap(d.data(), d.id))
            .toList());
  }

  /// Returns null on success, or an error string if pick is blocked.
  Future<String?> makePick(String leagueId, String symbol, String companyName,
      double price, Map<String, dynamic> state) async {

    // ── Unique draft mode: check if symbol already taken ──
    final draftMode = state['draftMode'] ?? 'unique';
    if (draftMode == 'unique') {
      final existingPicks = await _db
          .collection('leagues').doc(leagueId)
          .collection('draft').doc('state')
          .collection('picks')
          .where('symbol', isEqualTo: symbol)
          .limit(1)
          .get();
      if (existingPicks.docs.isNotEmpty) {
        final pickedBy = existingPicks.docs.first.data()['pickedByUsername'] ?? 'someone';
        return '$symbol was already drafted by $pickedBy';
      }
    }

    final pick = {
      'id': _db.collection('x').doc().id, 'leagueId': leagueId,
      'round': state['currentRound'], 'pickNumber': state['currentPick'],
      'pickedByUID': uid, 'pickedByUsername': username,
      'symbol': symbol, 'companyName': companyName,
      'priceAtDraft': price, 'timestamp': DateTime.now(),
    };
    await _db.collection('leagues').doc(leagueId)
        .collection('draft').doc('state').collection('picks').doc(pick['id'] as String).set(pick);
    final total = (state['pickOrder'] as List).length;
    final nextPick = (state['currentPick'] as int) + 1;
    final nextRound = ((nextPick - 1) ~/ total) + 1;
    final done = nextRound > (state['totalRounds'] as int);
    await _db.collection('leagues').doc(leagueId).collection('draft').doc('state').set({
      'currentPick': nextPick, 'currentRound': nextRound,
      'isComplete': done, 'secondsRemaining': 60,
    }, SetOptions(merge: true));
    await postSystemEvent(leagueId, '🎯 $username drafted $symbol in Round ${state['currentRound']}');
    if (done) {
      final league = leagues.cast<League?>().firstWhere(
          (l) => l!.id == leagueId, orElse: () => null);
      await _db.collection('leagues').doc(leagueId).update({
        'status': 'active',
        'currentWeek': 1,
        'startDate': DateTime.now().toIso8601String(),
        'startingBalance': league?.startingBalance ?? 10000,
      });
      await postSystemEvent(leagueId, '📋 Draft complete! Season Week 1 starts now.');
    }
    return null; // success
  }

  /// Returns all symbols already drafted in this league (for unique mode UI highlighting)
  Future<Set<String>> getDraftedSymbols(String leagueId) async {
    final snap = await _db
        .collection('leagues').doc(leagueId)
        .collection('draft').doc('state')
        .collection('picks')
        .get();
    return snap.docs.map((d) => d.data()['symbol'] as String).toSet();
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rng.nextInt(chars.length))));
  }
}
