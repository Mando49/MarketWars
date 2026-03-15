import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'draft_room_screen.dart';
import 'league_screen.dart';

class InvitePlayersScreen extends StatefulWidget {
  final String leagueId;
  final String leagueName;
  final String inviteCode;

  const InvitePlayersScreen({
    super.key,
    required this.leagueId,
    required this.leagueName,
    required this.inviteCode,
  });

  @override
  State<InvitePlayersScreen> createState() => _InvitePlayersScreenState();
}

class _InvitePlayersScreenState extends State<InvitePlayersScreen> {
  final _contactCtrl = TextEditingController();
  final _db = FirebaseFirestore.instance;
  bool _sending = false;
  List<_Invite> _invites = [];
  StreamSubscription? _membersSub;
  StreamSubscription? _leagueSub;
  int _memberCount = 1; // commissioner is already in
  String? _commissionerUID;
  String _leagueStatus = 'pending';
  bool _skipDraft = false;
  List<String> _draftOrder = [];
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isCommissioner => _commissionerUID == _uid;

  @override
  void initState() {
    super.initState();
    _loadInvites();
    _listenToMembers();
    _listenToLeague();
  }

  void _listenToLeague() {
    _leagueSub = _db
        .collection('leagues')
        .doc(widget.leagueId)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data() ?? {};
        final members = List<String>.from(data['members'] ?? []);
        final order = List<String>.from(data['draftOrder'] ?? []);
        setState(() {
          _commissionerUID = data['commissionerUID'] as String?;
          _leagueStatus = data['status'] as String? ?? 'pending';
          _skipDraft = data['skipDraft'] as bool? ?? false;
          _draftOrder = order.isNotEmpty ? order : members;
        });
      }
    });
  }

  Future<void> _toggleReady(bool currentReady) async {
    await _db
        .collection('leagues')
        .doc(widget.leagueId)
        .collection('members')
        .doc(_uid)
        .set({'draftReady': !currentReady}, SetOptions(merge: true));
  }

  Future<void> _randomizeOrder() async {
    final shuffled = List<String>.from(_draftOrder)..shuffle(math.Random());
    await _db.collection('leagues').doc(widget.leagueId).update({
      'draftOrder': shuffled,
    });
  }

  Future<void> _reorderDraft(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final updated = List<String>.from(_draftOrder);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    await _db.collection('leagues').doc(widget.leagueId).update({
      'draftOrder': updated,
    });
  }

  @override
  void dispose() {
    _contactCtrl.dispose();
    _membersSub?.cancel();
    _leagueSub?.cancel();
    super.dispose();
  }

  void _listenToMembers() {
    _membersSub = _db
        .collection('leagues')
        .doc(widget.leagueId)
        .snapshots()
        .listen((snap) {
      if (snap.exists) {
        final members = List<String>.from(snap.data()?['members'] ?? []);
        if (mounted) setState(() => _memberCount = members.length);
      }
    });
  }

  Future<void> _loadInvites() async {
    final snap = await _db
        .collection('leagues')
        .doc(widget.leagueId)
        .collection('invites')
        .orderBy('sentAt', descending: true)
        .get();
    if (mounted) {
      setState(() {
        _invites = snap.docs.map((d) => _Invite.fromMap(d.data(), d.id)).toList();
      });
    }
  }

  Future<void> _sendInvite() async {
    final contact = _contactCtrl.text.trim();
    if (contact.isEmpty) return;

    // Basic validation
    final isEmail = contact.contains('@');
    final isPhone = RegExp(r'^\+?[\d\s\-()]{7,}$').hasMatch(contact);
    if (!isEmail && !isPhone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid email or phone number'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    // Check for duplicate
    if (_invites.any((i) => i.contact == contact)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Already invited'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }

    setState(() => _sending = true);
    try {
      final docRef = _db
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('invites')
          .doc();

      final normalizedContact = isEmail ? contact.toLowerCase() : contact;
      final invite = {
        'contact': normalizedContact,
        'type': isEmail ? 'email' : 'phone',
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
        'inviteCode': widget.inviteCode,
      };

      await docRef.set(invite);

      setState(() {
        _invites.insert(
          0,
          _Invite(
            id: docRef.id,
            contact: contact,
            type: isEmail ? 'email' : 'phone',
            status: 'pending',
            sentAt: DateTime.now(),
          ),
        );
      });

      _contactCtrl.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Invite sent to $contact'),
          backgroundColor: AppTheme.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startDraft() async {
    try {
      await _db.collection('leagues').doc(widget.leagueId).update({
        'draftOrder': _draftOrder,
        'status': 'drafting',
      });

      await _navigateToDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.red,
        ));
      }
    }
  }

  Future<void> _joinDraft() async {
    try {
      await _navigateToDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.red,
        ));
      }
    }
  }

  Future<void> _navigateToDraft() async {
    final leagueDoc =
        await _db.collection('leagues').doc(widget.leagueId).get();
    final data = leagueDoc.data() ?? {};
    final rosterSize = data['rosterSize'] as int? ?? 10;
    final draftMode = data['draftMode'] as String? ?? 'unique';

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DraftRoomScreen(
            leagueId: widget.leagueId,
            leagueName: widget.leagueName,
            rosterSize: rosterSize,
            draftMode: draftMode,
          ),
        ),
      );
    }
  }

  Future<void> _startSeason() async {
    try {
      await _db.collection('leagues').doc(widget.leagueId).update({
        'status': 'active',
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LeagueScreen(leagueId: widget.leagueId),
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

  void _viewLeague() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LeagueScreen(leagueId: widget.leagueId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canStartDraft = _memberCount >= 1;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Invite Players'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // ── League info card ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    border: Border.all(color: AppTheme.border2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.leagueName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'INVITE CODE',
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 10,
                              color: AppTheme.textMuted,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.greenDim,
                              border:
                                  Border.all(color: AppTheme.greenBorder),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.inviteCode,
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.green,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: widget.inviteCode));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.people_outline,
                              size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            '$_memberCount player${_memberCount == 1 ? '' : 's'} joined',
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_isCommissioner) ...[
                  const SizedBox(height: 20),

                  // ── Invite input ──
                  _label('INVITE BY EMAIL OR PHONE'),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface2,
                            border: Border.all(color: AppTheme.border2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _contactCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(fontSize: 15),
                            decoration: const InputDecoration(
                              hintText: 'email or phone number',
                              hintStyle: TextStyle(color: AppTheme.textMuted),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _sendInvite(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _sending ? null : _sendInvite,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.send_rounded,
                                  size: 20, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Pending invites list ──
                  if (_invites.isNotEmpty) ...[
                    _label('PENDING INVITES'),
                    ..._invites.map((inv) => _inviteRow(inv)),
                  ],

                  if (_invites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.mail_outline_rounded,
                                size: 40,
                                color: AppTheme.textMuted.withValues(alpha: 0.4)),
                            const SizedBox(height: 10),
                            const Text(
                              'No invites sent yet',
                              style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],

                // ── Draft Lobby ──
                if (!_skipDraft) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _label('DRAFT ORDER')),
                    if (_isCommissioner)
                      GestureDetector(
                        onTap: _randomizeOrder,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shuffle_rounded,
                                  size: 14, color: AppTheme.green),
                              SizedBox(width: 6),
                              Text('Randomize',
                                  style: TextStyle(
                                      color: AppTheme.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Courier')),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    border: Border.all(color: AppTheme.border2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _db
                        .collection('leagues')
                        .doc(widget.leagueId)
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
                      if (memberDocs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No members yet',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 12)),
                        );
                      }

                      // Build map of uid -> member data
                      final memberMap = <String, Map<String, dynamic>>{};
                      for (final doc in memberDocs) {
                        memberMap[doc.id] =
                            doc.data() as Map<String, dynamic>;
                      }

                      // Order by draftOrder, include any members not in order at the end
                      final orderedUids = <String>[];
                      for (final uid in _draftOrder) {
                        if (memberMap.containsKey(uid)) orderedUids.add(uid);
                      }
                      for (final uid in memberMap.keys) {
                        if (!orderedUids.contains(uid)) orderedUids.add(uid);
                      }

                      Widget buildRow(String uid, int index) {
                        final data = memberMap[uid] ?? {};
                        final username =
                            data['username'] as String? ?? 'Player';
                        final draftReady =
                            data['draftReady'] as bool? ?? false;
                        final isMe = uid == _uid;
                        final isComm = uid == _commissionerUID;

                        return Container(
                          key: ValueKey(uid),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: AppTheme.border2, width: 0.5)),
                          ),
                          child: Row(
                            children: [
                              if (_isCommissioner)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.drag_handle,
                                      size: 20, color: AppTheme.textMuted),
                                ),
                              // Position number
                              SizedBox(
                                width: 24,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.green,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Avatar
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isComm
                                      ? AppTheme.gold
                                          .withValues(alpha: 0.15)
                                      : AppTheme.green
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: isComm
                                      ? Border.all(
                                          color: AppTheme.gold
                                              .withValues(alpha: 0.5))
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
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.gold
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: AppTheme.gold
                                                  .withValues(
                                                      alpha: 0.3)),
                                        ),
                                        child: const Text('COMM',
                                            style: TextStyle(
                                                color: AppTheme.gold,
                                                fontSize: 9,
                                                fontWeight:
                                                    FontWeight.w700,
                                                fontFamily: 'Courier')),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Ready badge or toggle (hidden when skipDraft)
                              if (!_skipDraft) ...[
                                if (isMe)
                                  GestureDetector(
                                    onTap: () =>
                                        _toggleReady(draftReady),
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6),
                                      decoration: BoxDecoration(
                                        color: draftReady
                                            ? AppTheme.green
                                            : AppTheme.surface2,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: draftReady
                                                ? AppTheme.green
                                                : AppTheme.border2),
                                      ),
                                      child: Text(
                                        draftReady
                                            ? 'Unready'
                                            : 'Ready Up',
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
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      border: Border.all(
                                          color: draftReady
                                              ? AppTheme.green.withValues(
                                                  alpha: 0.3)
                                              : AppTheme.border2),
                                    ),
                                    child: Text(
                                      draftReady
                                          ? 'READY'
                                          : 'NOT READY',
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
                            ],
                          ),
                        );
                      }

                      if (_isCommissioner) {
                        return ReorderableListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          onReorder: _reorderDraft,
                          children: [
                            for (int i = 0; i < orderedUids.length; i++)
                              buildRow(orderedUids[i], i),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          for (int i = 0; i < orderedUids.length; i++)
                            buildRow(orderedUids[i], i),
                        ],
                      );
                    },
                  ),
                ),
                ],
              ],
            ),
          ),

          // ── Bottom bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                top: BorderSide(color: AppTheme.border2),
              ),
            ),
            child: Column(
              children: [
                if (_isCommissioner) ...[
                  if (!canStartDraft)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _skipDraft
                            ? 'Need at least 1 player to start the season'
                            : 'Need at least 1 player to start the draft',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canStartDraft
                          ? (_skipDraft ? _startSeason : _startDraft)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            canStartDraft ? AppTheme.green : AppTheme.surface3,
                        foregroundColor:
                            canStartDraft ? Colors.black : AppTheme.textMuted,
                        disabledBackgroundColor: AppTheme.surface3,
                        disabledForegroundColor: AppTheme.textMuted,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _skipDraft ? 'Start Season' : 'Start Draft',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: _skipDraft
                        ? (_leagueStatus == 'active'
                            ? ElevatedButton(
                                onPressed: _viewLeague,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.green,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'View League',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            : ElevatedButton(
                                onPressed: null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.surface3,
                                  foregroundColor: AppTheme.textMuted,
                                  disabledBackgroundColor: AppTheme.surface3,
                                  disabledForegroundColor: AppTheme.textMuted,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Waiting for Season to Start...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ))
                        : (_leagueStatus == 'drafting'
                            ? ElevatedButton(
                                onPressed: _joinDraft,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.green,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Join Draft',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            : ElevatedButton(
                                onPressed: null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.surface3,
                                  foregroundColor: AppTheme.textMuted,
                                  disabledBackgroundColor: AppTheme.surface3,
                                  disabledForegroundColor: AppTheme.textMuted,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Waiting for Commissioner...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              )),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Courier',
            fontSize: 10,
            color: AppTheme.textMuted,
            letterSpacing: 1.5,
          ),
        ),
      );

  Future<void> _cancelInvite(_Invite inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remove Invite',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Remove invite to ${inv.contact}?',
            style: const TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Remove', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _db
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('invites')
          .doc(inv.id)
          .delete();

      if (mounted) {
        setState(() => _invites.remove(inv));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invite removed'),
          backgroundColor: AppTheme.green,
          duration: Duration(seconds: 2),
        ));
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

  Widget _inviteRow(_Invite inv) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          border: Border.all(color: AppTheme.border2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              inv.type == 'email'
                  ? Icons.email_outlined
                  : Icons.phone_outlined,
              size: 16,
              color: AppTheme.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                inv.contact,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: inv.status == 'joined'
                    ? AppTheme.greenDim
                    : const Color(0x1AFFC947),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                inv.status.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: inv.status == 'joined'
                      ? AppTheme.green
                      : AppTheme.gold,
                ),
              ),
            ),
            if (inv.status != 'joined') ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => _cancelInvite(inv),
                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.red),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
              ),
            ],
          ],
        ),
      );
}

class _Invite {
  final String id, contact, type, status;
  final DateTime sentAt;

  _Invite({
    required this.id,
    required this.contact,
    required this.type,
    required this.status,
    required this.sentAt,
  });

  factory _Invite.fromMap(Map<String, dynamic> map, String id) => _Invite(
        id: id,
        contact: map['contact'] ?? '',
        type: map['type'] ?? 'email',
        status: map['status'] ?? 'pending',
        sentAt: (map['sentAt'] as dynamic)?.toDate() ?? DateTime.now(),
      );
}
