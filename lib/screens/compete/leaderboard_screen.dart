import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────
// GLOBAL LEADERBOARD SCREEN
// Paginated, filterable by tier, with
// current-user header and medal icons.
// ─────────────────────────────────────────

Color _tierColor(RankTier tier) {
  switch (tier) {
    case RankTier.bronze:
      return const Color(0xFFCD7F32);
    case RankTier.silver:
      return const Color(0xFFA8B8C8);
    case RankTier.gold:
      return AppTheme.gold;
    case RankTier.diamond:
      return AppTheme.blue;
    case RankTier.champion:
      return AppTheme.purple;
  }
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // Filter
  int _selectedTab = 0; // 0=All, 1=bronze, ..., 5=champion
  static const _tabLabels = ['All', 'Bronze', 'Silver', 'Gold', 'Diamond', 'Champion'];
  RankTier? get _tierFilter =>
      _selectedTab == 0 ? null : RankTier.values[_selectedTab - 1];

  // Pagination state
  final List<_LeaderboardRow> _rows = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  static const _pageSize = 20;

  // Current user info (loaded once)
  int? _myRank;
  int _myPoints = 0;
  RankTier _myTier = RankTier.bronze;
  String _myName = '';

  @override
  void initState() {
    super.initState();
    _loadMyRank();
    _loadPage();
  }

  // ── Load current user's global rank ────

  Future<void> _loadMyRank() async {
    if (_uid.isEmpty) return;
    try {
      final myDoc = await _db.collection('rankedProfiles').doc(_uid).get();
      if (!myDoc.exists || !mounted) return;
      final data = myDoc.data()!;
      final pts = (data['seasonPoints'] ?? 0) as int;

      // Count players with more points to derive rank
      final above = await _db
          .collection('rankedProfiles')
          .where('seasonPoints', isGreaterThan: pts)
          .count()
          .get();

      if (!mounted) return;
      setState(() {
        _myPoints = pts;
        _myTier = RankTierExt.fromPoints(pts);
        _myName = data['username'] ?? '';
        _myRank = (above.count ?? 0) + 1;
      });
    } catch (_) {}
  }

  // ── Paginated Firestore query ──────────

  Future<void> _loadPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      Query q = _db
          .collection('rankedProfiles')
          .orderBy('seasonPoints', descending: true);

      if (_tierFilter != null) {
        q = q.where('tier', isEqualTo: _tierFilter!.name);
      }
      if (_lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }
      q = q.limit(_pageSize);

      final snap = await q.get();
      if (!mounted) return;

      final startRank = _rows.length + 1;
      final newRows = snap.docs.asMap().entries.map((e) {
        final data = e.value.data() as Map<String, dynamic>;
        return _LeaderboardRow(
          uid: e.value.id,
          username: data['username'] ?? '',
          points: (data['seasonPoints'] ?? 0) as int,
          tier: RankTierExt.fromPoints((data['seasonPoints'] ?? 0) as int),
          wins: (data['wins'] ?? 0) as int,
          losses: (data['losses'] ?? 0) as int,
          rank: startRank + e.key,
        );
      }).toList();

      setState(() {
        _rows.addAll(newRows);
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onTabChanged(int index) {
    if (index == _selectedTab) return;
    setState(() {
      _selectedTab = index;
      _rows.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    _loadPage();
  }

  // ── Build ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global Leaderboard')),
      body: Column(children: [
        // ── My rank header ──
        if (_myRank != null) _buildMyHeader(),

        // ── Tier filter tabs ──
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: _tabLabels.length,
            itemBuilder: (_, i) {
              final active = i == _selectedTab;
              final label = i == 0
                  ? _tabLabels[i]
                  : '${RankTier.values[i - 1].emoji} ${_tabLabels[i]}';
              return GestureDetector(
                onTap: () => _onTabChanged(i),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.greenDim : AppTheme.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: active
                            ? AppTheme.green.withValues(alpha: 0.25)
                            : AppTheme.border),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Courier',
                          color:
                              active ? AppTheme.green : AppTheme.textMuted)),
                ),
              );
            },
          ),
        ),

        // ── Leaderboard list ──
        Expanded(
          child: _rows.isEmpty && _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.green, strokeWidth: 2))
              : _rows.isEmpty
                  ? const Center(
                      child: Text('No players found',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 13)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _rows.length + (_hasMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _rows.length) {
                          return _buildLoadMore();
                        }
                        return _buildRow(_rows[i]);
                      },
                    ),
        ),
      ]),
    );
  }

  // ── My rank header ─────────────────────

  Widget _buildMyHeader() {
    final c = _tierColor(_myTier);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        // Rank position
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text('#$_myRank',
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.green)),
          ),
        ),
        const SizedBox(width: 12),
        // Name + tier badge
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_myName.isNotEmpty ? _myName : 'You',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.green)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: c.withValues(alpha: 0.25)),
              ),
              child: Text('${_myTier.emoji} ${_myTier.label}',
                  style: TextStyle(
                      fontSize: 9,
                      color: c,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        // Points
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$_myPoints',
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.green)),
          const Text('pts',
              style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'Courier',
                  color: AppTheme.textMuted)),
        ]),
      ]),
    );
  }

  // ── Leaderboard row ────────────────────

  Widget _buildRow(_LeaderboardRow row) {
    final isMe = row.uid == _uid;
    final c = _tierColor(row.tier);

    // Medal icon for top 3
    Widget? medalIcon;
    Color rankColor = AppTheme.textMuted;
    if (row.rank == 1) {
      rankColor = AppTheme.gold;
      medalIcon =
          Icon(Icons.emoji_events, size: 16, color: AppTheme.gold);
    } else if (row.rank == 2) {
      rankColor = const Color(0xFFA8B8C8);
      medalIcon =
          Icon(Icons.emoji_events, size: 16, color: const Color(0xFFA8B8C8));
    } else if (row.rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      medalIcon =
          Icon(Icons.emoji_events, size: 16, color: const Color(0xFFCD7F32));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.green.withValues(alpha: 0.05)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isMe
                ? AppTheme.green.withValues(alpha: 0.18)
                : AppTheme.border),
      ),
      child: Row(children: [
        // Rank number + medal
        SizedBox(
          width: 36,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (medalIcon != null) ...[
              medalIcon,
              const SizedBox(width: 2),
            ] else
              Text('#${row.rank}',
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: rankColor)),
          ]),
        ),
        // Avatar
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isMe
                ? AppTheme.green.withValues(alpha: 0.15)
                : AppTheme.surface2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(
            child: Text(
                row.username
                    .substring(0, math.min(2, row.username.length))
                    .toUpperCase(),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isMe ? AppTheme.green : AppTheme.textPrimary)),
          ),
        ),
        const SizedBox(width: 10),
        // Name
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.username,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isMe ? AppTheme.green : AppTheme.textPrimary)),
            if (isMe)
              const Text('<- you',
                  style: TextStyle(
                      fontSize: 9,
                      color: AppTheme.green,
                      fontFamily: 'Courier')),
          ]),
        ),
        // Tier badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.withValues(alpha: 0.2)),
          ),
          child: Text(row.tier.emoji, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        // Points
        Text('${row.points}',
            style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Load More button ───────────────────

  Widget _buildLoadMore() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: AppTheme.green, strokeWidth: 2))
            : GestureDetector(
                onTap: _loadPage,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Text('Load More',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.green)),
                ),
              ),
      ),
    );
  }
}

// ── Row data model ───────────────────────

class _LeaderboardRow {
  final String uid;
  final String username;
  final int points;
  final RankTier tier;
  final int wins;
  final int losses;
  final int rank;

  _LeaderboardRow({
    required this.uid,
    required this.username,
    required this.points,
    required this.tier,
    required this.wins,
    required this.losses,
    required this.rank,
  });
}
