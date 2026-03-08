import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ranked_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

// ─────────────────────────────────────────
// 1v1 RANKED SCREEN
// ─────────────────────────────────────────
class RankedScreen extends StatefulWidget {
  const RankedScreen({super.key});
  @override
  State<RankedScreen> createState() => _RankedScreenState();
}

class _RankedScreenState extends State<RankedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RankedProvider>().loadChallenges();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ranked = context.watch<RankedProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('1v1 Ranked'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.green,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(
              fontSize: 12, fontFamily: 'Courier', fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'CHALLENGE'),
            Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('PENDING'),
              if (ranked.pendingIncoming.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${ranked.pendingIncoming.length}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ])),
            const Tab(text: 'ACTIVE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ChallengeTab(onCreated: () => _tabCtrl.animateTo(1)),
          _PendingTab(),
          _ActiveTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// TAB 1 — CREATE CHALLENGE
// ─────────────────────────────────────────
class _ChallengeTab extends StatefulWidget {
  final VoidCallback onCreated;
  const _ChallengeTab({required this.onCreated});
  @override
  State<_ChallengeTab> createState() => _ChallengeTabState();
}

class _ChallengeTabState extends State<_ChallengeTab> {
  final _contactCtrl = TextEditingController();
  String _duration = '1week';
  int _rosterSize = 5;
  bool _isSending = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendChallenge() async {
    final contact = _contactCtrl.text.trim();
    if (contact.isEmpty) {
      setState(() => _error = 'Enter an email or phone number');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
      _success = null;
    });

    final ranked = context.read<RankedProvider>();
    final found = await ranked.findUserByContact(contact);
    if (!mounted) return;

    if (found == null) {
      setState(() {
        _isSending = false;
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
    setState(() {
      _isSending = false;
      if (err != null) {
        _error = err;
      } else {
        _success = 'Challenge sent to ${found['username']}!';
        _contactCtrl.clear();
      }
    });

    if (err == null) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) widget.onCreated();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Challenge a Player',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                  'Send a 1v1 head-to-head challenge. Both players pick their own stocks independently.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textMuted, height: 1.4)),
              const SizedBox(height: 16),

              // Contact input
              const Text('OPPONENT',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier',
                      letterSpacing: 2)),
              const SizedBox(height: 6),
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _contactCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Email or phone number',
                    hintStyle:
                        TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.person_search,
                        size: 18, color: AppTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Duration
              const Text('DURATION',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier',
                      letterSpacing: 2)),
              const SizedBox(height: 8),
              Row(children: [
                _OptionChip(
                    label: '1 Day',
                    selected: _duration == '1day',
                    onTap: () => setState(() => _duration = '1day')),
                const SizedBox(width: 8),
                _OptionChip(
                    label: '1 Week',
                    selected: _duration == '1week',
                    onTap: () => setState(() => _duration = '1week')),
              ]),
              const SizedBox(height: 16),

              // Roster size
              const Text('ROSTER SIZE',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier',
                      letterSpacing: 2)),
              const SizedBox(height: 8),
              Row(children: [
                _OptionChip(
                    label: '3 Stocks',
                    selected: _rosterSize == 3,
                    onTap: () => setState(() => _rosterSize = 3)),
                const SizedBox(width: 8),
                _OptionChip(
                    label: '5 Stocks',
                    selected: _rosterSize == 5,
                    onTap: () => setState(() => _rosterSize = 5)),
                const SizedBox(width: 8),
                _OptionChip(
                    label: '11 Sectors',
                    selected: _rosterSize == 11,
                    onTap: () => setState(() => _rosterSize = 11)),
              ]),
              if (_rosterSize == 11) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.purple.withValues(alpha: 0.2)),
                  ),
                  child: const Text(
                      'Sectors mode: each pick must be from a different GICS sector',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.purple,
                          fontFamily: 'Courier')),
                ),
              ],
              const SizedBox(height: 20),

              // Send button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _sendChallenge,
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Send Challenge'),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.red, fontSize: 12)),
              ],
              if (_success != null) ...[
                const SizedBox(height: 10),
                Text(_success!,
                    style: const TextStyle(
                        color: AppTheme.green, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// TAB 2 — PENDING CHALLENGES
// ─────────────────────────────────────────
class _PendingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ranked = context.watch<RankedProvider>();
    final incoming = ranked.pendingIncoming;
    final outgoing = ranked.pendingOutgoing;

    if (incoming.isEmpty && outgoing.isEmpty) {
      return const Center(
          child: Text('No pending challenges',
              style: TextStyle(color: AppTheme.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (incoming.isNotEmpty) ...[
          const _SectionLabel('INCOMING'),
          ...incoming.map((c) => _PendingCard(challenge: c, isIncoming: true)),
          const SizedBox(height: 12),
        ],
        if (outgoing.isNotEmpty) ...[
          const _SectionLabel('SENT'),
          ...outgoing.map((c) => _PendingCard(challenge: c, isIncoming: false)),
        ],
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Challenge challenge;
  final bool isIncoming;
  const _PendingCard({required this.challenge, required this.isIncoming});

  @override
  Widget build(BuildContext context) {
    final ranked = context.read<RankedProvider>();
    final otherName = isIncoming
        ? challenge.challengerUsername
        : challenge.opponentUsername;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Avatar
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.surface3,
              child: Text(
                  otherName.isNotEmpty
                      ? otherName.substring(0, 1).toUpperCase()
                      : '?',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppTheme.green)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(otherName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      '${challenge.durationLabel} · ${challenge.rosterSize} ${challenge.isSectorMode ? 'sectors' : 'stocks'}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          fontFamily: 'Courier'),
                    ),
                  ]),
            ),
            if (isIncoming)
              Text('vs YOU',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.green,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w700)),
            if (!isIncoming)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
                ),
                child: const Text('WAITING',
                    style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.gold,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          if (isIncoming) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: () => ranked.declineChallenge(challenge.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.red,
                      side: const BorderSide(color: AppTheme.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Decline',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: () async {
                      await ranked.acceptChallenge(challenge.id);
                      if (context.mounted) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => StockPickerScreen(
                                    challenge: challenge)));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Accept',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// TAB 3 — ACTIVE MATCHES
// ─────────────────────────────────────────
class _ActiveTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ranked = context.watch<RankedProvider>();
    final active = ranked.activeChallenges;
    final completed = ranked.completedChallenges;

    if (active.isEmpty && completed.isEmpty) {
      return const Center(
          child: Text('No active matches',
              style: TextStyle(color: AppTheme.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active.isNotEmpty) ...[
          const _SectionLabel('IN PROGRESS'),
          ...active.map((c) => _ActiveMatchCard(challenge: c)),
          const SizedBox(height: 12),
        ],
        if (completed.isNotEmpty) ...[
          const _SectionLabel('COMPLETED'),
          ...completed.take(10).map((c) => _ActiveMatchCard(challenge: c)),
        ],
      ],
    );
  }
}

class _ActiveMatchCard extends StatelessWidget {
  final Challenge challenge;
  const _ActiveMatchCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<RankedProvider>().uid;
    final isChallenger = challenge.challengerUID == myUid;
    final myValue = isChallenger ? challenge.challengerValue : challenge.opponentValue;
    final myCost = isChallenger ? challenge.challengerCost : challenge.opponentCost;
    final theirValue = isChallenger ? challenge.opponentValue : challenge.challengerValue;
    final theirCost = isChallenger ? challenge.opponentCost : challenge.challengerCost;
    final opponentName = challenge.opponentNameOf(myUid);

    final myPct = myCost > 0 ? ((myValue - myCost) / myCost) * 100 : 0.0;
    final theirPct = theirCost > 0 ? ((theirValue - theirCost) / theirCost) * 100 : 0.0;
    final winning = myPct >= theirPct;

    final needsPicking = challenge.status == ChallengeStatus.picking;
    final myPicks = isChallenger ? challenge.challengerPicks : challenge.opponentPicks;
    final needsMyPicks = needsPicking && myPicks.isEmpty;

    // Check if challenge is complete
    final isComplete = challenge.status == ChallengeStatus.complete;
    final iWon = isComplete && challenge.winnerId == myUid;

    return GestureDetector(
      onTap: needsMyPicks
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StockPickerScreen(challenge: challenge)))
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(
              color: needsMyPicks
                  ? AppTheme.green.withValues(alpha: 0.4)
                  : isComplete
                      ? (iWon ? AppTheme.green : AppTheme.red)
                          .withValues(alpha: 0.2)
                      : AppTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            // Status row
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (needsMyPicks
                          ? AppTheme.green
                          : isComplete
                              ? AppTheme.textMuted
                              : AppTheme.blue)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  needsMyPicks
                      ? 'PICK YOUR STOCKS'
                      : needsPicking
                          ? 'WAITING FOR OPPONENT'
                          : isComplete
                              ? (iWon ? 'YOU WON' : 'YOU LOST')
                              : '${challenge.durationLabel} · IN PROGRESS',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    color: needsMyPicks
                        ? AppTheme.green
                        : isComplete
                            ? (iWon ? AppTheme.green : AppTheme.red)
                            : AppTheme.blue,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                  '${challenge.rosterSize} ${challenge.isSectorMode ? 'sectors' : 'stocks'}',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      fontFamily: 'Courier')),
            ]),
            const SizedBox(height: 12),

            // Player vs Player
            Row(children: [
              // Me
              Expanded(
                child: Column(children: [
                  const Text('YOU',
                      style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                          fontFamily: 'Courier')),
                  const SizedBox(height: 4),
                  Text(
                    myPct == 0 && myCost == 0
                        ? '--'
                        : '${myPct >= 0 ? '+' : ''}${myPct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Courier',
                      color:
                          myPct >= 0 ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                ]),
              ),
              // VS
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: winning && myCost > 0
                          ? AppTheme.green.withValues(alpha: 0.3)
                          : AppTheme.border),
                ),
                child: const Text('VS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMuted,
                        fontFamily: 'Courier')),
              ),
              // Opponent
              Expanded(
                child: Column(children: [
                  Text(opponentName.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.textMuted,
                          fontFamily: 'Courier'),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    theirPct == 0 && theirCost == 0
                        ? '--'
                        : '${theirPct >= 0 ? '+' : ''}${theirPct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Courier',
                      color: theirPct >= 0
                          ? AppTheme.green
                          : AppTheme.red,
                    ),
                  ),
                ]),
              ),
            ]),

            // Win bar
            if (myCost > 0 && theirCost > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 4,
                  child: Row(children: [
                    Expanded(
                      flex: (myPct.abs() * 100 + 1).toInt(),
                      child: Container(color: AppTheme.green),
                    ),
                    Expanded(
                      flex: (theirPct.abs() * 100 + 1).toInt(),
                      child: Container(color: AppTheme.red),
                    ),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
// STOCK PICKER SCREEN
// ─────────────────────────────────────────
class StockPickerScreen extends StatefulWidget {
  final Challenge challenge;
  const StockPickerScreen({super.key, required this.challenge});
  @override
  State<StockPickerScreen> createState() => _StockPickerScreenState();
}

class _StockPickerScreenState extends State<StockPickerScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isSubmitting = false;

  // Picked stocks: {symbol, companyName, priceAtPick, sector}
  final List<Map<String, dynamic>> _picks = [];

  static const List<String> _gicsSectors = [
    'Technology',
    'Healthcare',
    'Financials',
    'Consumer Discretionary',
    'Consumer Staples',
    'Energy',
    'Industrials',
    'Materials',
    'Utilities',
    'Real Estate',
    'Communication Services',
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  int get _maxPicks => widget.challenge.rosterSize;
  bool get _isSectorMode => widget.challenge.isSectorMode;
  Set<String> get _pickedSectors =>
      _picks.map((p) => p['sector'] as String).toSet();

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query);
    });
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
      final prov = context.read<PortfolioProvider>();
      final results = await prov.searchStocks(query);
      if (!mounted) return;

      // Fetch prices for top 10
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
      setState(() => _isSearching = false);
    }
  }

  void _addPick(Map<String, dynamic> stock) {
    if (_picks.length >= _maxPicks) return;
    if (_picks.any((p) => p['symbol'] == stock['symbol'])) return;

    final sector = stock['sector'] as String;
    if (_isSectorMode && _pickedSectors.contains(sector) && sector != 'Other') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Already picked from $sector sector'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    setState(() {
      _picks.add({
        'symbol': stock['symbol'],
        'companyName': stock['name'],
        'priceAtPick': stock['price'],
        'sector': sector,
      });
    });
  }

  void _removePick(int index) {
    setState(() => _picks.removeAt(index));
  }

  Future<void> _submitPicks() async {
    if (_picks.length < _maxPicks) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick $_maxPicks stocks to continue'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    setState(() => _isSubmitting = true);
    final ranked = context.read<RankedProvider>();
    final err = await ranked.submitPicks(widget.challenge.id, _picks);
    if (!mounted) return;

    if (err != null) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Picks submitted!'),
      backgroundColor: AppTheme.green,
    ));
  }

  String _guessSector(String sym) {
    const map = {
      'Technology': [
        'NVDA', 'AAPL', 'MSFT', 'META', 'GOOGL', 'AMD', 'PLTR', 'SHOP',
        'DDOG', 'CRWD', 'SNAP', 'RBLX', 'CRM', 'ORCL', 'INTC', 'QCOM',
        'AVGO', 'TSM', 'MU', 'ADBE',
      ],
      'Financials': [
        'JPM', 'BAC', 'GS', 'V', 'MA', 'HOOD', 'SOFI', 'PYPL', 'SPY',
        'BRK.B', 'WFC', 'C', 'AXP', 'SCHW',
      ],
      'Consumer Discretionary': [
        'AMZN', 'TSLA', 'RIVN', 'NIO', 'F', 'GM', 'NFLX', 'DIS', 'UBER',
        'SPOT', 'BABA', 'ABNB', 'SBUX', 'NKE', 'MCD',
      ],
      'Consumer Staples': ['WMT', 'COST', 'PG', 'KO', 'PEP', 'CL', 'MDLZ'],
      'Energy': ['XOM', 'CVX', 'SLB', 'COP', 'EOG', 'OXY', 'MPC'],
      'Healthcare': [
        'JNJ', 'UNH', 'PFE', 'ABBV', 'MRK', 'LLY', 'TMO', 'ABT', 'MRNA',
      ],
      'Communication Services': ['GOOG', 'T', 'VZ', 'TMUS', 'CMCSA', 'NFLX'],
      'Industrials': ['BA', 'CAT', 'HON', 'UPS', 'GE', 'RTX', 'LMT', 'DE'],
      'Materials': ['LIN', 'APD', 'ECL', 'SHW', 'NEM', 'FCX', 'DOW'],
      'Utilities': ['NEE', 'DUK', 'SO', 'D', 'AEP', 'EXC', 'SRE'],
      'Real Estate': ['AMT', 'PLD', 'CCI', 'SPG', 'EQIX', 'O', 'PSA'],
    };
    for (final entry in map.entries) {
      if (entry.value.contains(sym)) return entry.key;
    }
    return 'Other';
  }

  static const Map<String, Color> _sectorColors = {
    'Technology': Color(0xFF4FC3F7),
    'Healthcare': Color(0xFF81C784),
    'Financials': Color(0xFFFFD54F),
    'Consumer Discretionary': Color(0xFFFF8A65),
    'Consumer Staples': Color(0xFFA5D6A7),
    'Energy': Color(0xFFE57373),
    'Industrials': Color(0xFF90A4AE),
    'Materials': Color(0xFFCE93D8),
    'Utilities': Color(0xFF4DB6AC),
    'Real Estate': Color(0xFFFFAB91),
    'Communication Services': Color(0xFF7986CB),
    'Other': Color(0xFF78909C),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pick $_maxPicks ${_isSectorMode ? 'Sectors' : 'Stocks'}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text('${_picks.length}/$_maxPicks',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w800,
                    color: _picks.length == _maxPicks
                        ? AppTheme.green
                        : AppTheme.textMuted,
                  )),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: 42,
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
                  hintText: 'Search stocks...',
                  hintStyle:
                      TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  prefixIcon: Icon(Icons.search,
                      size: 18, color: AppTheme.textMuted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),

          // Sector hints for sector mode
          if (_isSectorMode)
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _gicsSectors.map((s) {
                  final picked = _pickedSectors.contains(s);
                  final c = _sectorColors[s] ?? AppTheme.textMuted;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: picked
                          ? c.withValues(alpha: 0.2)
                          : AppTheme.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: picked
                              ? c.withValues(alpha: 0.4)
                              : AppTheme.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (picked)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.check, size: 12, color: AppTheme.green),
                        ),
                      Text(s,
                          style: TextStyle(
                              fontSize: 9,
                              color: picked ? c : AppTheme.textMuted,
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.w600)),
                    ]),
                  );
                }).toList(),
              ),
            ),

          // My picks
          if (_picks.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _picks.length,
                itemBuilder: (_, i) {
                  final pick = _picks[i];
                  final c = _sectorColors[pick['sector']] ?? AppTheme.textMuted;
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(pick['symbol'],
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'Courier',
                                    color: c)),
                            if (_isSectorMode)
                              Text(pick['sector'],
                                  style: TextStyle(
                                      fontSize: 8,
                                      color: c.withValues(alpha: 0.7),
                                      fontFamily: 'Courier')),
                          ]),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _removePick(i),
                        child: Icon(Icons.close,
                            size: 14,
                            color: AppTheme.textMuted),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 4),

          // Search results
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.green, strokeWidth: 2))
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty
                              ? 'Search for stocks to add to your roster'
                              : 'No results found',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (_, i) {
                          final stock = _searchResults[i];
                          final alreadyPicked = _picks
                              .any((p) => p['symbol'] == stock['symbol']);
                          final sector = stock['sector'] as String;
                          final sectorTaken = _isSectorMode &&
                              _pickedSectors.contains(sector) &&
                              sector != 'Other' &&
                              !alreadyPicked;
                          final disabled =
                              alreadyPicked || _picks.length >= _maxPicks || sectorTaken;
                          final c =
                              _sectorColors[sector] ?? AppTheme.textMuted;

                          return GestureDetector(
                            onTap: disabled ? null : () => _addPick(stock),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: AppTheme.border)),
                              ),
                              child: Opacity(
                                opacity: disabled ? 0.4 : 1.0,
                                child: Row(children: [
                                  // Sector badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: c.withValues(alpha: 0.1),
                                      border: Border.all(
                                          color:
                                              c.withValues(alpha: 0.3)),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(stock['symbol'],
                                        style: TextStyle(
                                            fontFamily: 'Courier',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: c)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(stock['name'],
                                              style: const TextStyle(
                                                  fontSize: 12),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          if (_isSectorMode)
                                            Text(sector,
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    color: c,
                                                    fontFamily: 'Courier')),
                                        ]),
                                  ),
                                  Text(
                                      AppTheme.currency(
                                          stock['price'] as double),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'Courier',
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  if (alreadyPicked)
                                    const Icon(Icons.check_circle,
                                        size: 18, color: AppTheme.green)
                                  else if (sectorTaken)
                                    const Icon(Icons.block,
                                        size: 18,
                                        color: AppTheme.textMuted)
                                  else
                                    const Icon(Icons.add_circle_outline,
                                        size: 18, color: AppTheme.green),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Submit button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    _picks.length == _maxPicks && !_isSubmitting
                        ? _submitPicks
                        : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        _picks.length == _maxPicks
                            ? 'Lock In Picks'
                            : '${_picks.length}/$_maxPicks Picked',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────
class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.green.withValues(alpha: 0.1)
              : AppTheme.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? AppTheme.green.withValues(alpha: 0.4)
                  : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? AppTheme.green : AppTheme.textMuted,
              fontFamily: 'Courier',
            )),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted,
              fontFamily: 'Courier',
              letterSpacing: 2,
              fontWeight: FontWeight.w700)),
    );
  }
}
