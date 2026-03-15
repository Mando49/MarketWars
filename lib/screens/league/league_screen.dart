import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/league_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../services/finnhub_stock_service.dart';
import '../../services/scoring_service.dart';
import '../../theme/app_theme.dart';
import '../search/stock_detail_screen.dart';
import 'create_league_screen.dart';
import 'draft_room_screen.dart';
import 'invite_players_screen.dart';

// ── Shared sector colors & helper ──
const Map<String, Color> _kSectorBg = {
  'Tech': Color(0xFF0E1F30),
  'Finance': Color(0xFF201800),
  'EV/Auto': Color(0xFF200A0A),
  'Crypto': Color(0xFF140A28),
  'Consumer': Color(0xFF0A1E0A),
  'Energy': Color(0xFF0A1E14),
};
const Map<String, Color> _kSectorFg = {
  'Tech': Color(0xFF4FC3F7),
  'Finance': Color(0xFFFFC947),
  'EV/Auto': Color(0xFFFF6B6B),
  'Crypto': Color(0xFFB388FF),
  'Consumer': Color(0xFFFF9F43),
  'Energy': Color(0xFF26DE81),
};
String _guessSectorFor(String sym) {
  const map = {
    'Tech': [
      'NVDA',
      'AAPL',
      'MSFT',
      'META',
      'GOOGL',
      'AMD',
      'PLTR',
      'SHOP',
      'DDOG',
      'CRWD',
      'SNAP',
      'RBLX'
    ],
    'Finance': ['JPM', 'BAC', 'GS', 'V', 'MA', 'HOOD', 'SOFI', 'PYPL', 'SPY'],
    'EV/Auto': ['TSLA', 'RIVN', 'NIO', 'F', 'GM'],
    'Crypto': ['COIN', 'MSTR', 'BTC', 'ETH'],
    'Consumer': [
      'AMZN',
      'NFLX',
      'DIS',
      'UBER',
      'SPOT',
      'BABA',
      'ABNB',
      'WMT',
      'COST'
    ],
    'Energy': ['XOM', 'CVX'],
  };
  for (final entry in map.entries) {
    if (entry.value.contains(sym)) return entry.key;
  }
  return 'Other';
}

// ─────────────────────────────────────────────────────────
// LEAGUE SCREEN — Sleeper-inspired layout
// Tabs: MATCH | TEAM | PLAYERS | LEAGUE
// ─────────────────────────────────────────────────────────
class LeagueScreen extends StatefulWidget {
  final String? leagueId;
  const LeagueScreen({super.key, this.leagueId});
  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final ScoringService _scoringService;
  Timer? _scoringTimer;
  StreamSubscription? _leagueSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 3);
    _scoringService = ScoringService(stockService: FinnhubStockService());

    // Score all active leagues every 15 minutes
    _scoringTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _scoringService.scoreAllLeagues(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LeagueProvider>().loadLeagues();
      _listenToLeagueChanges();
    });
  }

  void _listenToLeagueChanges() {
    if (widget.leagueId == null) return;
    _leagueSub = FirebaseFirestore.instance
        .collection('leagues')
        .doc(widget.leagueId)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        context.read<LeagueProvider>().loadLeagues();
      }
    });
  }

  @override
  void dispose() {
    _leagueSub?.cancel();
    _scoringTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<LeagueProvider>();
    final league = widget.leagueId != null
        ? prov.leagues.cast<League?>().firstWhere(
              (l) => l!.id == widget.leagueId,
              orElse: () => null,
            )
        : (prov.leagues.isNotEmpty ? prov.leagues.first : null);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            _LeagueHeader(
              league: league,
              tabController: _tabController,
              onBack: () => Navigator.pop(context),
              onInvite: () {
                if (league != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvitePlayersScreen(
                        leagueId: league.id,
                        leagueName: league.name,
                        inviteCode: league.inviteCode,
                      ),
                    ),
                  );
                }
              },
              onLeaveOrDelete: () async {
                if (league == null) return;
                final isCommissioner = league.commissionerUID == prov.uid;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: Text(
                        isCommissioner ? 'Delete League' : 'Leave League',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 18)),
                    content: Text(
                        isCommissioner
                            ? 'Delete this league? All data will be permanently lost.'
                            : 'Leave this league? You will need a new invite to rejoin.',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 15)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(isCommissioner ? 'Delete' : 'Leave',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  if (isCommissioner) {
                    await prov.deleteLeague(league.id);
                  } else {
                    await prov.leaveLeague(league.id);
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),

            // ── Tab panels ──
            Expanded(
              child: prov.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.green))
                  : league == null
                      ? _NoLeagueView(
                          onGetStarted: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const CreateJoinLeagueScreen())))
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _MatchTab(league: league, prov: prov),
                            _TeamTab(league: league, prov: prov),
                            _PlayersTab(league: league, prov: prov),
                            _LeagueTab(league: league, prov: prov),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// HEADER: league name + MATCH/TEAM/PLAYERS/LEAGUE tabs
// ─────────────────────────────────────────────────────────
class _LeagueHeader extends StatelessWidget {
  final League? league;
  final TabController tabController;
  final VoidCallback onBack;
  final VoidCallback onInvite;
  final VoidCallback onLeaveOrDelete;

  const _LeagueHeader({
    required this.league,
    required this.tabController,
    required this.onBack,
    required this.onInvite,
    required this.onLeaveOrDelete,
  });

