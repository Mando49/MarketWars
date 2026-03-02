import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key});

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();

  String _activeChannel = 'market';

  final List<Map<String, String>> _channels = [
    {
      'id': 'market',
      'label': '📈 Market',
      'placeholder': 'Talk stocks & market moves...'
    },
    {
      'id': 'ranked',
      'label': '🏆 Ranked',
      'placeholder': 'Flex your rank or talk ranked...'
    },
    {
      'id': 'tips',
      'label': '💡 Tips',
      'placeholder': 'Share a strategy or tip...'
    },
    {
      'id': 'hot',
      'label': '🔥 Hot Takes',
      'placeholder': 'Drop your hottest take...'
    },
  ];

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final txt = _msgController.text.trim();
    if (txt.isEmpty) return;
    final user = _auth.currentUser;
    if (user == null) return;

    _msgController.clear();

    // Get user's ranked profile for badge display
    final profileDoc =
        await _firestore.collection('rankedProfiles').doc(user.uid).get();

    final username = profileDoc.exists
        ? (profileDoc.data()?['username'] ?? 'Player')
        : 'Player';
    final tier =
        profileDoc.exists ? (profileDoc.data()?['tier'] ?? 'bronze') : 'bronze';
    final globalRank =
        profileDoc.exists ? (profileDoc.data()?['globalRank'] ?? 9999) : 9999;

    await _firestore
        .collection('globalChat')
        .doc(_activeChannel)
        .collection('messages')
        .add({
      'uid': user.uid,
      'username': username,
      'text': txt,
      'tier': tier,
      'globalRank': globalRank,
      'timestamp': FieldValue.serverTimestamp(),
      'reactions': <String, int>{},
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    final ref = _firestore
        .collection('globalChat')
        .doc(_activeChannel)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final reactions = Map<String, int>.from(snap.data()?['reactions'] ?? {});
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      tx.update(ref, {'reactions': reactions});
    });
  }

  @override
  Widget build(BuildContext context) {
    final channelInfo = _channels.firstWhere((c) => c['id'] == _activeChannel);

    return Scaffold(
      backgroundColor: const Color(0xFF05070e),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            _buildHeader(),

            // ── Channel tabs ──
            _buildChannelTabs(),

            // ── Online strip ──
            _buildOnlineStrip(),

            // ── Messages ──
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('globalChat')
                    .doc(_activeChannel)
                    .collection('messages')
                    .orderBy('timestamp', descending: false)
                    .limitToLast(100)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF00ff87)),
                    );
                  }
                  final docs = snap.data!.docs;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController
                          .jumpTo(_scrollController.position.maxScrollExtent);
                    }
                  });
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final isMe = data['uid'] == _auth.currentUser?.uid;
                      return _buildMessage(docs[i].id, data, isMe);
                    },
                  );
                },
              ),
            ),

            // ── Input bar ──
            _buildInputBar(channelInfo['placeholder']!),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF121720),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFF1a2535)),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF567090), size: 18),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Global',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('rankedProfiles')
                      .where('online', isEqualTo: true)
                      .snapshots(),
                  builder: (ctx, snap) {
                    final count = snap.hasData ? snap.data!.docs.length : 0;
                    return Text(
                      '🟢 $count players online',
                      style: const TextStyle(
                        color: Color(0xFF567090),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF121720),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFF1a2535)),
            ),
            child: const Icon(Icons.notifications_outlined,
                color: Color(0xFF567090), size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF080b14),
        border: Border(
          top: BorderSide(color: Color(0xFF0d1825)),
          bottom: BorderSide(color: Color(0xFF0d1825)),
        ),
      ),
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: _channels.map((ch) {
          final isActive = ch['id'] == _activeChannel;
          return GestureDetector(
            onTap: () => setState(() => _activeChannel = ch['id']!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color:
                        isActive ? const Color(0xFF00ff87) : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  ch['label']!,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF00ff87)
                        : const Color(0xFF567090),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOnlineStrip() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFF05070e),
        border: Border(bottom: BorderSide(color: Color(0xFF0d1825))),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('rankedProfiles')
            .where('online', isEqualTo: true)
            .limit(12)
            .snapshots(),
        builder: (ctx, snap) {
          final docs =
              snap.hasData ? snap.data!.docs : <QueryDocumentSnapshot>[];
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final username = data['username'] ?? 'Player';
              final initials = username.length >= 2
                  ? username.substring(0, 2).toUpperCase()
                  : username.toUpperCase();
              final isMe = docs[i].id == _auth.currentUser?.uid;
              return Container(
                margin: const EdgeInsets.only(right: 10),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isMe
                                  ? [
                                      const Color(0xFF0a2a0a),
                                      const Color(0xFF00ff87)
                                    ]
                                  : [
                                      const Color(0xFF1a2535),
                                      const Color(0xFF2a3a4a)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: isMe ? Colors.black : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00ff87),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: const Color(0xFF05070e), width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isMe ? 'You' : username.split('_')[0],
                      style: TextStyle(
                        color: isMe
                            ? const Color(0xFF00ff87)
                            : const Color(0xFF567090),
                        fontSize: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMessage(String docId, Map<String, dynamic> data, bool isMe) {
    final username = data['username'] ?? 'Player';
    final text = data['text'] ?? '';
    final tier = data['tier'] ?? 'bronze';
    final globalRank = data['globalRank'] ?? 9999;
    final reactions = Map<String, int>.from(data['reactions'] ?? {});
    final ts = data['timestamp'] as Timestamp?;
    final timeStr = ts != null
        ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
        : '';

    final initials = username.length >= 2
        ? username.substring(0, 2).toUpperCase()
        : username.toUpperCase();

    final tierEmoji = _tierEmoji(tier);
    final rankStr = globalRank <= 100 ? '#$globalRank' : tier.toUpperCase();

    final List<String> emojiOptions = ['🔥', '💯', '💎', '💀', '🚀', '😂'];

    if (isMe) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Text(timeStr,
                        style: const TextStyle(
                            color: Color(0xFF2d4055),
                            fontSize: 9,
                            fontFamily: 'monospace')),
                    const SizedBox(width: 5),
                    _tierBadge(tierEmoji, rankStr, tier),
                    const SizedBox(width: 5),
                    const Text('You',
                        style: TextStyle(
                            color: Color(0xFF00ff87),
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00ff87), Color(0xFF00e676)],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(text,
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
                if (reactions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildReactions(docId, reactions),
                ],
              ],
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0a2a0a), Color(0xFF00ff87)],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(
                child: Text('YO',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar
          GestureDetector(
            onLongPress: () => _showReactionPicker(docId, emojiOptions),
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _tierGradient(tier),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(username,
                      style: TextStyle(
                          color: _tierColor(tier),
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 5),
                  _tierBadge(tierEmoji, rankStr, tier),
                  const SizedBox(width: 5),
                  Text(timeStr,
                      style: const TextStyle(
                          color: Color(0xFF2d4055),
                          fontSize: 9,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onLongPress: () => _showReactionPicker(docId, emojiOptions),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0d1018),
                    border: Border.all(color: const Color(0xFF1a2535)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(text,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
              if (reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                _buildReactions(docId, reactions),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReactions(String docId, Map<String, int> reactions) {
    return Wrap(
      spacing: 4,
      children: reactions.entries.map((e) {
        return GestureDetector(
          onTap: () => _addReaction(docId, e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF121720),
              border: Border.all(color: const Color(0xFF1a2535)),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 3),
                Text('${e.value}',
                    style: const TextStyle(
                        color: Color(0xFF567090),
                        fontSize: 10,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showReactionPicker(String docId, List<String> emojis) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0d1018),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('React',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis
                  .map((e) => GestureDetector(
                        onTap: () {
                          _addReaction(docId, e);
                          Navigator.pop(ctx);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 32)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(String placeholder) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF05070e),
        border: Border(top: BorderSide(color: Color(0xFF0d1825))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0d1018),
                border: Border.all(color: const Color(0xFF1a2535)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _msgController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle:
                      const TextStyle(color: Color(0xFF567090), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00ff87), Color(0xFF00e676)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00ff87).withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.send_rounded, color: Colors.black, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierBadge(String emoji, String label, String tier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _tierBgColor(tier),
        border: Border.all(color: _tierColor(tier).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        '$emoji $label',
        style: TextStyle(
            color: _tierColor(tier), fontSize: 9, fontFamily: 'monospace'),
      ),
    );
  }

  String _tierEmoji(String tier) {
    switch (tier) {
      case 'champion':
        return '👑';
      case 'diamond':
        return '💎';
      case 'gold':
        return '🥇';
      case 'silver':
        return '🥈';
      default:
        return '🥉';
    }
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'champion':
        return const Color(0xFFb388ff);
      case 'diamond':
        return const Color(0xFF4fc3f7);
      case 'gold':
        return const Color(0xFFffc947);
      case 'silver':
        return const Color(0xFFa8b8c8);
      default:
        return const Color(0xFFcd7f32);
    }
  }

  Color _tierBgColor(String tier) {
    switch (tier) {
      case 'champion':
        return const Color(0xFF1a1030);
      case 'diamond':
        return const Color(0xFF0a1828);
      case 'gold':
        return const Color(0xFF1a1200);
      case 'silver':
        return const Color(0xFF0f1520);
      default:
        return const Color(0xFF1a0f00);
    }
  }

  List<Color> _tierGradient(String tier) {
    switch (tier) {
      case 'champion':
        return [const Color(0xFF2a1a4a), const Color(0xFF663399)];
      case 'diamond':
        return [const Color(0xFF0a1a3a), const Color(0xFF1a5a9a)];
      case 'gold':
        return [const Color(0xFF2a1a00), const Color(0xFF8a5a00)];
      case 'silver':
        return [const Color(0xFF1a2530), const Color(0xFF4a5560)];
      default:
        return [const Color(0xFF2a1500), const Color(0xFF6a3500)];
    }
  }
}
