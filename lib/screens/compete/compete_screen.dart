import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/ranked_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'match_detail_screen.dart';
import 'ranked_screen.dart';
import 'stock_picker_screen.dart';

// ─────────────────────────────────────────
// COMPETE SCREEN  (tab 2)
// ─────────────────────────────────────────
class CompeteScreen extends StatefulWidget {
  const CompeteScreen({super.key});
  @override
  State<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends State<CompeteScreen> {
  bool _timedOut = false;
  int _rankingPoints = 0;
  List<League> _myLeagues = [];
  // Per-league member data for the current user: leagueId -> LeagueMember
  Map<String, LeagueMember> _myMemberData = {};
  bool _wasMatchmaking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ranked = context.read<RankedProvider>();
      _wasMatchmaking = ranked.isMatchmaking;
      ranked.addListener(_checkMatchFound);
      ranked.load().timeout(const Duration(seconds: 5), onTimeout: () {
        if (mounted) ranked.forceStopLoading();
      });
      // Fallback: force show UI after 5s no matter what
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && context.read<RankedProvider>().isLoading) {
          setState(() => _timedOut = true);
        }
      });
      _loadRankingPoints();
      _loadMyLeagues();
    });
  }

  @override
  void dispose() {
    context.read<RankedProvider>().removeListener(_checkMatchFound);
    super.dispose();
  }

  void _checkMatchFound() {
    if (!mounted) return;
    final ranked = context.read<RankedProvider>();
    if (_wasMatchmaking && !ranked.isMatchmaking &&
        ranked.matchmakingStatus == 'Match found!') {
      // Matchmaking just ended with a match — show overlay
      // Use lastMatchedChallenge first (reliable for both players),
      // then fall back to searching the challenges list.
      Challenge? match = ranked.lastMatchedChallenge;
      if (match == null) {
        final picking = ranked.challenges
            .where((c) => c.status == ChallengeStatus.picking)
            .toList();
        if (picking.isNotEmpty) match = picking.first;
      }
      if (match != null) {
        _showMatchFoundBanner(match);
        ranked.lastMatchedChallenge = null; // consume it
      }
    }
    _wasMatchmaking = ranked.isMatchmaking;
  }

  void _showMatchFoundBanner(Challenge challenge) {
    final opponentName = challenge.opponentNameOf(
        FirebaseAuth.instance.currentUser?.uid ?? '');
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => _MatchFoundOverlay(
        opponentName: opponentName,
        onPickStocks: () {
          Navigator.of(context, rootNavigator: true).pop();
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StockPickerScreen(challenge: challenge)));
        },
      ),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _loadRankingPoints() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final pts = doc.data()?['rankingPoints'] as int? ?? 0;
      if (mounted) setState(() => _rankingPoints = pts);
    } catch (_) {}
  }

  Future<void> _loadMyLeagues() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('[Compete] _loadMyLeagues called, uid=$uid');
    if (uid == null || uid.isEmpty) {
      debugPrint('[Compete] _loadMyLeagues: uid is null/empty, returning');
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('leagues')
          .where('members', arrayContains: uid)
          .get();
      debugPrint('[Compete] _loadMyLeagues: found ${snap.docs.length} leagues');
      final leagues =
          snap.docs.map((d) => League.fromMap(d.data(), d.id)).toList();
      // Load member data for current user from each league
      final memberData = <String, LeagueMember>{};
      for (final league in leagues) {
        try {
          final memberDoc = await FirebaseFirestore.instance
              .collection('leagues')
              .doc(league.id)
              .collection('members')
              .doc(uid)
              .get();
          if (memberDoc.exists) {
            memberData[league.id] =
                LeagueMember.fromMap(memberDoc.data()!, memberDoc.id);
          }
        } catch (e) {
          debugPrint('[Compete] Error loading member data for ${league.id}: $e');
        }
      }
      debugPrint('[Compete] _loadMyLeagues: ${leagues.length} leagues, ${memberData.length} member records');
      if (mounted) {
        setState(() {
          _myLeagues = leagues;
          _myMemberData = memberData;
        });
      }
    } catch (e) {
      debugPrint('[Compete] _loadMyLeagues error: $e');
    }
  }

  List<Widget> _buildActiveMatches(RankedProvider ranked) {
    final active = ranked.activeChallenges;
    if (active.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Center(
            child: Text('No active matches yet — start a duel to play!',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                textAlign: TextAlign.center),
          ),
        ),
      ];
    }
    return active
        .map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActiveMatchCard(challenge: c, myUid: ranked.uid),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ranked = context.watch<RankedProvider>();
    final profile = ranked.myProfile;
    final showLoading = ranked.isLoading && !_timedOut;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compete'),
        actions: [
          if (profile != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: TierBadge(tier: profile.tier)),
            ),
        ],
      ),
      body: showLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (profile != null)
                  _RankCard(profile: profile, rankingPoints: _rankingPoints),
                const SizedBox(height: 12),
                _OnlinePlayersBar(ranked: ranked),
                const SizedBox(height: 12),
                _SeasonStatsRow(profile: profile),
                const SizedBox(height: 14),
                if (ranked.isMatchmaking)
                  _MatchmakingCard(ranked: ranked)
                else ...[
                  // Daily Duel
                  _QuickModeButton(
                    emoji: '⚡',
                    title: 'Daily Duel',
                    subtitle: '1 day · 5 stocks · \$10K · Any rank',
                    onTap: () => ranked.startQuickMatch(
                      matchType: 'anyRank',
                      duration: '1day',
                      rosterSize: 5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Weekly War
                  _QuickModeButton(
                    emoji: '🔥',
                    title: 'Weekly War',
                    subtitle: '1 week · 5 stocks · \$10K · Any rank',
                    onTap: () => ranked.startQuickMatch(
                      matchType: 'anyRank',
                      duration: '1week',
                      rosterSize: 5,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // 1v1 Ranked Button
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RankedScreen())),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.purple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppTheme.purple.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                            child: Text('⚔️', style: TextStyle(fontSize: 20))),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('1v1 Ranked',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary)),
                          Text('Customize match settings',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      )),
                      if (ranked.pendingIncoming.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${ranked.pendingIncoming.length}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Courier')),
                        )
                      else
                        const Icon(Icons.arrow_forward_ios,
                            size: 14, color: AppTheme.textMuted),
                    ]),
                  ),
                ),
                // Pending Challenges
                if (ranked.pendingIncoming.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _SectionLabel('Pending Challenges'),
                  const SizedBox(height: 8),
                  ...ranked.pendingIncoming.map((challenge) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person,
                                      size: 16, color: AppTheme.textMuted),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      challenge.challengerUsername,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.purple
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      challenge.duration == '1day'
                                          ? '1 Day'
                                          : '1 Week',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.purple,
                                        fontFamily: 'Courier',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          AppTheme.green.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${challenge.rosterSize} stocks',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.green,
                                        fontFamily: 'Courier',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          ranked.declineChallenge(challenge.id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.red,
                                        side: const BorderSide(
                                            color: AppTheme.red),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                      ),
                                      child: const Text('Decline',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        await ranked
                                            .acceptChallenge(challenge.id);
                                        if (context.mounted) {
                                          Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      StockPickerScreen(
                                                          challenge:
                                                              challenge)));
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.green,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                      ),
                                      child: const Text('Accept',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
                const SizedBox(height: 20),
                const _SectionLabel('Explore'),
                Row(children: [
                  _ExploreCard(
                      icon: '🏆',
                      label: 'Global\nLeaderboard',
                      color: AppTheme.gold,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LeaderboardScreen()))),
                  const SizedBox(width: 8),
                  _ExploreCard(
                      icon: '🌐',
                      label: 'Browse\nLeagues',
                      color: AppTheme.blue,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BrowseLeaguesScreen()))),
                  const SizedBox(width: 8),
                  _ExploreCard(
                      icon: '🎖️',
                      label: 'Season\nRewards',
                      color: AppTheme.purple,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SeasonScreen()))),
                ]),
                const SizedBox(height: 20),
                const _SectionLabel('Active Matches'),
                ..._buildActiveMatches(ranked),
                const SizedBox(height: 20),
                const _SectionLabel('My Leagues'),
                if (_myLeagues.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Center(
                      child: Text('No leagues yet',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ),
                  )
                else
                  ..._myLeagues.map((league) {
                    final member = _myMemberData[league.id];
                    final record = member != null
                        ? '${member.wins}-${member.losses}'
                        : '0-0';
                    final roiPct = member != null
                        ? member.gainLossPercent(league.startingBalance)
                        : 0.0;
                    final roiStr =
                        '${roiPct >= 0 ? '+' : ''}${roiPct.toStringAsFixed(0)}%';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ActiveLeagueCard(
                        name: league.name,
                        type:
                            '${league.isPublic ? 'Public' : 'Private'} · ${league.members.length} players',
                        week: league.calculatedWeek,
                        record: record,
                        rank: member?.seed ?? 0,
                        roi: roiStr,
                        tier: league.tier != null
                            ? RankTierExt.fromPoints(RankTier.values
                                .firstWhere(
                                  (t) => t.name == league.tier,
                                  orElse: () => RankTier.bronze,
                                )
                                .minPoints)
                            : RankTier.bronze,
                        isPrivate: !league.isPublic,
                        status: league.status,
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────
// LEADERBOARD SCREEN
// ─────────────────────────────────────────
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  RankTier? _filter;

  @override
  Widget build(BuildContext context) {
    final ranked = context.watch<RankedProvider>();
    final myUID = ranked.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Leaderboard'),
        actions: const [
          Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child: Text('Season 3',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontFamily: 'Courier'))))
        ],
      ),
      body: Column(children: [
        // Tier filter chips
        SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _FilterChip(
                    label: '🌍 All',
                    active: _filter == null,
                    onTap: () {
                      setState(() => _filter = null);
                      ranked.filterLeaderboard(null);
                    }),
                ...RankTier.values.map((t) => _FilterChip(
                    label: '${t.emoji} ${t.label}',
                    active: _filter == t,
                    onTap: () {
                      setState(() => _filter = t);
                      ranked.filterLeaderboard(t);
                    })),
              ],
            )),
        // Podium top 3
        if (_filter == null && ranked.leaderboard.length >= 3)
          _Podium(top3: ranked.leaderboard.take(3).toList()),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Text('TOP 100 PLAYERS',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontFamily: 'Courier',
                    letterSpacing: 2))
          ]),
        ),
        // List
        Expanded(
          child: StreamBuilder<List<LeaderboardEntry>>(
            stream: ranked.leaderboardStream(),
            builder: (_, snap) {
              final entries = snap.data ?? ranked.leaderboard;
              final filtered = _filter == null
                  ? entries
                  : entries.where((e) => e.tier == _filter).toList();
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) =>
                    _LBRow(entry: filtered[i], isMe: filtered[i].uid == myUID),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────
// BROWSE LEAGUES SCREEN
// ─────────────────────────────────────────
class BrowseLeaguesScreen extends StatefulWidget {
  const BrowseLeaguesScreen({super.key});
  @override
  State<BrowseLeaguesScreen> createState() => _BrowseLeaguesScreenState();
}

class _BrowseLeaguesScreenState extends State<BrowseLeaguesScreen> {
  RankTier? _tierFilter;
  bool _openOnly = false, _withDraft = false;
  int? _weekFilter;
  List<Map<String, dynamic>> _leagues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await context.read<RankedProvider>().fetchPublicLeagues(
        tier: _tierFilter,
        openSpotsOnly: _openOnly,
        withDraft: _withDraft,
        weekLength: _weekFilter);
    if (mounted) {
      setState(() {
        _leagues = results;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Leagues'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
              color: AppTheme.green)
        ],
      ),
      body: Column(children: [
        SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _FilterChip(
                    label: 'All Tiers',
                    active: _tierFilter == null,
                    onTap: () {
                      setState(() => _tierFilter = null);
                      _load();
                    }),
                ...RankTier.values.map((t) => _FilterChip(
                    label: '${t.emoji} ${t.label}',
                    active: _tierFilter == t,
                    onTap: () {
                      setState(() => _tierFilter = t);
                      _load();
                    })),
              ],
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(spacing: 8, children: [
            _ToggleChip(
                label: '🔓 Open Spots',
                active: _openOnly,
                onTap: () {
                  setState(() => _openOnly = !_openOnly);
                  _load();
                }),
            _ToggleChip(
                label: '🎯 With Draft',
                active: _withDraft,
                onTap: () {
                  setState(() => _withDraft = !_withDraft);
                  _load();
                }),
            _ToggleChip(
                label: '📅 8 Weeks',
                active: _weekFilter == 8,
                onTap: () {
                  setState(() => _weekFilter = _weekFilter == 8 ? null : 8);
                  _load();
                }),
            _ToggleChip(
                label: '📅 12 Weeks',
                active: _weekFilter == 12,
                onTap: () {
                  setState(() => _weekFilter = _weekFilter == 12 ? null : 12);
                  _load();
                }),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.green))
              : _leagues.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('🔍', style: TextStyle(fontSize: 44)),
                      SizedBox(height: 12),
                      Text('No leagues found',
                          style: TextStyle(color: AppTheme.textMuted)),
                      Text('Try different filters',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _leagues.length,
                      itemBuilder: (_, i) => _LeagueCard(data: _leagues[i]),
                    ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────
// SEASON SCREEN
// ─────────────────────────────────────────
class SeasonScreen extends StatefulWidget {
  const SeasonScreen({super.key});
  @override
  State<SeasonScreen> createState() => _SeasonScreenState();
}

class _SeasonScreenState extends State<SeasonScreen> {
  int? _rankingPoints;

  @override
  void initState() {
    super.initState();
    _loadRankingPoints();
  }

  Future<void> _loadRankingPoints() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final pts = doc.data()?['rankingPoints'] as int? ?? 0;
      if (mounted) {
        setState(() {
          _rankingPoints = pts;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _rankingPoints = 0;
        });
      }
    }
  }

  double _tierProgress(int pts, RankTier tier) {
    final range = tier.maxPoints - tier.minPoints + 1;
    return ((pts - tier.minPoints) / range).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _rankingPoints ?? 0;
    final tier = RankTierExt.fromPoints(pts);
    final c = tierColor(tier);
    return Scaffold(
      appBar: AppBar(title: const Text('Season Rewards')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Hero — Current Season header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF100820), Color(0xFF080D18)]),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.purple.withValues(alpha: 0.15)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('CURRENT SEASON',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.purple,
                    fontFamily: 'Courier',
                    letterSpacing: 2)),
            const SizedBox(height: 6),
            const Text('Compete in leagues, climb ranks, earn rewards',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontFamily: 'Courier')),
            const SizedBox(height: 14),
            // Your progress
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${tier.emoji} ${tier.label}',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: c)),
                      Text('$pts pts',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Courier',
                              color: c)),
                    ]),
                const SizedBox(height: 8),
                ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                        value: _tierProgress(pts, tier),
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation(c),
                        minHeight: 6)),
                if (tier.next != null) ...[
                  const SizedBox(height: 6),
                  Text(
                      '${tier.next!.minPoints - pts} more points to ${tier.next!.label}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontFamily: 'Courier'),
                      textAlign: TextAlign.center),
                ] else ...[
                  const SizedBox(height: 6),
                  const Text('Max rank reached!',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.purple,
                          fontFamily: 'Courier'),
                      textAlign: TextAlign.center),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Rank Tiers'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border)),
          child: Column(
              children: RankTier.values.asMap().entries.map((e) {
            final t = e.value;
            final isLast = e.key == RankTier.values.length - 1;
            final isCurrent = tier == t;
            const tierRanges = {
              RankTier.bronze: '0 – 999 pts',
              RankTier.silver: '1,000 – 1,999 pts',
              RankTier.gold: '2,000 – 2,999 pts',
              RankTier.diamond: '3,000 – 3,999 pts',
              RankTier.champion: '4,000+ pts (Top 100)',
            };
            return Column(children: [
              Container(
                padding: isCurrent ? const EdgeInsets.all(8) : EdgeInsets.zero,
                decoration: isCurrent
                    ? BoxDecoration(
                        color: tierColor(t).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: tierColor(t).withValues(alpha: 0.15)))
                    : null,
                child: Row(children: [
                  Text(t.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(isCurrent ? '${t.label} ← You' : t.label,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isCurrent
                                    ? tierColor(t)
                                    : AppTheme.textPrimary)),
                        Text(tierRanges[t]!,
                            style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                                fontFamily: 'Courier')),
                      ])),
                  if (isCurrent)
                    Text('$pts pts',
                        style: TextStyle(
                            color: tierColor(t),
                            fontFamily: 'Courier',
                            fontSize: 11,
                            fontWeight: FontWeight.w500))
                  else if (tier.index > t.index)
                    const Text('✓',
                        style: TextStyle(color: AppTheme.green, fontSize: 16)),
                ]),
              ),
              if (!isLast)
                Container(
                    width: 2,
                    height: 10,
                    color: AppTheme.border,
                    margin: const EdgeInsets.only(left: 11, top: 2, bottom: 2)),
            ]);
          }).toList()),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('How to Earn Points'),
        Container(
          decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border)),
          child: const Column(children: [
            _PointsRow('Weekly portfolio +10%', '+100 pts', AppTheme.green),
            _PointsRow('Weekly portfolio +7–9.99%', '+75 pts', AppTheme.green),
            _PointsRow('Weekly portfolio +5–6.99%', '+50 pts', AppTheme.green),
            _PointsRow('Weekly portfolio +3–4.99%', '+35 pts', AppTheme.green),
            _PointsRow('Weekly portfolio +1–2.99%', '+20 pts', AppTheme.green),
            _PointsRow('Weekly portfolio 0–0.99%', '+10 pts', AppTheme.green),
            _PointsRow(
                'Weekly portfolio negative', '+5 pts', AppTheme.textMuted,
                isLast: true),
          ]),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Season End Rewards'),
        GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.3,
            children: const [
              _RewardCard('🥉', 'Bronze', 'Exclusive badge', RankTier.bronze),
              _RewardCard(
                  '🥈', 'Silver', 'Badge + profile border', RankTier.silver),
              _RewardCard('🥇', 'Gold', 'Badge + avatar frame', RankTier.gold),
              _RewardCard(
                  '💎', 'Diamond', 'Animated border + emote', RankTier.diamond),
            ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.purple.withValues(alpha: 0.08),
              AppTheme.purple.withValues(alpha: 0.04)
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
          ),
          child: const Column(children: [
            Text('👑', style: TextStyle(fontSize: 32)),
            SizedBox(height: 6),
            Text('Champion Reward',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.purple)),
            SizedBox(height: 4),
            Text(
                'Animated crown · Exclusive chat color · "Champion" title · Hall of Fame',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    fontFamily: 'Courier',
                    height: 1.5)),
          ]),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ─────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────