  @override
  Widget build(BuildContext context) {
    final uid = context.read<LeagueProvider>().uid;
    final isCommissioner = league?.commissionerUID == uid;

    return Container(
      color: AppTheme.bg,
      child: Column(
        children: [
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 18),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40),
                ),
                const Text('🏦', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        league?.name ?? 'My League',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3),
                      ),
                      Text(
                        'Season 1 · ${league?.members.length ?? 0} players · 🏈 Fantasy Draft'
                        '${league != null ? ' · ${league!.inviteCode}' : ''}',
                        style: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                            fontFamily: 'Courier'),
                      ),
                    ],
                  ),
                ),
                _SmallBtn(label: '+ Invite', green: true, onTap: onInvite),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 20),
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    if (value == 'leave_or_delete') onLeaveOrDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'leave_or_delete',
                      child: Row(
                        children: [
                          Icon(
                            isCommissioner
                                ? Icons.delete_outline_rounded
                                : Icons.logout_rounded,
                            color: AppTheme.red,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isCommissioner ? 'Delete League' : 'Leave League',
                            style: const TextStyle(
                                color: AppTheme.red,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab bar
          TabBar(
            controller: tabController,
            indicatorColor: AppTheme.green,
            indicatorWeight: 2,
            labelColor: AppTheme.green,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8),
            tabs: const [
              Tab(text: 'MATCH'),
              Tab(text: 'TEAM'),
              Tab(text: 'PLAYERS'),
              Tab(text: 'LEAGUE'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final bool green;
  final VoidCallback onTap;
  const _SmallBtn(
      {required this.label, required this.green, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: green ? AppTheme.greenDim : AppTheme.surface2,
            border: Border.all(
                color: green ? AppTheme.greenBorder : AppTheme.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Courier',
                  color: green ? AppTheme.green : AppTheme.textMuted)),
        ),
      );
}

// ─────────────────────────────────────────────────────────
// TAB 1 — MATCH: current week matchup + holdings
// ─────────────────────────────────────────────────────────
class _MatchTab extends StatefulWidget {
  final League league;
  final LeagueProvider prov;
  const _MatchTab({required this.league, required this.prov});

  @override
  State<_MatchTab> createState() => _MatchTabState();
}

class _MatchTabState extends State<_MatchTab> {
  bool _scored = false;
  @override
  void initState() {
    super.initState();
    _scoreCurrentWeek();
  }

  @override
  void didUpdateWidget(covariant _MatchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.league.id != widget.league.id) {
      _scored = false;
      _scoreCurrentWeek();
    }
  }

  Future<void> _scoreCurrentWeek() async {
    if (_scored) return;
    _scored = true;
    final service = ScoringService(stockService: FinnhubStockService());
    await service.scoreWeek(widget.league, widget.league.calculatedWeek);
  }

  @override
  Widget build(BuildContext context) {
    final myMatchup = widget.prov.currentMatchups[widget.league.id];
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (myMatchup != null) ...[
          _MatchupDetailCard(matchup: myMatchup, startingBalance: widget.league.startingBalance),
          const _SectionLabel('YOUR HOLDINGS'),
          _LeagueHoldingsCard(leagueId: widget.league.id, prov: widget.prov),
        ] else
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
                child: Text('No active matchup this week',
                    style: TextStyle(color: AppTheme.textMuted))),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 2 — TEAM: full portfolio
// ─────────────────────────────────────────────────────────
class _TeamTab extends StatelessWidget {
  final League league;
  final LeagueProvider prov;
  const _TeamTab({required this.league, required this.prov});

  @override
  Widget build(BuildContext context) {
    final uid = prov.uid;
    return StreamBuilder<List<DraftPick>>(
      stream: prov.draftPicksStream(league.id),
      builder: (context, snap) {
        final allPicks = snap.data ?? [];
        final myPicks =
            allPicks.where((p) => p.pickedByUID == uid).toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('My Team',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const _SectionLabel('DRAFTED STOCKS'),
            if (myPicks.isEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: AppTheme.surface1,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text('No picks yet',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 14)),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                decoration: BoxDecoration(
                  color: AppTheme.surface1,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: myPicks
                      .map((pick) => _DraftPickTile(pick: pick))
                      .toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 3 — PLAYERS: available stocks
// ─────────────────────────────────────────────────────────
class _PlayersTab extends StatefulWidget {
  final League league;
  final LeagueProvider prov;
  const _PlayersTab({required this.league, required this.prov});

  @override
  State<_PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<_PlayersTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<StockResult> _searchResults = [];
  bool _isSearching = false;
  bool _didInitTrending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitTrending) {
      _didInitTrending = true;
      final prov = context.read<PortfolioProvider>();
      if (prov.trendingStocks.isEmpty) {
        prov.loadTrending();
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results =
          await context.read<PortfolioProvider>().searchStocks(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results.take(20).toList();
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolioProv = context.watch<PortfolioProvider>();

    return StreamBuilder<List<DraftPick>>(
      stream: widget.prov.draftPicksStream(widget.league.id),
      builder: (context, snap) {
        final picks = snap.data ?? [];
        // Build map: symbol → DraftPick for taken lookup
        final takenMap = <String, DraftPick>{};
        for (final p in picks) {
          takenMap[p.symbol] = p;
        }

        return Column(
          children: [
            // ── Header + Search ──
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Available Stocks',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search stocks…',
                    hintStyle:
                        TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Stock List ──
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.green)))
                  : _searchResults.isNotEmpty
                      ? _buildSearchResults(takenMap)
                      : _buildTrendingList(portfolioProv, takenMap),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(Map<String, DraftPick> takenMap) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, i) {
        final r = _searchResults[i];
        final taken = takenMap[r.symbol];
        return _StockListTile(
          symbol: r.symbol,
          companyName: r.description.isNotEmpty ? r.description : r.symbol,
          takenBy: taken?.pickedByUsername,
          onTap: taken == null
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StockDetailScreen(
                          symbol: r.symbol,
                          companyName: r.description.isNotEmpty
                              ? r.description
                              : r.symbol)))
              : null,
        );
      },
    );
  }

  Widget _buildTrendingList(
      PortfolioProvider prov, Map<String, DraftPick> takenMap) {
    if (prov.isTrendingLoading) {
      return const Center(
          child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.green)));
    }
    if (prov.trendingStocks.isEmpty) {
      return const Center(
        child: Text('No trending stocks available',
            style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                color: AppTheme.textMuted)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: prov.trendingStocks.length,
      itemBuilder: (context, i) {
        final stock = prov.trendingStocks[i];
        final taken = takenMap[stock.symbol];
        return _StockListTile(
          symbol: stock.symbol,
          companyName: stock.companyName,
          price: stock.price,
          changePct: stock.changePercent,
          takenBy: taken?.pickedByUsername,
          onTap: taken == null
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StockDetailScreen(
                          symbol: stock.symbol,
                          companyName: stock.companyName)))
              : null,
        );
      },
    );
  }
}

/// A single stock row used in the Available Stocks tab.
class _StockListTile extends StatelessWidget {
  final String symbol;
  final String companyName;
  final double? price;
  final double? changePct;
  final String? takenBy;
  final VoidCallback? onTap;

  const _StockListTile({
    required this.symbol,
    required this.companyName,
    this.price,
    this.changePct,
    this.takenBy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTaken = takenBy != null;
    final sec = _guessSectorFor(symbol);
    final fg = isTaken
        ? AppTheme.textMuted.withValues(alpha: 0.4)
        : (_kSectorFg[sec] ?? AppTheme.textMuted);
    final bg = isTaken
        ? AppTheme.surface2.withValues(alpha: 0.5)
        : (_kSectorBg[sec] ?? AppTheme.surface2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            // Ticker badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: fg.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(symbol,
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: fg)),
            ),
            const SizedBox(width: 10),
            // Name + taken label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(companyName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isTaken
                              ? AppTheme.textMuted.withValues(alpha: 0.5)
                              : Colors.white)),
                  if (isTaken)
                    Text('TAKEN · $takenBy',
                        style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 9,
                            color: AppTheme.red,
                            fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            // Price + change OR ADD button
            if (isTaken)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.redDim,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('TAKEN',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.red)),
              )
            else ...[
              if (price != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(AppTheme.currency(price!),
                        style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    if (changePct != null)
                      Text(
                          '${changePct! >= 0 ? '+' : ''}${changePct!.toStringAsFixed(2)}%',
                          style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: changePct! >= 0
                                  ? AppTheme.green
                                  : AppTheme.red)),
                  ],
                ),
                const SizedBox(width: 10),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.greenDim,
                  border: Border.all(color: AppTheme.greenBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('ADD',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TAB 4 — LEAGUE: trophy + matchup list (Sleeper-style)
// ─────────────────────────────────────────────────────────
class _LeagueTab extends StatefulWidget {
  final League league;
  final LeagueProvider prov;
  const _LeagueTab({required this.league, required this.prov});
  @override
  State<_LeagueTab> createState() => _LeagueTabState();
}

class _LeagueTabState extends State<_LeagueTab> {
  late int _currentWeek;

  @override
  void initState() {
    super.initState();
    _currentWeek = widget.league.calculatedWeek;
  }

  @override
  Widget build(BuildContext context) {
    final maxWeek = widget.league.calculatedWeek;
    final status = widget.league.status;
    final showTrophyAndMatchups = status == LeagueStatus.active ||
        status == LeagueStatus.playoffs ||
        status == LeagueStatus.complete;

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        // ── Waiting for Draft for pending leagues ──
        if (status == LeagueStatus.pending)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: 48, color: AppTheme.gold),
                SizedBox(height: 16),
                Text('Waiting for Draft',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Tap + Invite to invite players and start the draft',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),

        // ── Draft In Progress for drafting leagues ──
        if (status == LeagueStatus.drafting)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Icon(Icons.sports_esports_rounded,
                    color: AppTheme.green, size: 48),
                const SizedBox(height: 16),
                const Text('Draft In Progress',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'The commissioner has started the draft.\nJoin now to pick your stocks!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textMuted, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final db = FirebaseFirestore.instance;
                      final data = (await db
                              .collection('leagues')
                              .doc(widget.league.id)
                              .get())
                          .data() ?? {};
                      final rosterSize = data['rosterSize'] as int? ?? 10;
                      final draftMode = data['draftMode'] as String? ?? 'unique';
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DraftRoomScreen(
                              leagueId: widget.league.id,
                              leagueName: widget.league.name,
                              rosterSize: rosterSize,
                              draftMode: draftMode,
                            ),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Join Draft',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),

        // ── Trophy section ──
        if (showTrophyAndMatchups) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('League Trophy',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          _TrophyRow(league: widget.league, prov: widget.prov),

          // ── Matchups header + week nav ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Matchups',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                _WeekNav(
                  week: _currentWeek,
                  maxWeek: maxWeek,
                  onPrev: _currentWeek > 1
                      ? () => setState(() => _currentWeek--)
                      : null,
                  onNext: _currentWeek < maxWeek
                      ? () => setState(() => _currentWeek++)
                      : null,
                ),
              ],
            ),
          ),

          // ── Matchup cards ──
          _MatchupList(
            league: widget.league,
            prov: widget.prov,
            week: _currentWeek,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// DRAFT LOBBY — shown when league status is pending
// ─────────────────────────────────────────────────────────
class _DraftLobby extends StatefulWidget {
  final League league;
  final LeagueProvider prov;
  const _DraftLobby({required this.league, required this.prov});
  @override
  State<_DraftLobby> createState() => _DraftLobbyState();
}

class _DraftLobbyState extends State<_DraftLobby> {
  final _db = FirebaseFirestore.instance;

  String get _uid => widget.prov.uid;
  bool get _isCommissioner => widget.league.commissionerUID == _uid;

  Future<void> _toggleReady(bool currentReady) async {
    await _db
        .collection('leagues')
        .doc(widget.league.id)
        .collection('members')
        .doc(_uid)
        .set({'draftReady': !currentReady}, SetOptions(merge: true));
  }

  Future<void> _startDraft() async {
    try {
      await _db.collection('leagues').doc(widget.league.id).update({
        'status': 'drafting',
      });

      final data = (await _db.collection('leagues').doc(widget.league.id).get()).data() ?? {};
      final rosterSize = data['rosterSize'] as int? ?? 10;
      final draftMode = data['draftMode'] as String? ?? 'unique';

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DraftRoomScreen(
              leagueId: widget.league.id,
              leagueName: widget.league.name,
              rosterSize: rosterSize,
              draftMode: draftMode,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Lobby card ──
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('Draft Lobby',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text(
                          '${widget.league.members.length}/${widget.league.maxPlayers} players',
                          style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontFamily: 'Courier')),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.border),

                // Member list via StreamBuilder
                StreamBuilder<QuerySnapshot>(
                  stream: _db
                      .collection('leagues')
                      .doc(widget.league.id)
                      .collection('members')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.green, strokeWidth: 2)),
                      );
                    }

                    final memberDocs = snapshot.data!.docs;

                    return Column(
                      children: memberDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final username =
                            data['username'] as String? ?? 'Player';
                        final draftReady =
                            data['draftReady'] as bool? ?? false;
                        final isMe = doc.id == _uid;
                        final isComm = doc.id == widget.league.commissionerUID;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: const Border(
                                bottom:
                                    BorderSide(color: AppTheme.border, width: 0.5)),
                            color: isComm
                                ? AppTheme.gold.withValues(alpha: 0.04)
                                : null,
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isComm
                                      ? AppTheme.gold.withValues(alpha: 0.15)
                                      : AppTheme.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: isComm
                                      ? Border.all(
                                          color: AppTheme.gold.withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    username.isNotEmpty
                                        ? username[0].toUpperCase()
                                        : 'P',
                                    style: TextStyle(
                                        color: isComm
                                            ? AppTheme.gold
                                            : AppTheme.green,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(username,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14)),
                                    if (isComm) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.gold.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                              color: AppTheme.gold.withValues(alpha: 0.3)),
                                        ),
                                        child: const Text('COMM',
                                            style: TextStyle(
                                                color: AppTheme.gold,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'Courier')),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Ready badge or toggle
                              if (isMe)
                                GestureDetector(
                                  onTap: () => _toggleReady(draftReady),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: draftReady
                                          ? AppTheme.green
                                          : AppTheme.surface2,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: draftReady
                                              ? AppTheme.green
                                              : AppTheme.border),
                                    ),
                                    child: Text(
                                      draftReady ? 'Unready' : 'Ready Up',
                                      style: TextStyle(
                                        color: draftReady
                                            ? Colors.black
                                            : AppTheme.textMuted,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        fontFamily: 'Courier',
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: draftReady
                                        ? AppTheme.greenDim
                                        : AppTheme.surface2,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: draftReady
                                            ? AppTheme.green.withValues(alpha: 0.3)
                                            : AppTheme.border),
                                  ),
                                  child: Text(
                                    draftReady ? 'READY' : 'NOT READY',
                                    style: TextStyle(
                                      color: draftReady
                                          ? AppTheme.green
                                          : AppTheme.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                // Start Draft button (commissioner only)
                if (_isCommissioner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _startDraft,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Start Draft',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Invite code row ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('INVITE CODE',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.5)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.greenDim,
                    border: Border.all(color: AppTheme.greenBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(widget.league.inviteCode,
                      style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.green,
                          letterSpacing: 2)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: widget.league.inviteCode));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Code copied!'),
                      backgroundColor: AppTheme.green,
                      duration: Duration(seconds: 2),
                    ));
                  },
                  child: const Icon(Icons.copy_rounded,
                      size: 16, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TROPHY ROW — Champion 🏆 + Last Place 🪠
// ─────────────────────────────────────────────────────────
class _TrophyRow extends StatelessWidget {
  final League league;
  final LeagueProvider prov;
  const _TrophyRow({required this.league, required this.prov});

  @override
  Widget build(BuildContext context) {
    final memberList = prov.members[league.id] ?? [];
    final sorted = [...memberList]
      ..sort((a, b) => b.totalValue.compareTo(a.totalValue));
    final champion = sorted.isNotEmpty ? sorted.first : null;
    final lastPlace = sorted.length > 1 ? sorted.last : null;

    final isComplete = league.status == LeagueStatus.complete;
    final champLabel = isComplete ? 'CHAMPION' : 'CURRENT LEADER';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Champion / Current Leader
          Expanded(
              child: _TrophyCard(
            label: champLabel,
            emoji: '🏆',
            labelColor: const Color(0xFFFFCA47),
            bgGradient: const [Color(0xFF1a1200), Color(0xFF2a1e00)],
            borderColor: const Color(0x40FFC947),
            name: champion?.username ?? '—',
            subtitle: champion != null
                ? '${champion.wins}-${champion.losses} · \$${_fmt(champion.totalValue)}'
                : '—',
            subtitleColor: const Color(0x99FFC947),
          )),
          const SizedBox(width: 10),
          // Last place
          Expanded(
              child: _TrophyCard(
            label: 'LAST PLACE 💩',
            emoji: '🪠',
            labelColor: const Color(0xFF8B5A2B),
            bgGradient: const [Color(0xFF0d0a06), Color(0xFF1a1208)],
            borderColor: const Color(0x338B5A2B),
            name: lastPlace?.username ?? '—',
            subtitle: lastPlace != null
                ? '${lastPlace.wins}-${lastPlace.losses} · \$${_fmt(lastPlace.totalValue)}'
                : '—',
            subtitleColor: const Color(0x998B5A2B),
          )),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.toStringAsFixed(0);
}

class _TrophyCard extends StatelessWidget {
  final String label, emoji, name, subtitle;
  final Color labelColor, borderColor, subtitleColor;
  final List<Color> bgGradient;

  const _TrophyCard({
    required this.label,
    required this.emoji,
    required this.name,
    required this.subtitle,
    required this.labelColor,
    required this.borderColor,
    required this.bgGradient,
    required this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bgGradient,
          ),
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            // Banner label
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: labelColor.withValues(alpha: 0.15),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(17)),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      letterSpacing: 1.5)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  Text(emoji,
                      style: TextStyle(fontSize: 44, height: 1, shadows: [
                        Shadow(
                            color: labelColor.withValues(alpha: 0.4),
                            blurRadius: 16)
                      ])),
                  const SizedBox(height: 8),
                  Text(name,
                      style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: labelColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          color: subtitleColor)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────
// WEEK NAV
// ─────────────────────────────────────────────────────────
class _WeekNav extends StatelessWidget {
  final int week, maxWeek;
  final VoidCallback? onPrev, onNext;
  const _WeekNav(
      {required this.week, required this.maxWeek, this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          GestureDetector(
            onTap: onPrev,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.chevron_left,
                  size: 18,
                  color: onPrev != null ? AppTheme.green : AppTheme.border),
            ),
          ),
          Text('Week $week',
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.green)),
          GestureDetector(
            onTap: onNext,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.chevron_right,
                  size: 18,
                  color: onNext != null ? AppTheme.green : AppTheme.border),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────
// MATCHUP LIST — all matchups for the week with section banners
// ─────────────────────────────────────────────────────────
class _MatchupList extends StatelessWidget {
  final League league;
  final LeagueProvider prov;
  final int week;
  const _MatchupList(
      {required this.league, required this.prov, required this.week});

  @override
  Widget build(BuildContext context) {
    // TODO: Load matchups for arbitrary weeks; for now show current matchup only
    final current = prov.currentMatchups[league.id];
    final matchups = current != null ? [current] : <Matchup>[];
    if (matchups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
            child: Text('No matchups yet',
                style: TextStyle(color: AppTheme.textMuted))),
      );
    }

    final currentUid = prov.uid;
    final List<Widget> widgets = [];

    for (int i = 0; i < matchups.length; i++) {
      final mu = matchups[i];

      // Section banner logic
      if (i == matchups.length ~/ 2 && matchups.length > 2) {
        widgets.add(const _SectionBanner(
          label: '5th Place',
          color: Color(0xFFA8B8C8),
          icon: '🥈',
        ));
      }
      if (i == matchups.length - 1 && matchups.length > 3) {
        widgets.add(const _SectionBanner(
          label: 'Last Place Bracket',
          color: Color(0xFF8B5A2B),
          icon: '🪠',
        ));
      }

      final isMe = mu.homeUID == currentUid || mu.awayUID == currentUid;
      widgets.add(_MatchupCard2(
        matchup: mu,
        league: league,
        prov: prov,
        isMe: isMe,
        currentUid: currentUid,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    MatchupDetailScreen(matchupId: mu.id, league: league))),
      ));
    }

    return Column(children: widgets);
  }
}

class _SectionBanner extends StatelessWidget {
  final String label, icon;
  final Color color;
  const _SectionBanner(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color)),
            const SizedBox(width: 8),
            Text(icon, style: const TextStyle(fontSize: 14)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────
// MATCHUP CARD — Sleeper-style with win % bar
// ─────────────────────────────────────────────────────────
class _MatchupCard2 extends StatelessWidget {
  final Matchup matchup;
  final League league;
  final LeagueProvider prov;
  final bool isMe;
  final String currentUid;
  final VoidCallback onTap;

  const _MatchupCard2({
    required this.matchup,
    required this.league,
    required this.prov,
    required this.isMe,
    required this.currentUid,
    required this.onTap,
  });

  LeagueMember? _findMember(String uid) {
    final list = prov.members[league.id] ?? [];
    try {
      return list.firstWhere((m) => m.id == uid);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m1 = _findMember(matchup.homeUID);
    final m2 = _findMember(matchup.awayUID);
    final s1 = matchup.homeValue;
    final s2 = matchup.awayValue;
    final total = s1 + s2;
    final winPct = total > 0 ? (s1 / total) : 0.5;
    final m1IsMe = matchup.homeUID == currentUid;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: AppTheme.surface1,
          border:
              Border.all(color: isMe ? AppTheme.greenBorder : AppTheme.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                children: [
                  // Scores row
                  Row(
                    children: [
                      // Team 1
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _WinPctLabel(
                            pct: (winPct * 100).round(),
                            isLeading: s1 >= s2,
                            isMe: m1IsMe,
                          ),
                          Text('\$${_fmt(s1)}',
                              style: TextStyle(
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color:
                                      m1IsMe ? AppTheme.green : AppTheme.text)),
                          Text(_pctLabel(s1),
                              style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10,
                                  color: _pctColor(s1))),
                        ],
                      )),
                      // VS pill
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppTheme.surface2,
                          border: Border.all(color: AppTheme.border),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                            child: Text('VS',
                                style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 8,
                                    color: AppTheme.textMuted))),
                      ),
                      // Team 2
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _WinPctLabel(
                            pct: (100 - winPct * 100).round(),
                            isLeading: s2 > s1,
                            isMe: !m1IsMe && isMe,
                            align: TextAlign.right,
                          ),
                          Text('\$${_fmt(s2)}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: (!m1IsMe && isMe)
                                      ? AppTheme.green
                                      : AppTheme.text)),
                          Text(_pctLabel(s2),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 10,
                                  color: _pctColor(s2))),
                        ],
                      )),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Win probability bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      height: 4,
                      color: Colors.white.withValues(alpha: 0.06),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: winPct,
                        child: Container(
                            color: m1IsMe ? AppTheme.green : AppTheme.blue),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Team names
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${m1IsMe ? 'You' : (m1?.username ?? '—')}${m1IsMe ? ' ◀' : ''}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      m1IsMe ? AppTheme.green : AppTheme.text)),
                          Text(
                              '${m1?.record ?? '—'} · #${m1?.seed ?? '?'} seed',
                              style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 9,
                                  color: AppTheme.textMuted)),
                        ],
                      )),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                              (!m1IsMe && isMe)
                                  ? 'You ◀'
                                  : (m2?.username ?? '—'),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: (!m1IsMe && isMe)
                                      ? AppTheme.green
                                      : AppTheme.text)),
                          Text(
                              '${m2?.record ?? '—'} · #${m2?.seed ?? '?'} seed',
                              style: const TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 9,
                                  color: AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.toStringAsFixed(0);

  String _pctLabel(double value) {
    final sb = league.startingBalance;
    if (sb == 0) return '0.00%';
    final pct = ((value - sb) / sb) * 100;
    return '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
  }

  Color _pctColor(double value) {
    return value >= league.startingBalance ? AppTheme.green : AppTheme.red;
  }
}

