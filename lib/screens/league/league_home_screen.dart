import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/league_provider.dart';
import '../../theme/app_theme.dart';
import 'create_league_screen.dart';
import 'league_screen.dart';

class LeagueHomeScreen extends StatelessWidget {
  const LeagueHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<LeagueProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: prov.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.green))
            : const _LeagueHomeBody(),
      ),
    );
  }
}

class _LeagueHomeBody extends StatefulWidget {
  const _LeagueHomeBody();

  @override
  State<_LeagueHomeBody> createState() => _LeagueHomeBodyState();
}

class _LeagueHomeBodyState extends State<_LeagueHomeBody> {
  bool _joinExpanded = false;
  List<_PendingInvite> _pendingInvites = [];
  bool _loadingInvites = true;

  static const int _freeLeagueLimit = 3;

  @override
  void initState() {
    super.initState();
    _loadPendingInvites();
  }

  Future<void> _loadPendingInvites() async {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
    if (email == null || email.isEmpty) {
      setState(() => _loadingInvites = false);
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final leaguesSnap = await db.collection('leagues').get();
      final invites = <_PendingInvite>[];

      for (final leagueDoc in leaguesSnap.docs) {
        final leagueData = leagueDoc.data();
        final leagueName = leagueData['name'] as String? ?? 'Unknown League';
        final members = List<String>.from(leagueData['members'] ?? []);
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

        // Skip leagues the user is already in
        if (members.contains(uid)) continue;

        final invitesSnap = await db
            .collection('leagues')
            .doc(leagueDoc.id)
            .collection('invites')
            .where('contact', isEqualTo: email)
            .where('status', isEqualTo: 'pending')
            .get();

        for (final invDoc in invitesSnap.docs) {
          invites.add(_PendingInvite(
            leagueId: leagueDoc.id,
            leagueName: leagueName,
            inviteDocId: invDoc.id,
            memberCount: members.length,
            maxPlayers: leagueData['maxPlayers'] as int? ?? 10,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _pendingInvites = invites;
          _loadingInvites = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInvites = false);
    }
  }

  Future<void> _acceptInvite(_PendingInvite invite) async {
    final prov = context.read<LeagueProvider>();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final error = await prov.joinByContact(email);

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppTheme.red,
      ));
    } else {
      setState(() {
        _pendingInvites.removeWhere((i) => i.inviteDocId == invite.inviteDocId);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Joined ${invite.leagueName}!'),
        backgroundColor: AppTheme.green,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<LeagueProvider>();
    final leagues = prov.leagues;
    final atLimit = leagues.length >= _freeLeagueLimit;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 48),
        // Icon
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.greenDim,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.groups_rounded,
                size: 40, color: AppTheme.green),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text('Leagues',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
              'Create or join a league to start\ncompeting with friends',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
        ),
        const SizedBox(height: 40),

        // ── League limit banner ──
        if (atLimit)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0x1AFFD700),
              border: Border.all(color: const Color(0x33FFD700)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, color: AppTheme.gold, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Upgrade to Pro for unlimited leagues',
                    style: TextStyle(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

        // ── Create League button ──
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: atLimit
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreateLeagueScreen()),
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.green,
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppTheme.surface2,
              disabledForegroundColor: AppTheme.textMuted,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(atLimit ? Icons.lock_rounded : Icons.add_rounded,
                    size: 20),
                const SizedBox(width: 8),
                const Text('Create League',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Join a League button ──
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: atLimit
                ? null
                : () => setState(() => _joinExpanded = !_joinExpanded),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: atLimit ? AppTheme.textMuted : AppTheme.green),
              disabledForegroundColor: AppTheme.textMuted,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Join a League',
                    style: TextStyle(
                        color: atLimit ? AppTheme.textMuted : AppTheme.green,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(width: 8),
                if (!atLimit)
                  AnimatedRotation(
                    turns: _joinExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.green, size: 22),
                  ),
                if (atLimit)
                  const Icon(Icons.lock_rounded,
                      color: AppTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),

        // ── Join options ──
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _joinExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _JoinOptionTile(
                          emoji: '\u{1F4E7}',
                          label: 'Join by Email',
                          onTap: () => _showJoinDialog(
                            context,
                            title: 'Join by Email',
                            hint: 'Enter email address',
                            inputType: TextInputType.emailAddress,
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        _JoinOptionTile(
                          emoji: '\u{1F4F1}',
                          label: 'Join by Phone',
                          onTap: () => _showJoinDialog(
                            context,
                            title: 'Join by Phone',
                            hint: 'Enter phone number',
                            inputType: TextInputType.phone,
                          ),
                        ),
                        const Divider(height: 1, indent: 56),
                        _JoinOptionTile(
                          emoji: '\u{1F511}',
                          label: 'Join by Code',
                          onTap: () => _showJoinDialog(
                            context,
                            title: 'Join by Code',
                            hint: 'Enter invite code (e.g. MW4X9R)',
                            capitalize: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Pending Invites section ──
        if (!_loadingInvites && _pendingInvites.isNotEmpty) ...[
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('PENDING INVITES',
                style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    color: AppTheme.gold,
                    letterSpacing: 1.5)),
          ),
          ..._pendingInvites.map((inv) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppTheme.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.mail_rounded,
                            color: AppTheme.gold, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(inv.leagueName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(
                                '${inv.memberCount}/${inv.maxPlayers} players',
                                style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                    fontFamily: 'Courier')),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _acceptInvite(inv),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Join',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],

        // ── Your Leagues section ──
        const SizedBox(height: 32),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('YOUR LEAGUES',
              style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5)),
        ),
        if (leagues.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              children: [
                Icon(Icons.sports_esports_outlined,
                    size: 36, color: AppTheme.textMuted),
                SizedBox(height: 10),
                Text('No leagues yet',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                SizedBox(height: 4),
                Text('Create or join a league above',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
              ],
            ),
          )
        else
          ...leagues.map((league) => _LeagueCard(league: league)),

        const SizedBox(height: 32),
      ],
    );
  }

  void _showJoinDialog(
    BuildContext context, {
    required String title,
    required String hint,
    TextInputType inputType = TextInputType.text,
    bool capitalize = false,
  }) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          keyboardType: inputType,
          textCapitalization: capitalize
              ? TextCapitalization.characters
              : TextCapitalization.none,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppTheme.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.green),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = ctrl.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx);
              await _handleJoin(title, value);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.green,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Join',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleJoin(String method, String value) async {
    final prov = context.read<LeagueProvider>();
    String? error;