Color tierColor(RankTier tier) {
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

class TierBadge extends StatelessWidget {
  final RankTier tier;
  final bool small;
  const TierBadge({super.key, required this.tier, this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = tierColor(tier);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 12, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: c.withValues(alpha: 0.25))),
      child: Text('${tier.emoji} ${tier.label}',
          style: TextStyle(
              fontSize: small ? 9 : 11,
              color: c,
              fontFamily: 'Courier',
              fontWeight: FontWeight.w500)),
    );
  }
}

class _RankCard extends StatelessWidget {
  final RankedProfile profile;
  final int rankingPoints;
  const _RankCard({required this.profile, required this.rankingPoints});

  static double _tierProgress(int pts, RankTier tier) {
    final range = tier.maxPoints - tier.minPoints + 1;
    return ((pts - tier.minPoints) / range).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final pts = rankingPoints;
    final tier = RankTierExt.fromPoints(pts);
    final c = tierColor(tier);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0A0D18), Color(0xFF0D1220)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.blue.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF0A2A0A), AppTheme.green]),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.green.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ]),
              child: Center(
                  child: Text(
                      profile.username.isNotEmpty
                          ? profile.username[0].toUpperCase()
                          : 'P',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(profile.username,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)),
                Text('${tier.emoji} ${tier.label} · $pts pts',
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontFamily: 'Courier')),
                const SizedBox(height: 6),
                TierBadge(tier: tier),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('GLOBAL RANK',
                style: TextStyle(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                    fontFamily: 'Courier',
                    letterSpacing: 1)),
            Text('#${profile.globalRank}',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: c,
                    letterSpacing: -1,
                    fontFamily: 'Courier',
                    height: 1)),
          ]),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                  '${tier.emoji} ${tier.label} → ${tier.next?.emoji ?? "👑"} ${tier.next?.label ?? "Champion"}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: c)),
              Text('$pts / ${tier.next?.minPoints ?? pts} pts',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier')),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: _tierProgress(pts, tier),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation(c),
                    minHeight: 6)),
            if (tier.next != null) ...[
              const SizedBox(height: 6),
              Text(
                  '${tier.next!.minPoints - pts} more points to reach ${tier.next!.label}!',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier'),
                  textAlign: TextAlign.center),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _SeasonStatsRow extends StatelessWidget {
  final RankedProfile? profile;
  const _SeasonStatsRow({required this.profile});
  @override
  Widget build(BuildContext context) => Row(children: [
        _StatTile(
            'Wins', '${profile?.wins ?? 0}', AppTheme.green, 'this season'),
        const SizedBox(width: 8),
        _StatTile(
            'Win Rate',
            '${((profile?.winRate ?? 0) * 100).toStringAsFixed(0)}%',
            AppTheme.textPrimary,
            '${profile?.wins ?? 0}W · ${profile?.losses ?? 0}L'),
        const SizedBox(width: 8),
        _StatTile(
            'Best ROI',
            '+${(profile?.bestWeekROI ?? 0).toStringAsFixed(0)}%',
            AppTheme.gold,
            'single week'),
      ]);
}

class _StatTile extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  const _StatTile(this.label, this.value, this.color, this.sub);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border)),
        child: Column(children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.5)),
          Text(sub,
              style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier')),
        ]),
      ));
}