class _WinPctLabel extends StatelessWidget {
  final int pct;
  final bool isLeading, isMe;
  final TextAlign align;
  const _WinPctLabel({
    required this.pct,
    required this.isLeading,
    required this.isMe,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) => Text(
        '$pct% WIN${pct == 100 ? ' 🏆' : ''}',
        textAlign: align,
        style: TextStyle(
            fontFamily: 'Courier',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isLeading
                ? (isMe ? AppTheme.green : AppTheme.text)
                : AppTheme.textMuted),
      );
}

// ─────────────────────────────────────────────────────────
// MATCHUP DETAIL CARD (used in MATCH tab)
// ─────────────────────────────────────────────────────────
// ── Points scoring helper ──
int _weeklyPoints(double pctChange) {
  if (pctChange >= 10) return 100;
  if (pctChange >= 7) return 75;
  if (pctChange >= 5) return 50;
  if (pctChange >= 3) return 35;
  if (pctChange >= 1) return 20;
  if (pctChange >= 0) return 10;
  return 5;
}

double _pctChangeFor(double value, double startingBalance) {
  if (startingBalance == 0) return 0;
  return ((value - startingBalance) / startingBalance) * 100;
}

class _MatchupDetailCard extends StatelessWidget {
  final Matchup matchup;
  final double startingBalance;
  const _MatchupDetailCard({required this.matchup, required this.startingBalance});

