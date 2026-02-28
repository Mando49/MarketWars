import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ranked_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────
// COMPETE SCREEN  (tab 2)
// ─────────────────────────────────────────
class CompeteScreen extends StatefulWidget {
  const CompeteScreen({super.key});
  @override
  State<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends State<CompeteScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RankedProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranked = context.watch<RankedProvider>();
    final profile = ranked.myProfile;

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
      body: ranked.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.green))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (profile != null) _RankCard(profile: profile),
                const SizedBox(height: 12),
                _SeasonStatsRow(profile: profile),
                const SizedBox(height: 14),
                ranked.isMatchmaking
                    ? _MatchmakingCard(ranked: ranked)
                    : _QuickMatchButton(onTap: () => ranked.startQuickMatch()),
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
                const _SectionLabel('My Active Leagues'),
                const _ActiveLeagueCard(
                  name: 'Wall Street Warriors',
                  type: 'Private · 8 players',
                  week: 6,
                  record: '4-1',
                  rank: 2,
                  roi: '+14%',
                  tier: RankTier.gold,
                  isPrivate: true,
                ),
                const SizedBox(height: 8),
                const _ActiveLeagueCard(
                  name: 'Diamond Ranked #1441',
                  type: 'Quick match · 6 players',
                  week: 3,
                  record: '2-0',
                  rank: 1,
                  roi: '+9%',
                  tier: RankTier.diamond,
                  isPrivate: false,
                ),
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
  late Timer _timer;
  Duration _remaining =
      const Duration(days: 18, hours: 4, minutes: 32, seconds: 17);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          if (_remaining.inSeconds > 0) {
            _remaining -= const Duration(seconds: 1);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<RankedProvider>().myProfile;
    return Scaffold(
      appBar: AppBar(title: const Text('Season 3')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Hero
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
            const Text('🎖️ CURRENT SEASON',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.purple,
                    fontFamily: 'Courier',
                    letterSpacing: 2)),
            const SizedBox(height: 6),
            const Text('Season 3: Bull Run',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5)),
            const Text('Compete in leagues, climb ranks, earn rewards',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontFamily: 'Courier')),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _TimeBlock(
                        num: _remaining.inDays.toString().padLeft(2, '0'),
                        label: 'DAYS'),
                    _TimeSep(),
                    _TimeBlock(
                        num: (_remaining.inHours % 24)
                            .toString()
                            .padLeft(2, '0'),
                        label: 'HRS'),
                    _TimeSep(),
                    _TimeBlock(
                        num: (_remaining.inMinutes % 60)
                            .toString()
                            .padLeft(2, '0'),
                        label: 'MIN'),
                    _TimeSep(),
                    _TimeBlock(
                        num: (_remaining.inSeconds % 60)
                            .toString()
                            .padLeft(2, '0'),
                        label: 'SEC'),
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
            final tier = e.value;
            final isLast = e.key == RankTier.values.length - 1;
            final isCurrent = profile?.tier == tier;
            return Column(children: [
              Container(
                padding: isCurrent ? const EdgeInsets.all(8) : EdgeInsets.zero,
                decoration: isCurrent
                    ? BoxDecoration(
                        color: tierColor(tier).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: tierColor(tier).withValues(alpha: 0.15)))
                    : null,
                child: Row(children: [
                  Text(tier.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(isCurrent ? '${tier.label} ← You' : tier.label,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isCurrent
                                    ? tierColor(tier)
                                    : AppTheme.textPrimary)),
                        Text(
                            tier == RankTier.champion
                                ? '4,000+ pts · Top 100'
                                : '${tier.minPoints} – ${tier.maxPoints} points',
                            style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                                fontFamily: 'Courier')),
                      ])),
                  if (isCurrent && profile != null)
                    Text('${profile.seasonPoints} pts',
                        style: TextStyle(
                            color: tierColor(tier),
                            fontFamily: 'Courier',
                            fontSize: 11,
                            fontWeight: FontWeight.w500))
                  else if (profile != null && profile.tier.index > tier.index)
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
            _PointsRow('Win a matchup', '+${PointsSystem.matchupWin} pts',
                AppTheme.green),
            _PointsRow('Win the league', '+${PointsSystem.leagueWin} pts',
                AppTheme.green),
            _PointsRow('Reach playoffs', '+${PointsSystem.reachPlayoffs} pts',
                AppTheme.green),
            _PointsRow('Portfolio +10% in a week',
                '+${PointsSystem.weekROI10pct} pts', AppTheme.green),
            _PointsRow('Portfolio +20% in a week',
                '+${PointsSystem.weekROI20pct} pts', AppTheme.green),
            _PointsRow('Lose a matchup', '${PointsSystem.matchupLoss} pts',
                AppTheme.red,
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
  const _RankCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final c = tierColor(profile.tier);
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
                Text('${profile.tier.emoji} ${profile.tier.label} · Season 3',
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontFamily: 'Courier')),
                const SizedBox(height: 6),
                TierBadge(tier: profile.tier),
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
                  '${profile.tier.emoji} ${profile.tier.label} → ${profile.tier.next?.emoji ?? "👑"} ${profile.tier.next?.label ?? "Champion"}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: c)),
              Text(
                  '${profile.seasonPoints} / ${profile.tier.next?.minPoints ?? profile.seasonPoints} pts',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier')),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: profile.tierProgress,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation(c),
                    minHeight: 6)),
            if (profile.tier.next != null) ...[
              const SizedBox(height: 6),
              Text(
                  '${profile.pointsToNextTier} more points to reach ${profile.tier.next!.label}!',
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

class _QuickMatchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickMatchButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final tier =
        context.read<RankedProvider>().myProfile?.tier.label ?? 'Ranked';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppTheme.green, AppTheme.green2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: AppTheme.green.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8))
            ]),
        child: Row(children: [
          const Text('⚡', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Quick Match',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: -0.5)),
                Text('Auto-join a $tier league · ~30 sec',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0x99000000),
                        fontFamily: 'Courier')),
              ])),
          const Text('→',
              style: TextStyle(fontSize: 22, color: Color(0x66000000))),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.blue.withValues(alpha: 0.2))),
        child: Column(children: [
          const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  color: AppTheme.blue, strokeWidth: 2.5)),
          const SizedBox(height: 10),
          Text(ranked.matchmakingStatus,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text('${ranked.matchmakingPlayerCount} / 8 players found',
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'Courier')),
          const SizedBox(height: 12),
          ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  value: ranked.matchmakingPlayerCount / 8,
                  backgroundColor: AppTheme.border,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.blue),
                  minHeight: 4)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => ranked.cancelMatchmaking(),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textMuted))),
        ]),
      );
}