class _QuickModeButton extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickModeButton({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppTheme.green, AppTheme.green2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppTheme.green.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 6))
            ]),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: -0.5)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0x99000000),
                        fontFamily: 'Courier')),
              ])),
          const Text('→',
              style: TextStyle(fontSize: 20, color: Color(0x66000000))),
        ]),
      ),
    );
  }
}

class _MatchmakingCard extends StatelessWidget {
  final RankedProvider ranked;
  const _MatchmakingCard({required this.ranked});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.blue.withValues(alpha: 0.2))),
        child: Column(children: [
          const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  color: AppTheme.blue, strokeWidth: 2.5)),
          const SizedBox(height: 12),
          Text(ranked.matchmakingStatus,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Waiting for an opponent...',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'Courier')),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton(
              onPressed: () => ranked.cancelMatchmaking(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.red,
                side: const BorderSide(color: AppTheme.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Cancel Search',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────
// 1v1 RANKED CHALLENGE SHEET
// ─────────────────────────────────────────
class _QuickMatchSheet extends StatefulWidget {
  final RankedProvider ranked;
  const _QuickMatchSheet({required this.ranked});
  @override
  State<_QuickMatchSheet> createState() => _QuickMatchSheetState();
}

class _QuickMatchSheetState extends State<_QuickMatchSheet> {
  final _contactController = TextEditingController();
  String _duration = '1week';
  int _rosterSize = 5;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _sendChallenge() async {
    final contact = _contactController.text.trim();
    if (contact.isEmpty) {
      setState(() => _error = 'Enter an email, code, or phone number');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ranked = widget.ranked;
      final found = await ranked.findUserByContact(contact);
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _sending = false;
          _error = 'No user found with that email or phone';
        });
        return;
      }
      final err = await ranked.createChallenge(
        opponentUID: found['uid']!,
        opponentUsername: found['username']!,
        opponentContact: contact,
        duration: _duration,
        rosterSize: _rosterSize,
      );
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _sending = false;
          _error = err;
        });
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Challenge sent!'),
          backgroundColor: AppTheme.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: AppTheme.border2, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 16),
        const Text('1v1 Ranked',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5)),
        const SizedBox(height: 4),
        const Text('Challenge a friend head-to-head',
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontFamily: 'Courier')),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.green.withValues(alpha: 0.2)),
          ),
          child: const Text('💰 \$10,000 starting balance',
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.green,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 20),

        // Opponent
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('OPPONENT',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  letterSpacing: 2)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _contactController,
          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Email, invite code, or phone number',
            hintStyle: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.5), fontSize: 13),
            filled: true,
            fillColor: AppTheme.surface2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.green)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_error!,
                style: const TextStyle(
                    color: AppTheme.red, fontSize: 11, fontFamily: 'Courier')),
          ),
        ],
        const SizedBox(height: 16),

        // Duration
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('DURATION',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  letterSpacing: 2)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _SheetChip(
              label: '1 Day',
              selected: _duration == '1day',
              onTap: () => setState(() => _duration = '1day')),
          const SizedBox(width: 8),
          _SheetChip(
              label: '1 Week',
              selected: _duration == '1week',
              onTap: () => setState(() => _duration = '1week')),
        ]),
        const SizedBox(height: 16),

        // Roster Size
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('ROSTER SIZE',
              style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  letterSpacing: 2)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _SheetChip(
              label: '3 Stocks',
              selected: _rosterSize == 3,
              onTap: () => setState(() => _rosterSize = 3)),
          const SizedBox(width: 8),
          _SheetChip(
              label: '5 Stocks',
              selected: _rosterSize == 5,
              onTap: () => setState(() => _rosterSize = 5)),
          const SizedBox(width: 8),
          _SheetChip(
              label: '11 Sectors',
              selected: _rosterSize == 11,
              onTap: () => setState(() => _rosterSize = 11)),
        ]),
        if (_rosterSize == 11) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
            ),
            child: const Text('Each pick must be from a different GICS sector',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.purple,
                    fontFamily: 'Courier')),
          ),
        ],
        const SizedBox(height: 24),

        // Send Challenge button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _sending ? null : _sendChallenge,
            child: _sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2.5))
                : const Text('Send Challenge',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
    );
  }
}

