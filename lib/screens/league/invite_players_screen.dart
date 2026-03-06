import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'draft_room_screen.dart';

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
  int _memberCount = 1; // commissioner is already in

  @override
  void initState() {
    super.initState();
    _loadInvites();
    _listenToMembers();
  }

  @override
  void dispose() {
    _contactCtrl.dispose();
    _membersSub?.cancel();
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

      final invite = {
        'contact': contact,
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
        'status': 'drafting',
      });

      // Read league settings for the draft room
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
            ),
          ),

          // ── Bottom bar with Start Draft ──
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
                if (!canStartDraft)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Need at least 1 player to start the draft',
                      style: TextStyle(
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
                    onPressed: canStartDraft ? _startDraft : null,
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
                    child: const Text(
                      'Start Draft',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Testing mode - normally requires 2+ players',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 9,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
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
