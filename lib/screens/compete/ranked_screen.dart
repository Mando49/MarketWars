import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ranked_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'stock_picker_screen.dart';
import 'match_detail_screen.dart';

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
            const Tab(text: 'CHALLENGE'),
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
                    style: const TextStyle(color: AppTheme.red, fontSize: 12)),
              ],
              if (_success != null) ...[
                const SizedBox(height: 10),
                Text(_success!,
                    style:
                        const TextStyle(color: AppTheme.green, fontSize: 12)),
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
    final otherName =
        isIncoming ? challenge.challengerUsername : challenge.opponentUsername;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(
            color: isIncoming
                ? AppTheme.green.withValues(alpha: 0.25)
                : AppTheme.border),
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
                    if (isIncoming)
                      const Text('challenged you!',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.green,
                              fontFamily: 'Courier')),
                  ]),
            ),
            if (!isIncoming)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const SizedBox(height: 10),
          // Match details row
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              _DetailChip(icon: Icons.schedule, label: challenge.durationLabel),
              const SizedBox(width: 12),
              _DetailChip(
                  icon: Icons.bar_chart,
                  label:
                      '${challenge.rosterSize} ${challenge.isSectorMode ? 'sectors' : 'stocks'}'),
              const SizedBox(width: 12),
              const _DetailChip(
                  icon: Icons.account_balance_wallet, label: '\$10,000'),
            ]),
          ),
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
                    child:
                        const Text('Decline', style: TextStyle(fontSize: 12)),
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
                                builder: (_) =>
                                    StockPickerScreen(challenge: challenge)));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Accept', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ]),
          ],
          if (!isIncoming) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Expanded(
                child: Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppTheme.gold)),
                  SizedBox(width: 8),
                  Text('Waiting for opponent...',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.gold,
                          fontFamily: 'Courier')),
                ]),
              ),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () => ranked.cancelChallenge(challenge.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.red,
                    side: const BorderSide(color: AppTheme.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DetailChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppTheme.textMuted),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textPrimary,
              fontFamily: 'Courier',
              fontWeight: FontWeight.w600)),
    ]);
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
          Row(children: [
            const Expanded(child: _SectionLabel('COMPLETED')),
            GestureDetector(
              onTap: () => ranked.clearCompletedChallenges(),
              child: const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Clear All',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.red,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          ...completed.take(10).map((c) => _CompletedMatchCard(challenge: c)),
        ],
      ],
    );
  }
}

class _CompletedMatchCard extends StatelessWidget {
  final Challenge challenge;
  const _CompletedMatchCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<RankedProvider>().uid;
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
    final iWon = challenge.winnerId == myUid;
    final rpEarned = iWon ? 25 : -10;

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MatchDetailScreen(challenge: challenge))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: (iWon ? AppTheme.green : AppTheme.red)
                  .withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Row(children: [
            Text(iWon ? '🏆' : '', style: const TextStyle(fontSize: 18)),
            if (iWon) const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('vs $opponentName',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Row(children: [
                  Text(
                    iWon ? 'YOU WON' : 'YOU LOST',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Courier',
                      color: iWon ? AppTheme.green : AppTheme.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (iWon ? AppTheme.green : AppTheme.red)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${rpEarned > 0 ? '+' : ''}$rpEarned RP',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Courier',
                        color: iWon ? AppTheme.green : AppTheme.red,
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
            // Dismiss button
            GestureDetector(
              onTap: () => context
                  .read<RankedProvider>()
                  .deleteChallenge(challenge.id),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close,
                    size: 14, color: AppTheme.textMuted),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (iWon ? AppTheme.green : AppTheme.red)
                      .withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
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
              child: Text(iWon ? '>' : '<',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: iWon ? AppTheme.green : AppTheme.red,
                      fontFamily: 'Courier')),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(10),
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
        ]),
      ),
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

    final needsPicking = challenge.status == ChallengeStatus.picking;
    final myPicks =
        isChallenger ? challenge.challengerPicks : challenge.opponentPicks;
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
          : (challenge.status == ChallengeStatus.active ||
                  challenge.status == ChallengeStatus.complete)
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          MatchDetailScreen(challenge: challenge)))
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      color: myPct >= 0 ? AppTheme.green : AppTheme.red,
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
                      color: theirPct >= 0 ? AppTheme.green : AppTheme.red,
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

            // Cancel button for picking-phase matches
            if (needsPicking) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: OutlinedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: const Text('Cancel Match?',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        content: const Text(
                            'This will forfeit the match and count as a loss.',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 13)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Keep',
                                style:
                                    TextStyle(color: AppTheme.textMuted)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              context
                                  .read<RankedProvider>()
                                  .forfeitChallenge(challenge.id);
                            },
                            child: const Text('Forfeit',
                                style: TextStyle(
                                    color: AppTheme.red,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.red,
                    side: const BorderSide(color: AppTheme.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Cancel Match',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
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
// SHARED WIDGETS
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