class _MatchFoundOverlay extends StatefulWidget {
  final String opponentName;
  final VoidCallback onPickStocks;
  const _MatchFoundOverlay(
      {required this.opponentName, required this.onPickStocks});
  @override
  State<_MatchFoundOverlay> createState() => _MatchFoundOverlayState();
}

class _MatchFoundOverlayState extends State<_MatchFoundOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.15, end: 0.45).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder2(
        listenable: _glowAnim,
        builder: (_, child) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1220),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppTheme.green.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.green.withValues(alpha: _glowAnim.value),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: child,
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('\u2694\uFE0F', style: TextStyle(fontSize: 32))),
            ),
            const SizedBox(height: 16),
            const Text('OPPONENT FOUND!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Courier',
                  color: AppTheme.green,
                  letterSpacing: 1,
                )),
            const SizedBox(height: 8),
            Text('vs ${widget.opponentName}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                )),
            const SizedBox(height: 4),
            const Text('Get ready to pick your stocks!',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: widget.onPickStocks,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Pick Stocks',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class AnimatedBuilder2 extends StatelessWidget {
  final Listenable listenable;
  final Widget? child;
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder2({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (ctx, _) => builder(ctx, child),
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _SheetChip(
      {required this.label,
      this.subtitle, // ignore: unused_element_parameter — used in build
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.green.withValues(alpha: 0.1)
                : AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected
                    ? AppTheme.green.withValues(alpha: 0.4)
                    : AppTheme.border),
          ),
          child: Column(children: [
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.green : AppTheme.textPrimary,
                )),
            if (subtitle != null)
              Text(subtitle!,
                  style: TextStyle(
                    fontSize: 9,
                    color: selected
                        ? AppTheme.green.withValues(alpha: 0.7)
                        : AppTheme.textMuted,
                    fontFamily: 'Courier',
                  )),
          ]),
        ),
      ),
    );
  }
}