class _ActiveLeagueCard extends StatelessWidget {
  final String name, type, record, roi;
  final int week, rank;
  final RankTier tier;
  final bool isPrivate;
  const _ActiveLeagueCard(
      {required this.name,
      required this.type,
      required this.week,
      required this.record,
      required this.rank,
      required this.roi,
      required this.tier,
      required this.isPrivate});
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
                  Text('$type · Week $week',
                      style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontFamily: 'Courier')),
                ])),
            TierBadge(tier: tier, small: true),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _MiniStat('RECORD', record, AppTheme.green),
            const SizedBox(width: 8),
            _MiniStat('RANK', '#$rank', AppTheme.textPrimary),
            const SizedBox(width: 8),
            _MiniStat('RETURN', roi, AppTheme.green),
          ]),
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
          color: isMe ? AppTheme.green.withValues(alpha: 0.05) : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  isMe ? AppTheme.green.withValues(alpha: 0.18) : AppTheme.border)),
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

class _TimeBlock extends StatelessWidget {
  final String num, label;
  const _TimeBlock({required this.num, required this.label});
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(num,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                fontFamily: 'Courier',
                color: AppTheme.purple,
                height: 1)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 9, color: AppTheme.textMuted, fontFamily: 'Courier')),
      ]);
}

class _TimeSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(':',
          style: TextStyle(
              fontSize: 20, color: AppTheme.textMuted, fontFamily: 'Courier')));
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