  @override
  Widget build(BuildContext context) {
    final homePct = _pctChangeFor(matchup.homeValue, startingBalance);
    final awayPct = _pctChangeFor(matchup.awayValue, startingBalance);
    final homePts = _weeklyPoints(homePct);
    final awayPts = _weeklyPoints(awayPct);
    final homeLeading = homePct >= awayPct;
    final total = matchup.homeValue + matchup.awayValue;
    final winPct = total > 0 ? (matchup.homeValue / total) : 0.5;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        border: Border.all(color: AppTheme.greenBorder.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text('WEEK ${matchup.week} · IN PROGRESS',
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  letterSpacing: 1)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MatchupSide(
                init: 'YO',
                name: 'You',
                record: '—',
                pctChange: homePct,
                projPts: homePts,
                isMe: true,
                align: CrossAxisAlignment.start,
              ),
              Column(children: [
                const Text('VS',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 13,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: homeLeading ? AppTheme.greenDim : AppTheme.redDim,
                    border: Border.all(
                        color: homeLeading
                            ? AppTheme.greenBorder
                            : AppTheme.red.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(homeLeading ? 'YOU LEAD' : 'TRAILING',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 9,
                          color: homeLeading ? AppTheme.green : AppTheme.red,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              _MatchupSide(
                init: matchup.awayUsername.isNotEmpty
                    ? matchup.awayUsername.substring(0, 2).toUpperCase()
                    : 'OP',
                name: matchup.awayUsername,
                record: '—',
                pctChange: awayPct,
                projPts: awayPts,
                isMe: false,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 5,
              color: Colors.white.withValues(alpha: 0.06),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: winPct,
                child: Container(color: AppTheme.green),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$homePts pts',
                  style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold)),
              Text('Lead: ${(homePct - awayPct).abs().toStringAsFixed(2)}%',
                  style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 9,
                      color: AppTheme.textMuted)),
              Text('$awayPts pts',
                  style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gold)),
            ],
          ),

          // Scoring legend
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              border: Border.all(color: AppTheme.border2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SCORING',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 8,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.5)),
                SizedBox(height: 6),
                _ScoreLegendRow('+10%+', '100'),
                _ScoreLegendRow('+7-9.99%', '75'),
                _ScoreLegendRow('+5-6.99%', '50'),
                _ScoreLegendRow('+3-4.99%', '35'),
                _ScoreLegendRow('+1-2.99%', '20'),
                _ScoreLegendRow('0-0.99%', '10'),
                _ScoreLegendRow('Negative', '5'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreLegendRow extends StatelessWidget {
  final String range, pts;
  const _ScoreLegendRow(this.range, this.pts);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(range,
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 9,
                    color: AppTheme.textMuted)),
            Text('$pts pts',
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gold)),
          ],
        ),
      );
}

class _MatchupSide extends StatelessWidget {
  final String init, name, record;
  final double pctChange;
  final int projPts;
  final bool isMe;
  final CrossAxisAlignment align;

  const _MatchupSide({
    required this.init,
    required this.name,
    required this.record,
    required this.pctChange,
    required this.projPts,
    required this.isMe,
    required this.align,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isMe
                        ? [const Color(0xFF0A2A0A), AppTheme.green]
                        : [const Color(0xFF2A2A4A), const Color(0xFF4A4A8A)]),
                borderRadius: BorderRadius.circular(13)),
            child: Center(
                child: Text(init,
                    style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isMe ? Colors.black : Colors.white))),
          ),
          const SizedBox(height: 5),
          Text(name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isMe ? AppTheme.green : AppTheme.text)),
          Text(record,
              style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 10,
                  color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text('${pctChange >= 0 ? '+' : ''}${pctChange.toStringAsFixed(2)}%',
              style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: pctChange >= 0 ? AppTheme.green : AppTheme.red)),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x1AFFD700),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$projPts pts',
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gold)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────
// HOLDINGS CARD
// ─────────────────────────────────────────────────────────
class _DraftPickTile extends StatelessWidget {
  final DraftPick pick;
  const _DraftPickTile({required this.pick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          Container(
              width: 3,
              height: 32,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                  color: AppTheme.green,
                  borderRadius: BorderRadius.circular(2))),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(pick.symbol,
                  style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              Text(pick.companyName,
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(AppTheme.currency(pick.priceAtDraft, decimals: 2),
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            Text('Rd ${pick.round} · #${pick.pickNumber}',
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: AppTheme.textMuted)),
          ]),
        ],
      ),
    );
  }
}

class _LeagueHoldingsCard extends StatelessWidget {
  final String leagueId;
  final LeagueProvider prov;
  const _LeagueHoldingsCard({required this.leagueId, required this.prov});