class _ActiveMatchCard extends StatelessWidget {
  final Challenge challenge;
  final String myUid;
  const _ActiveMatchCard({required this.challenge, required this.myUid});

  String _timeRemaining() {
    if (challenge.startDate == null && challenge.endDateUtc == null) {
      return 'Picking stocks';
    }
    DateTime end;
    if (challenge.endDateUtc != null) {
      end = DateTime.parse(challenge.endDateUtc!);
    } else {
      end = challenge.duration == '1day'
          ? challenge.startDate!.add(const Duration(days: 1))
          : challenge.startDate!.add(const Duration(days: 7));
    }
    final remaining = end.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'Ended';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours % 24}h left';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
    }
    return '${remaining.inMinutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    final isChallenger = challenge.challengerUID == myUid;
    final myValue =
        isChallenger ? challenge.challengerValue : challenge.opponentValue;
    final myCost =
        isChallenger ? challenge.challengerCost : challenge.opponentCost;
    final theirValue =
        isChallenger ? challenge.opponentValue : challenge.challengerValue;
    final theirCost =
        isChallenger ? challenge.opponentCost : challenge.challengerCost;
    final opponentName = challenge.opponentNameOf(myUid);
    final myPct = myCost > 0 ? ((myValue - myCost) / myCost) * 100 : 0.0;
    final theirPct =
        theirCost > 0 ? ((theirValue - theirCost) / theirCost) * 100 : 0.0;
    final winning = myPct >= theirPct;
    final isPicking = challenge.status == ChallengeStatus.picking;
    final myPicks =
        isChallenger ? challenge.challengerPicks : challenge.opponentPicks;
    final needsMyPicks = isPicking && myPicks.isEmpty;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatchDetailScreen(challenge: challenge),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: needsMyPicks
                  ? AppTheme.green.withValues(alpha: 0.3)
                  : AppTheme.border),
        ),
        child: Column(children: [
        // Header: opponent + time
        Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.surface3,
            child: Text(
                opponentName.isNotEmpty
                    ? opponentName.substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppTheme.green)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('vs $opponentName',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                  '${challenge.durationLabel} · ${challenge.rosterSize} ${challenge.isSectorMode ? 'sectors' : 'stocks'}',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier')),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: needsMyPicks
                  ? AppTheme.green.withValues(alpha: 0.1)
                  : AppTheme.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              needsMyPicks ? 'PICK STOCKS' : _timeRemaining(),
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'Courier',
                fontWeight: FontWeight.w700,
                color: needsMyPicks ? AppTheme.green : AppTheme.textMuted,
              ),
            ),
          ),
        ]),
        if (!isPicking || (myCost > 0 && theirCost > 0)) ...[
          const SizedBox(height: 12),
          // Score row
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: winning
                      ? AppTheme.green.withValues(alpha: 0.05)
                      : AppTheme.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: winning
                      ? Border.all(
                          color: AppTheme.green.withValues(alpha: 0.15))
                      : null,
                ),
                child: Column(children: [
                  const Text('YOU',
                      style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                          fontFamily: 'Courier')),
                  const SizedBox(height: 2),
                  Text(
                    '${myPct >= 0 ? '+' : ''}${myPct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Courier',
                      color: myPct >= 0 ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(winning ? '>' : '<',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: winning ? AppTheme.green : AppTheme.red,
                      fontFamily: 'Courier')),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
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
                  const SizedBox(height: 2),
                  Text(
                    '${theirPct >= 0 ? '+' : ''}${theirPct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Courier',
                      color: theirPct >= 0 ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ],
        ]),
      ),
    );
  }
}