    if (method == 'Join by Code') {
      error = await prov.joinLeague(value);
    } else {
      // Email / Phone lookup: search all leagues for a pending invite
      error = await prov.joinByContact(value);
    }

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppTheme.red,
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────
// LEAGUE CARD
// ─────────────────────────────────────────────────────────
class _LeagueCard extends StatelessWidget {
  final League league;
  const _LeagueCard({required this.league});

  String get _statusLabel {
    switch (league.status) {
      case LeagueStatus.pending:
        return 'Forming';
      case LeagueStatus.drafting:
        return 'Draft';
      case LeagueStatus.active:
        return league.currentWeek > 0 ? 'Week ${league.currentWeek}' : 'Active';
      case LeagueStatus.playoffs:
        return 'Playoffs';
      case LeagueStatus.complete:
        return 'Complete';
    }
  }

  Color get _statusColor {
    switch (league.status) {
      case LeagueStatus.pending:
        return AppTheme.blue;
      case LeagueStatus.drafting:
        return AppTheme.purple;
      case LeagueStatus.active:
        return AppTheme.green;
      case LeagueStatus.playoffs:
        return AppTheme.gold;
      case LeagueStatus.complete:
        return AppTheme.textMuted;
    }
  }

  bool get _isCommissioner =>
      FirebaseAuth.instance.currentUser?.uid == league.commissionerUID;

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete League',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: const Text(
            'Delete this league? All data will be permanently lost.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<LeagueProvider>().deleteLeague(league.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmLeave(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave League',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: const Text(
            'Leave this league? You will need a new invite to rejoin.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<LeagueProvider>().leaveLeague(league.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Leave',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => LeagueScreen(leagueId: league.id)),
          ),
          onLongPress: _isCommissioner ? null : () => _confirmLeave(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // League icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(Icons.groups_rounded, color: _statusColor, size: 22),
                ),
                const SizedBox(width: 14),
                // Name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(league.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(_statusLabel,
                                style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 10,
                                    color: _statusColor,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.person_rounded,
                              size: 13, color: AppTheme.textMuted),
                          const SizedBox(width: 3),
                          Text('${league.members.length}/${league.maxPlayers}',
                              style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Commissioner: show trash icon always
                GestureDetector(
                  onTap: () => _confirmDelete(context),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded,
                        color: AppTheme.red, size: 20),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingInvite {
  final String leagueId, leagueName, inviteDocId;
  final int memberCount, maxPlayers;

  _PendingInvite({
    required this.leagueId,
    required this.leagueName,
    required this.inviteDocId,
    required this.memberCount,
    required this.maxPlayers,
  });
}

class _JoinOptionTile extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _JoinOptionTile({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppTheme.textMuted, size: 20),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