  @override
  Widget build(BuildContext context) {
    final uid = prov.uid;
    return StreamBuilder<List<DraftPick>>(
      stream: prov.draftPicksStream(leagueId),
      builder: (context, snap) {
        final myPicks = (snap.data ?? [])
            .where((p) => p.pickedByUID == uid)
            .toList();
        if (myPicks.isEmpty) {
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppTheme.surface1,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('No picks yet',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            color: AppTheme.surface1,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: myPicks
                .map((pick) => _DraftPickTile(pick: pick))
                .toList(),
          ),
        );
      },
    );
  }
}


// ─────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 1.5)),
      );
}

// ─────────────────────────────────────────────────────────
// NO LEAGUE VIEW
// ─────────────────────────────────────────────────────────
class _NoLeagueView extends StatelessWidget {
  final VoidCallback onGetStarted;
  const _NoLeagueView({required this.onGetStarted});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🏈', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          const Text("You're not in a league yet",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Create or join one to start competing',
              style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 20),
          ElevatedButton(
              onPressed: onGetStarted, child: const Text('Get Started')),
        ]),
      );
}

// ─────────────────────────────────────────────────────────
// MATCHUP DETAIL SCREEN (tapped from league)
// ─────────────────────────────────────────────────────────
class MatchupDetailScreen extends StatelessWidget {
  final String matchupId;
  final League league;
  const MatchupDetailScreen(
      {super.key, required this.matchupId, required this.league});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<LeagueProvider>();
    final matchup = prov.currentMatchups.values
        .where((m) => m != null && m.id == matchupId)
        .map((m) => m!)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Matchup'),
      ),
      body: matchup == null
          ? const Center(
              child: Text('Matchup not found',
                  style: TextStyle(color: AppTheme.textMuted)))
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              _MatchupDetailCard(matchup: matchup, startingBalance: league.startingBalance),
              const _SectionLabel('HOLDINGS'),
              _LeagueHoldingsCard(leagueId: matchup.leagueId, prov: prov),
            ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// DRAFT SCREEN — Sleeper-style
// Snake board + Manager strip + Bottom panel with live search
// ─────────────────────────────────────────────────────────
class DraftScreen extends StatefulWidget {
  final League league;
  const DraftScreen({super.key, required this.league});
  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _boardScrollCtrl = ScrollController();

  // Search state
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _lastQuery = '';
  Timer? _debounce;

  // Sector filter
  String _activeSector = 'ALL';
  static const List<String> sectors = [
    'ALL',
    'Tech',
    'Finance',
    'EV/Auto',
    'Crypto',
    'Consumer',
    'Energy'
  ];

  // Draft state
  int _timerSecs = 60;
  Timer? _timer;

  // My picks this session
  final List<Map<String, dynamic>> _myPicks = [];

  // Queue state — stocks the user wants to draft next
  final List<Map<String, dynamic>> _queue = [];