class _ActiveLeagueCard extends StatelessWidget {
  final String name, type, record, roi;
  final int week, rank;
  final RankTier tier;
  final bool isPrivate;
  final LeagueStatus status;
  const _ActiveLeagueCard(
      {required this.name,
      required this.type,
      required this.week,
      required this.record,
      required this.rank,
      required this.roi,
      required this.tier,
      required this.isPrivate,
      this.status = LeagueStatus.active});

  String get _statusLabel {
    switch (status) {
      case LeagueStatus.pending:
        return 'PENDING';
      case LeagueStatus.drafting:
        return 'DRAFTING';
      case LeagueStatus.active:
        return 'Week $week';
      case LeagueStatus.playoffs:
        return 'PLAYOFFS';
      case LeagueStatus.complete:
        return 'COMPLETE';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isPrivate
                    ? AppTheme.border
                    : AppTheme.blue.withValues(alpha: 0.15))),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                  Text('$type · $_statusLabel',
                      style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontFamily: 'Courier')),
                ])),
          ]),
          if (status == LeagueStatus.active ||
              status == LeagueStatus.playoffs) ...[
            const SizedBox(height: 10),
            Row(children: [
              _MiniStat('RECORD', record, AppTheme.green),
              const SizedBox(width: 8),
              _MiniStat('RETURN', roi,
                  roi.startsWith('-') ? AppTheme.red : AppTheme.green),
            ]),
          ],
        ]),
      );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AppTheme.surface2, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: color)),
        ]),
      ));
}

class _ExploreCard extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _ExploreCard(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
      child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.15))),
            child: Column(children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.3)),
            ]),
          )));
}

class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  const _Podium({required this.top3});
  @override
  Widget build(BuildContext context) {
    final order = [top3[1], top3[0], top3[2]];
    final heights = [46.0, 64.0, 34.0];
    final avSizes = [48.0, 60.0, 44.0];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: order.asMap().entries.map((e) {
            final entry = e.value;
            final isFirst = entry.rank == 1;
            return Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (isFirst) const Text('👑', style: TextStyle(fontSize: 20)),
              Container(
                  width: avSizes[e.key],
                  height: avSizes[e.key],
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: isFirst
                              ? [const Color(0xFF2A1A00), AppTheme.gold]
                              : [AppTheme.surface2, AppTheme.surface3]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isFirst
                          ? [
                              BoxShadow(
                                  color: AppTheme.gold.withValues(alpha: 0.3),
                                  blurRadius: 16)
                            ]
                          : null),
                  child: Center(
                      child: Text(
                          entry.username
                              .substring(0, min(2, entry.username.length))
                              .toUpperCase(),
                          style: TextStyle(
                              fontSize: isFirst ? 20 : 15,
                              fontWeight: FontWeight.w900,
                              color: isFirst
                                  ? Colors.black
                                  : AppTheme.textPrimary)))),
              const SizedBox(height: 4),
              Text(entry.username,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isFirst ? FontWeight.w900 : FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
              Text('${entry.points} pts',
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Courier',
                      color: isFirst ? AppTheme.gold : AppTheme.textMuted)),
              Container(
                  height: heights[e.key],
                  decoration: BoxDecoration(
                      color: isFirst
                          ? AppTheme.gold.withValues(alpha: 0.08)
                          : AppTheme.surface,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                      border: Border.all(
                          color: isFirst
                              ? AppTheme.gold.withValues(alpha: 0.2)
                              : AppTheme.border))),
            ]));
          }).toList()),
    );
  }
}

int min(int a, int b) => a < b ? a : b;