  // Live draft picks from Firestore
  List<DraftPick> _livePicks = [];
  StreamSubscription? _draftSub;
  Set<String> _takenSymbols = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _startTimer();
    _runSearch('');
    _subscribeToDraft();
  }

  /// Listen to Firestore draft picks in real time
  void _subscribeToDraft() {
    final prov = context.read<LeagueProvider>();
    _draftSub = prov.draftPicksStream(widget.league.id).listen((picks) {
      if (!mounted) return;
      setState(() {
        _livePicks = picks;
        _takenSymbols = picks.map((p) => p.symbol).toSet();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_boardScrollCtrl.hasClients) {
          _boardScrollCtrl.animateTo(
            _boardScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _boardScrollCtrl.dispose();
    _debounce?.cancel();
    _timer?.cancel();
    _draftSub?.cancel();
    super.dispose();
  }

  // ── Timer ──
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_timerSecs > 0) {
        setState(() => _timerSecs--);
      } else {
        // Timer hit 0 — auto-draft for whoever's turn it is
        final idx = _currentTurnMemberIndex();
        if (idx >= 0) {
          final available = _defaultPool()
              .where((s) => !_takenSymbols.contains(s['symbol'] as String))
              .toList();
          if (available.isNotEmpty) {
            final pick = available[Random().nextInt(available.length)];
            final sym = pick['symbol'] as String;

            if (_isMyTurn()) {
              // Auto-pick for current user
              _confirmPick(pick);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('\u23f0 Time\'s up! Auto-drafted $sym for you'),
                  backgroundColor: AppTheme.red,
                  duration: const Duration(seconds: 2),
                ));
              }
            } else {
              // Auto-pick for another real player
              _autoPickForPlayer(idx, pick);
            }
          }
        }
        _resetTimer();
      }
    });
  }

  void _resetTimer() {
    setState(() => _timerSecs = 60);
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Reset draft?'),
        content: const Text('This will clear all picks.',
            style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetDraft();
            },
            child: const Text('Reset', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _resetDraft() async {
    final db = FirebaseFirestore.instance;
    final leagueId = widget.league.id;
    final picksSnap = await db
        .collection('leagues')
        .doc(leagueId)
        .collection('draft')
        .doc('state')
        .collection('picks')
        .get();
    final batch = db.batch();
    for (final doc in picksSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.set(
      db.collection('leagues').doc(leagueId).collection('draft').doc('state'),
      {
        'currentPick': 1,
        'currentRound': 1,
        'isComplete': false,
        'secondsRemaining': 60,
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    setState(() {
      _myPicks.clear();
      _livePicks.clear();
    });
    _resetTimer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Draft reset!'),
        backgroundColor: AppTheme.green,
        duration: Duration(seconds: 2),
      ));
    }
  }

  // ── Search (uses same Finnhub endpoint as SearchScreen) ──
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _lastQuery = query;
    });

    final prov = context.read<PortfolioProvider>();

    if (query.trim().isEmpty) {
      // Show default pool when empty
      final defaults = _defaultPool();
      if (!mounted) return;
      setState(() {
        _searchResults = defaults;
        _isSearching = false;
      });
      return;
    }

    try {
      final results = await prov.searchStocks(query);
      if (!mounted || _lastQuery != query) return;

      // Fetch live prices in parallel (capped at 10)
      final limited = results.take(10).toList();
      final withPrices = await Future.wait(limited.map((r) async {
        try {
          final q = await prov.fetchQuote(r.symbol);
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': q?.currentPrice ?? 0.0,
            'change': q?.change ?? 0.0,
            'changePct': q?.changePercent ?? 0.0,
            'sector': _guessSector(r.symbol),
          };
        } catch (_) {
          return {
            'symbol': r.symbol,
            'name': r.description.isNotEmpty ? r.description : r.symbol,
            'price': 0.0,
            'change': 0.0,
            'changePct': 0.0,
            'sector': 'Other',
          };
        }
      }));

      if (!mounted) return;
      setState(() {
        _searchResults = withPrices;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
      });
    }
  }

  List<Map<String, dynamic>> _defaultPool() => [
        {
          'symbol': 'NVDA',
          'name': 'NVIDIA Corp.',
          'price': 875.40,
          'changePct': 3.21,
          'sector': 'Tech'
        },
        {
          'symbol': 'AAPL',
          'name': 'Apple Inc.',
          'price': 189.30,
          'changePct': 1.42,
          'sector': 'Tech'
        },
        {
          'symbol': 'TSLA',
          'name': 'Tesla Inc.',
          'price': 248.10,
          'changePct': -2.31,
          'sector': 'EV/Auto'
        },
        {
          'symbol': 'MSFT',
          'name': 'Microsoft Corp.',
          'price': 415.20,
          'changePct': 0.83,
          'sector': 'Tech'
        },
        {
          'symbol': 'META',
          'name': 'Meta Platforms',
          'price': 519.80,
          'changePct': 1.95,
          'sector': 'Tech'
        },
        {
          'symbol': 'AMZN',
          'name': 'Amazon.com',
          'price': 198.45,
          'changePct': 0.55,
          'sector': 'Consumer'
        },
        {
          'symbol': 'GOOGL',
          'name': 'Alphabet Inc.',
          'price': 172.30,
          'changePct': -0.42,
          'sector': 'Tech'
        },
        {
          'symbol': 'AMD',
          'name': 'Adv. Micro Devices',
          'price': 178.90,
          'changePct': 2.88,
          'sector': 'Tech'
        },
        {
          'symbol': 'PLTR',
          'name': 'Palantir Technologies',
          'price': 24.82,
          'changePct': 5.14,
          'sector': 'Tech'
        },
        {
          'symbol': 'COIN',
          'name': 'Coinbase Global',
          'price': 198.30,
          'changePct': -4.22,
          'sector': 'Crypto'
        },
        {
          'symbol': 'JPM',
          'name': 'JPMorgan Chase',
          'price': 196.50,
          'changePct': 0.35,
          'sector': 'Finance'
        },
        {
          'symbol': 'HOOD',
          'name': 'Robinhood Markets',
          'price': 18.75,
          'changePct': 6.20,
          'sector': 'Finance'
        },
        {
          'symbol': 'RIVN',
          'name': 'Rivian Automotive',
          'price': 11.42,
          'changePct': -5.80,
          'sector': 'EV/Auto'
        },
        {
          'symbol': 'MSTR',
          'name': 'MicroStrategy',
          'price': 1680.0,
          'changePct': 8.50,
          'sector': 'Crypto'
        },
        {
          'symbol': 'XOM',
          'name': 'Exxon Mobil',
          'price': 113.20,
          'changePct': -0.85,
          'sector': 'Energy'
        },
        {
          'symbol': 'SPY',
          'name': 'S&P 500 ETF',
          'price': 524.30,
          'changePct': 0.31,
          'sector': 'Finance'
        },
      ];

  String _guessSector(String sym) {
    const map = {
      'Tech': [
        'NVDA',
        'AAPL',
        'MSFT',
        'META',
        'GOOGL',
        'AMD',
        'PLTR',
        'SHOP',
        'DDOG',
        'CRWD',
        'SNAP',
        'RBLX'
      ],
      'Finance': ['JPM', 'BAC', 'GS', 'V', 'MA', 'HOOD', 'SOFI', 'PYPL', 'SPY'],
      'EV/Auto': ['TSLA', 'RIVN', 'NIO', 'F', 'GM'],
      'Crypto': ['COIN', 'MSTR', 'BTC', 'ETH'],
      'Consumer': [
        'AMZN',
        'NFLX',
        'DIS',
        'UBER',
        'SPOT',
        'BABA',
        'ABNB',
        'WMT',
        'COST'
      ],
      'Energy': ['XOM', 'CVX'],
    };
    for (final entry in map.entries) {
      if (entry.value.contains(sym)) return entry.key;
    }
    return 'Other';
  }

  // ── Draft a stock ──
  bool _isTaken(String symbol) {
    if (!widget.league.isUniqueDraft) return false;
    return _takenSymbols.contains(symbol) ||
        _myPicks.any((p) => p['symbol'] == symbol);
  }

  // ── Queue helpers ──
  bool _isQueued(String symbol) => _queue.any((q) => q['symbol'] == symbol);

  void _addToQueue(Map<String, dynamic> stock) {
    if (_isQueued(stock['symbol'] as String)) return;
    setState(() => _queue.add(stock));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('📋 ${stock['symbol']} added to queue'),
      backgroundColor: const Color(0xFF1a2535),
      duration: const Duration(seconds: 1),
    ));
  }

  void _removeFromQueue(int index) {
    setState(() => _queue.removeAt(index));
  }

  void _draftFromQueue(int index) {
    final stock = _queue[index];
    setState(() => _queue.removeAt(index));
    _openConfirm(stock);
  }

  /// Returns the member index (into widget.league.members) whose turn it is,
  /// or -1 if the draft is complete / index is out of range.
  int _currentTurnMemberIndex() {
    final numPlayers = widget.league.members.length;
    if (numPlayers == 0) return -1;
    final pickNum = _livePicks.length + 1;
    final round = (pickNum - 1) ~/ numPlayers;
    final pos = (pickNum - 1) % numPlayers;
    final memberIndex = round % 2 == 0 ? pos : (numPlayers - 1 - pos);
    if (memberIndex >= numPlayers) return -1;
    return memberIndex;
  }

  bool _isMyTurn() {
    final idx = _currentTurnMemberIndex();
    if (idx < 0) return false;
    final currentUid = context.read<LeagueProvider>().uid;
    return widget.league.members[idx] == currentUid;
  }

  /// Auto-draft a random stock on behalf of another player whose timer expired.
  Future<void> _autoPickForPlayer(
      int memberIndex, Map<String, dynamic> stock) async {
    final prov = context.read<LeagueProvider>();
    final memberList = prov.members[widget.league.id] ?? [];
    // Find the LeagueMember matching this UID
    final memberUid = widget.league.members[memberIndex];
    final member = memberList.firstWhere(
      (m) => m.id == memberUid,
      orElse: () => LeagueMember(
        id: memberUid,
        username: 'Player ${memberIndex + 1}',
        leagueId: widget.league.id,
        wins: 0,
        losses: 0,
        totalValue: widget.league.startingBalance,
        cashBalance: widget.league.startingBalance,
        seed: memberIndex + 1,
        isEliminated: false,
      ),
    );

    final sym = stock['symbol'] as String;
    final numPlayers = widget.league.members.length;
    final db = FirebaseFirestore.instance;
    final leagueId = widget.league.id;
    final pickNum = _livePicks.length + 1;
    final currentRound = (pickNum - 1) ~/ numPlayers + 1;

    final pickDoc = {
      'id': db.collection('x').doc().id,
      'leagueId': leagueId,
      'round': currentRound,
      'pickNumber': pickNum,
      'pickedByUID': member.id,
      'pickedByUsername': member.username,
      'symbol': sym,
      'companyName': stock['name'] as String? ?? sym,
      'priceAtDraft': (stock['price'] as num?)?.toDouble() ?? 0.0,
      'timestamp': DateTime.now(),
    };

    await db
        .collection('leagues')
        .doc(leagueId)
        .collection('draft')
        .doc('state')
        .collection('picks')
        .doc(pickDoc['id'] as String)
        .set(pickDoc);

    final nextPick = pickNum + 1;
    final nextRound = ((nextPick - 1) ~/ numPlayers) + 1;
    const totalRounds = 11;
    final done = nextRound > totalRounds;

    await db
        .collection('leagues')
        .doc(leagueId)
        .collection('draft')
        .doc('state')
        .set({
      'currentPick': nextPick,
      'currentRound': nextRound,
      'isComplete': done,
      'secondsRemaining': 60,
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '\u23f0 ${member.username} ran out of time - auto-drafted $sym'),
        backgroundColor: AppTheme.red,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _openConfirm(Map<String, dynamic> stock) {
    if (!_isMyTurn()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not your turn!'),
        backgroundColor: AppTheme.red,
        duration: Duration(seconds: 2),
      ));
      return;
    }
    if (_isTaken(stock['symbol'])) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${stock['symbol']} is already drafted!'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }
    _showConfirmSheet(stock);
  }

  void _showConfirmSheet(Map<String, dynamic> stock) {
    final sym = stock['symbol'] as String;
    final name = stock['name'] as String;
    final price = (stock['price'] as num).toDouble();
    final pct = (stock['changePct'] as num).toDouble();
    final up = pct >= 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E1117),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.border2,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('🎯 Confirm Draft Pick',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            // Stock info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                border: Border.all(
                    color: AppTheme.greenBorder.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppTheme.greenDim,
                      border: Border.all(color: AppTheme.greenBorder),
                      borderRadius: BorderRadius.circular(9)),
                  child: Text(sym,
                      style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.green)),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(
                        widget.league.isUniqueDraft
                            ? '🏈 Fantasy Style'
                            : '📈 Open Picks',
                        style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 10,
                            color: AppTheme.textMuted)),
                  ],
                )),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(price > 0 ? AppTheme.currency(price) : '—',
                      style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('${up ? '▲ +' : '▼ '}${pct.abs().toStringAsFixed(2)}%',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: up ? AppTheme.green : AppTheme.red)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            Text(
                widget.league.isUniqueDraft
                    ? 'This pick cannot be undone. $sym will be locked — no other player can draft it.'
                    : 'Other players can still pick $sym in Open Picks mode.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    height: 1.6)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: AppTheme.border)),
                      child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmPick(stock);
                      },
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          backgroundColor: AppTheme.green,
                          foregroundColor: Colors.black),
                      child: const Text('Draft It! 🎯',
                          style: TextStyle(fontWeight: FontWeight.w800)))),
            ]),
          ],
        ),
      ),
    );
  }

  void _confirmPick(Map<String, dynamic> stock) {
    if (!_isMyTurn()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not your turn!'),
        backgroundColor: AppTheme.red,
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final sym = stock['symbol'] as String;
    final prov = context.read<LeagueProvider>();
    prov.makePick(widget.league.id, sym, stock['name'] as String? ?? sym,
        (stock['price'] as num?)?.toDouble() ?? 0.0, {
      'draftMode': widget.league.draftMode,
      'currentRound': _myPicks.length ~/ (widget.league.members.length) + 1,
      'currentPick': _myPicks.length + 1,
      'pickOrder': widget.league.members,
      'totalRounds': 11,
    });
    setState(() {
      _myPicks.add({...stock, 'round': 2, 'pick': _myPicks.length + 1});
    });
    _searchCtrl.clear();
    _runSearch('');
    _resetTimer();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('🎯 You drafted $sym!'),
      backgroundColor: AppTheme.green,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── BUILD ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildMgrStrip(),
            _buildBoard(),
            _buildClockBar(),
            _buildPanelTabs(),
            Expanded(
                child: TabBarView(
              controller: _tabController,
              children: [
                _buildStocksPanel(),
                _buildQueuePanel(),
                _buildMyPicksPanel(),
                _buildChatPanel(),
              ],
            )),
          ],
        ),
      ),
    );
  }

  // ── TOP BAR ──
  Widget _buildTopBar() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Row(
          children: [
            GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios,
                    size: 16, color: AppTheme.green)),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Draft Room',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(widget.league.name,
                    style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 9,
                        color: AppTheme.textMuted)),
              ],
            )),
            GestureDetector(
              onTap: _showResetDialog,
              child: Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppTheme.redDim,
                  border:
                      Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.restart_alt,
                    size: 16, color: AppTheme.red),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.greenDim,
                  border: Border.all(color: AppTheme.greenBorder),
                  borderRadius: BorderRadius.circular(100)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('⏱ ',
                    style: TextStyle(fontSize: 11, color: AppTheme.green)),
                Text('$_timerSecs s',
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            _timerSecs <= 10 ? AppTheme.red : AppTheme.green)),
              ]),
            ),
          ],
        ),
      );

  // ── MANAGER STRIP ──
  Widget _buildMgrStrip() {
    final prov = context.read<LeagueProvider>();
    final memberList = prov.members[widget.league.id] ?? [];
    return Container(
      height: 46,
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: memberList.length,
        itemBuilder: (_, i) {
          final m = memberList[i];
          final isMe = m.id == prov.uid;
          final initials = _pickInitials(m.username);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: isMe ? AppTheme.green : Colors.transparent,
                        width: 2))),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius: BorderRadius.circular(6)),
                  child: Center(
                      child: Text(initials,
                          style: const TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: Colors.white))),
                ),
                const SizedBox(width: 5),
                Text(isMe ? 'You' : m.username,
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: isMe ? AppTheme.green : AppTheme.textMuted)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── SNAKE BOARD ──
  Widget _buildBoard() {
    // Use maxPlayers so the full grid shows even before all players join
    final cols = widget.league.maxPlayers.clamp(2, 20);
    const totalRounds = 11;
    final leagueProv = context.read<LeagueProvider>();
    final memberList = leagueProv.members[widget.league.id] ?? [];

    // Build a map of pickNumber → DraftPick for quick lookup
    final pickMap = <int, DraftPick>{};
    for (final p in _livePicks) {
      pickMap[p.pickNumber] = p;
    }

    return Container(
      height: 200,
      decoration: const BoxDecoration(
          color: Color(0xFF050810),
          border: Border(bottom: BorderSide(color: AppTheme.border, width: 2))),
      child: SingleChildScrollView(
        controller: _boardScrollCtrl,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            children: List.generate(totalRounds, (r) {
              return Row(
                children: List.generate(cols, (c) {
                  // Snake draft: odd rounds go right-to-left
                  final snakeC = r % 2 == 1 ? (cols - 1 - c) : c;
                  // Pick number is 1-indexed: round * cols + column + 1
                  final pickNum = r * cols + snakeC + 1;

                  // Check if this slot has a real pick
                  final pick = pickMap[pickNum];
                  if (pick != null) {
                    return _buildPickCard(pick, r + 1);
                  }

                  // Empty slot placeholder
                  final username = snakeC < memberList.length
                      ? memberList[snakeC].username
                      : 'Player ${snakeC + 1}';
                  final initials = _pickInitials(username);

                  return Container(
                    width: 68,
                    height: 62,
                    margin: const EdgeInsets.all(1),
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E18),
                      border: Border.all(
                          color: AppTheme.border.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r + 1}.${snakeC + 1}',
                            style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 8,
                                color:
                                    AppTheme.textMuted.withValues(alpha: 0.4))),
                        const Spacer(),
                        Text('—',
                            style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color:
                                    AppTheme.textMuted.withValues(alpha: 0.2),
                                height: 1.1)),
                        Text(initials,
                            style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 8,
                                color:
                                    AppTheme.textMuted.withValues(alpha: 0.3))),
                      ],
                    ),
                  );
                }),
              );
            }),
          ),
        ),
      ),
    );
  }

  static const Map<String, Color> _sectorBg = {
    'Tech': Color(0xFF0E1F30),
    'Finance': Color(0xFF201800),
    'EV/Auto': Color(0xFF200A0A),
    'Crypto': Color(0xFF140A28),
    'Consumer': Color(0xFF0A1E0A),
    'Energy': Color(0xFF0A1E14),
  };
  static const Map<String, Color> _sectorFg = {
    'Tech': Color(0xFF4FC3F7),
    'Finance': Color(0xFFFFC947),
    'EV/Auto': Color(0xFFFF6B6B),
    'Crypto': Color(0xFFB388FF),
    'Consumer': Color(0xFFFF9F43),
    'Energy': Color(0xFF26DE81),
  };

  String _pickInitials(String name) {
    if (name.isEmpty) return '??';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Widget _buildPickCard(DraftPick pick, int round) {
    final sec = _guessSector(pick.symbol);
    final bg = _sectorBg[sec] ?? const Color(0xFF111827);
    final fg = _sectorFg[sec] ?? AppTheme.textMuted;
    final initials = _pickInitials(pick.pickedByUsername);

    return Container(
      width: 68,
      height: 62,
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '$round.${((pick.pickNumber - 1) % widget.league.maxPlayers) + 1}',
              style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 8,
                  color: fg.withValues(alpha: 0.6))),
          Text(pick.symbol,
              style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.1)),
          Text(initials,
              style: TextStyle(fontFamily: 'Courier', fontSize: 8, color: fg)),
        ],
      ),
    );
  }

  // ── CLOCK BAR ──
  Widget _buildClockBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: AppTheme.green.withValues(alpha: 0.04),
            border: Border(
                bottom:
                    BorderSide(color: AppTheme.green.withValues(alpha: 0.12)))),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0A2A0A), AppTheme.green]),
                borderRadius: BorderRadius.circular(10)),
            child: const Center(
                child: Text('YO',
                    style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.black))),
          ),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⏰ ON THE CLOCK · RD 2 · PICK #9',
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: AppTheme.green,
                      fontWeight: FontWeight.w700)),
              Text("You're up! Make your pick.",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('PICK TIMER',
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 9,
                    color: AppTheme.textMuted)),
            Text('$_timerSecs',
                style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: _timerSecs <= 10 ? AppTheme.red : AppTheme.green)),
          ]),
        ]),
      );

  // ── PANEL TABS ──
  Widget _buildPanelTabs() => Container(
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.green,
          indicatorWeight: 2,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5),
          tabs: const [
            Tab(text: 'STOCKS'),
            Tab(text: 'QUEUE'),
            Tab(text: 'MY PICKS'),
            Tab(text: 'CHAT'),
          ],
        ),
      );

  // ── STOCKS PANEL ──
  Widget _buildStocksPanel() => Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border))),
            child: Row(children: [
              const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search any stock to draft...',
                  hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              )),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      _runSearch('');
                    },
                    child: const Icon(Icons.close,
                        size: 16, color: AppTheme.textMuted)),
            ]),
          ),

          // Sector chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: sectors.map((s) {
                final on = s == _activeSector;
                final fg = _sectorFg[s] ?? AppTheme.green;
                final bg = _sectorBg[s] ?? AppTheme.surface2;
                return GestureDetector(
                  onTap: () => setState(() {
                    _activeSector = s;
                    _runSearch(_searchCtrl.text);
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: on
                            ? (s == 'ALL' ? AppTheme.green : bg)
                            : AppTheme.surface1,
                        border: Border.all(
                            color: on
                                ? (s == 'ALL'
                                    ? AppTheme.green
                                    : fg.withValues(alpha: 0.5))
                                : AppTheme.border),
                        borderRadius: BorderRadius.circular(100)),
                    child: Text(s,
                        style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 10,
                            color: on
                                ? (s == 'ALL' ? Colors.black : fg)
                                : AppTheme.textMuted)),
                  ),
                );
              }).toList(),
            ),
          ),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.green, strokeWidth: 2))
                : _buildStockList(),
          ),
        ],
      );

  Widget _buildStockList() {
    var list = _searchResults;

    // Apply sector filter
    if (_activeSector != 'ALL') {
      list = list.where((s) => s['sector'] == _activeSector).toList();
    }

    // If search text doesn't match anything, show Draft Anyway
    if (list.isEmpty && _searchCtrl.text.trim().isNotEmpty) {
      final q = _searchCtrl.text.trim().toUpperCase();
      return ListView(padding: const EdgeInsets.all(14), children: [
        const Text('NOT IN LIST — DRAFT ANYWAY?',
            style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _openConfirm({
            'symbol': q,
            'name': '$q (Custom Pick)',
            'price': 0.0,
            'changePct': 0.0,
            'sector': 'Other'
          }),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppTheme.greenDim,
                border: Border.all(color: AppTheme.greenBorder),
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.greenDim,
                      border: Border.all(color: AppTheme.greenBorder),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(q,
                      style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.green))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Draft "$q"',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const Text('Any valid ticker · live price at draft time',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 9,
                          color: AppTheme.textMuted)),
                ],
              )),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppTheme.green,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('DRAFT',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.black))),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
            child: Text('Try exact ticker: NVDA, SPY, BRK.B…',
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: AppTheme.textMuted))),
      ]);
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final s = list[i];
        final sym = s['symbol'] as String;
        final taken = _isTaken(sym);
        final pct = (s['changePct'] as num).toDouble();
        final up = pct >= 0;
        final sec = s['sector'] as String? ?? 'Other';
        final fg = _sectorFg[sec] ?? AppTheme.textMuted;
        final bg = _sectorBg[sec] ?? AppTheme.surface2;

        return GestureDetector(
          onTap: () => _openConfirm(s),
          child: Opacity(
            opacity: taken ? 0.3 : 1.0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border))),
              child: Row(children: [
                // Sector badge
                SizedBox(
                  width: 54,
                  child: Column(children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                            color: bg,
                            border:
                                Border.all(color: fg.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(7)),
                        child: Text(sym,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: fg))),
                    const SizedBox(height: 2),
                    Text(sec,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Courier', fontSize: 7, color: fg)),
                  ]),
                ),
                const SizedBox(width: 10),
                // Name + taken indicator
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'] as String,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(
                        taken
                            ? '⛔ Already drafted'
                            : AppTheme.currency((s['price'] as num).toDouble()),
                        style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 9,
                            color: taken ? AppTheme.red : AppTheme.textMuted)),
                  ],
                )),
                // Price + change
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(AppTheme.currency((s['price'] as num).toDouble()),
                      style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  Text('${up ? '▲ +' : '▼ '}${pct.abs().toStringAsFixed(2)}%',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: up ? AppTheme.green : AppTheme.red)),
                ]),
                const SizedBox(width: 6),
                // + Queue button
                GestureDetector(
                  onTap:
                      (taken || _isQueued(sym)) ? null : () => _addToQueue(s),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color:
                          _isQueued(sym) ? AppTheme.surface2 : AppTheme.surface,
                      border: Border.all(
                        color: _isQueued(sym)
                            ? AppTheme.green.withValues(alpha: 0.3)
                            : AppTheme.border,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      _isQueued(sym) ? Icons.check : Icons.add,
                      size: 14,
                      color:
                          _isQueued(sym) ? AppTheme.green : AppTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Draft button
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                      color: taken ? AppTheme.redDim : AppTheme.green,
                      border: taken
                          ? Border.all(
                              color: AppTheme.red.withValues(alpha: 0.3))
                          : null,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(taken ? 'TAKEN' : 'DRAFT',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: taken ? AppTheme.red : Colors.black)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ── QUEUE PANEL ──
  Widget _buildQueuePanel() {
    if (_queue.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('📋', style: TextStyle(fontSize: 36)),
          SizedBox(height: 8),
          Text('Queue is empty',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Tap + on any stock to add it here',
              style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 10,
                  color: AppTheme.textMuted)),
        ]),
      );
    }

    return ReorderableListView.builder(
      itemCount: _queue.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _queue.removeAt(oldIndex);
          _queue.insert(newIndex, item);
        });
      },
      itemBuilder: (_, i) {
        final s = _queue[i];
        final sym = s['symbol'] as String;
        final sec = s['sector'] as String? ?? 'Other';
        final fg = _sectorFg[sec] ?? AppTheme.textMuted;
        final bg = _sectorBg[sec] ?? AppTheme.surface2;
        final price = (s['price'] as num).toDouble();
        final taken = _isTaken(sym);

        return Container(
          key: ValueKey('queue_$sym'),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            const Icon(Icons.drag_handle_rounded,
                size: 16, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              child: Text('${i + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted)),
            ),
            const SizedBox(width: 8),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: fg.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(7)),
                child: Text(sym,
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: fg))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['name'] as String,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                Text(AppTheme.currency(price),
                    style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 9,
                        color: AppTheme.textMuted)),
              ],
            )),
            GestureDetector(
              onTap: taken ? null : () => _draftFromQueue(i),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: taken ? AppTheme.redDim : AppTheme.green,
                      border: taken
                          ? Border.all(
                              color: AppTheme.red.withValues(alpha: 0.3))
                          : null,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(taken ? 'TAKEN' : 'DRAFT',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: taken ? AppTheme.red : Colors.black))),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _removeFromQueue(i),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: AppTheme.redDim,
                    borderRadius: BorderRadius.circular(7),
                    border:
                        Border.all(color: AppTheme.red.withValues(alpha: 0.2))),
                child: const Icon(Icons.close, size: 14, color: AppTheme.red),
              ),
            ),
          ]),
        );
      },
    );
  }

  // ── MY PICKS PANEL ──
  Widget _buildMyPicksPanel() {
    if (_myPicks.isEmpty) {
      return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('📭', style: TextStyle(fontSize: 36)),
        SizedBox(height: 8),
        Text('No picks yet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        SizedBox(height: 4),
        Text('Draft a stock to see it here',
            style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                color: AppTheme.textMuted)),
      ]));
    }

    return ListView.builder(
      itemCount: _myPicks.length,
      itemBuilder: (_, i) {
        final p = _myPicks[i];
        final sym = p['symbol'] as String;
        final sec = p['sector'] as String? ?? 'Other';
        final fg = _sectorFg[sec] ?? AppTheme.textMuted;
        final bg = _sectorBg[sec] ?? AppTheme.surface2;
        final price = (p['price'] as num).toDouble();

        return Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: fg.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(7)),
                child: Text(sym,
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: fg))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'] as String,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text('Rd ${p['round']} · Pick #${p['pick']}',
                    style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 9,
                        color: AppTheme.textMuted)),
              ],
            )),
            Text(AppTheme.currency(price),
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.green)),
          ]),
        );
      },
    );
  }

  // ── CHAT PANEL ──
  Widget _buildChatPanel() => ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          Center(
              child: Text('DRAFT ROOM CHAT',
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      letterSpacing: 1))),
          SizedBox(height: 10),
          _ChatBubble(
              init: 'SM',
              name: 'stockmage',
              msg: 'NVDA was the obvious pick there 🤷',
              g: [Color(0xFF1A3A1A), Color(0xFF00C853)],
              tc: Colors.white),
          _ChatBubble(
              init: 'JR',
              name: 'jake_r',
              msg: 'TSLA going crazy this week 🚀',
              g: [Color(0xFF2A2A4A), Color(0xFF4A4A8A)],
              tc: Colors.white),
          _ChatBubble(
              init: 'YO',
              name: 'You',
              msg: 'Watch me clean up with NVDA 💎',
              g: [Color(0xFF0A2A0A), AppTheme.green],
              tc: Colors.black,
              isMe: true),
        ],
      );
}

class _ChatBubble extends StatelessWidget {
  final String init, name, msg;
  final List<Color> g;
  final Color tc;
  final bool isMe;
  const _ChatBubble(
      {required this.init,
      required this.name,
      required this.msg,
      required this.g,
      required this.tc,
      this.isMe = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: g),
                      borderRadius: BorderRadius.circular(8)),
                  child: Center(
                      child: Text(init,
                          style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: tc)))),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: isMe ? AppTheme.green : AppTheme.textMuted)),
                const SizedBox(height: 2),
                Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: isMe ? AppTheme.green : AppTheme.surface2,
                        border:
                            isMe ? null : Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(14)),
                    child: Text(msg,
                        style: TextStyle(
                            fontSize: 13,
                            color: isMe ? Colors.black : AppTheme.text,
                            fontWeight:
                                isMe ? FontWeight.w600 : FontWeight.normal))),
              ],
            ),
            if (isMe) ...[
              const SizedBox(width: 8),
              Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: g),
                      borderRadius: BorderRadius.circular(8)),
                  child: Center(
                      child: Text(init,
                          style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: tc)))),
            ],
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────
// CREATE / JOIN LEAGUE SCREEN
// ─────────────────────────────────────────────────────────
class CreateJoinLeagueScreen extends StatefulWidget {
  const CreateJoinLeagueScreen({super.key});
  @override
  State<CreateJoinLeagueScreen> createState() => _CreateJoinLeagueScreenState();
}