class _LBRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isMe;
  const _LBRow({required this.entry, required this.isMe});
  @override
  Widget build(BuildContext context) {
    final c = tierColor(entry.tier);
    final rankColor = entry.rank == 1
        ? AppTheme.gold
        : entry.rank == 2
            ? AppTheme.silver
            : entry.rank == 3
                ? const Color(0xFFCD7F32)
                : AppTheme.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color:
              isMe ? AppTheme.green.withValues(alpha: 0.05) : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isMe
                  ? AppTheme.green.withValues(alpha: 0.18)
                  : AppTheme.border)),
      child: Row(children: [
        SizedBox(
            width: 28,
            child: Text('#${entry.rank}',
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: rankColor))),
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(11)),
            child: Center(
                child: Text(
                    entry.username
                        .substring(0, min(2, entry.username.length))
                        .toUpperCase(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)))),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.username,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isMe ? AppTheme.green : AppTheme.textPrimary)),
          if (isMe)
            const Text('← you',
                style: TextStyle(
                    fontSize: 9, color: AppTheme.green, fontFamily: 'Courier')),
        ])),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.withValues(alpha: 0.2))),
            child:
                Text(entry.tier.emoji, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${entry.points}',
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          Text(
              entry.pointsDelta >= 0
                  ? '▲ +${entry.pointsDelta}'
                  : '▼ ${entry.pointsDelta}',
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Courier',
                  color:
                      entry.pointsDelta >= 0 ? AppTheme.green : AppTheme.red)),
        ]),
      ]),
    );
  }
}

class _LeagueCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LeagueCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final members = (data['members'] as List?)?.length ?? 0;
    final maxPlayers = data['maxPlayers'] as int? ?? 8;
    final spotsLeft = maxPlayers - members;
    final isFull = spotsLeft <= 0;
    final tier = RankTierExt.fromPoints(0);
    final c = tierColor(tier);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text(data['name'] ?? 'League',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3))),
                  const SizedBox(width: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: (isFull ? AppTheme.red : AppTheme.green)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: (isFull ? AppTheme.red : AppTheme.green)
                                  .withValues(alpha: 0.2))),
                      child: Text(isFull ? '✕ Full' : '● $spotsLeft spots',
                          style: TextStyle(
                              fontSize: 9,
                              color: isFull ? AppTheme.red : AppTheme.green,
                              fontFamily: 'Courier'))),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  TierBadge(tier: tier, small: true),
                  const SizedBox(width: 6),
                  Text('${data['totalWeeks'] ?? 12} weeks',
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontFamily: 'Courier')),
                ]),
              ])),
          ElevatedButton(
              onPressed: isFull
                  ? null
                  : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Joining ${data['name']}!'),
                      backgroundColor: AppTheme.green)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: isFull ? AppTheme.surface2 : AppTheme.green,
                  foregroundColor: isFull ? AppTheme.textMuted : Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  minimumSize: Size.zero),
              child: Text(isFull ? 'Full' : 'Join',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
                value: members / maxPlayers,
                minHeight: 4,
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation(isFull ? AppTheme.red : c))),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$members of $maxPlayers players',
              style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier')),
          Text(isFull ? 'League full' : '$spotsLeft spots left',
              style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'Courier',
                  color: isFull ? AppTheme.red : AppTheme.textMuted)),
        ]),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
              color: active ? AppTheme.greenDim : AppTheme.surface,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                  color: active
                      ? AppTheme.green.withValues(alpha: 0.25)
                      : AppTheme.border)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Courier',
                  color: active ? AppTheme.green : AppTheme.textMuted))));
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: active ? AppTheme.greenDim : AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active
                      ? AppTheme.green.withValues(alpha: 0.2)
                      : AppTheme.border)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Courier',
                  color: active ? AppTheme.green : AppTheme.textMuted))));
}

class _OnlinePlayersBar extends StatelessWidget {
  final RankedProvider ranked;
  const _OnlinePlayersBar({required this.ranked});

  static const _tiers = ['bronze', 'silver', 'gold', 'diamond', 'champion'];
  static const Map<String, String> _tierEmojis = {
    'bronze': '\u{1F949}',
    'silver': '\u{1F948}',
    'gold': '\u{1F947}',
    'diamond': '\u{1F48E}',
    'champion': '\u{1F451}',
  };

  @override
  Widget build(BuildContext context) {
    final total = ranked.totalOnline;
    final activeTiers = _tiers
        .where((t) => (ranked.onlineCounts[t] ?? 0) > 0)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: total > 0 ? AppTheme.green : AppTheme.textMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text('PLAYERS ONLINE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'Courier',
              letterSpacing: 0.5,
              color: total > 0 ? AppTheme.green : AppTheme.textMuted,
            )),
        const SizedBox(width: 12),
        Expanded(
          child: total == 0
              ? const Text('No players online',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Courier',
                    color: AppTheme.textMuted,
                  ))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < activeTiers.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('\u{00B7}',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted)),
                        ),
                      Text(
                        '${_tierEmojis[activeTiers[i]]} ${ranked.onlineCounts[activeTiers[i]]}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted,
              fontFamily: 'Courier',
              letterSpacing: 2)));
}

class _PointsRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool isLast;
  const _PointsRow(this.label, this.value, this.color, {this.isLast = false});
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 13))),
              Text(value,
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontSize: 13)),
            ])),
        if (!isLast) const Divider(height: 1, color: AppTheme.border),
      ]);
}

class _RewardCard extends StatelessWidget {
  final String emoji, name, desc;
  final RankTier tier;
  const _RewardCard(this.emoji, this.name, this.desc, this.tier);
  @override
  Widget build(BuildContext context) {
    final c = tierColor(tier);
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.withValues(alpha: 0.15))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 4),
          Text(name,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 2),
          Text(desc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  fontFamily: 'Courier',
                  height: 1.3)),
        ]));
  }
}