class _CreateJoinLeagueScreenState extends State<CreateJoinLeagueScreen> {
  final _codeCtrl = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _joinLeague() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _joining = true);
    try {
      await context.read<LeagueProvider>().joinLeague(code);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppTheme.red));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Create / Join League'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Create League ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final created = await nav.push<bool>(
                    MaterialPageRoute(
                        builder: (_) => const CreateLeagueScreen()),
                  );
                  if (created == true && mounted) nav.pop();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Create New League',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ),
          const SizedBox(height: 24),
          const Center(
              child: Text('— OR JOIN AN EXISTING LEAGUE —',
                  style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      letterSpacing: 1))),
          const SizedBox(height: 16),
          const _SectionLabel('INVITE CODE'),
          _InputCard(
              controller: _codeCtrl,
              hint: 'Enter code (e.g. MW4X9R)',
              caps: true),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _joining ? null : _joinLeague,
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.green),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Join League',
                  style: TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 15))),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool caps;
  const _InputCard(
      {required this.controller, required this.hint, this.caps = false});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
            color: AppTheme.surface2,
            border: Border.all(color: AppTheme.border2),
            borderRadius: BorderRadius.circular(12)),
        child: TextField(
          controller: controller,
          textCapitalization: caps
              ? TextCapitalization.characters
              : TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppTheme.textMuted),
              border: InputBorder.none),
        ),
      );
}
