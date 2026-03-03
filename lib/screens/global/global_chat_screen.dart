import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class GlobalChatScreen extends StatefulWidget {
  const GlobalChatScreen({super.key});

  @override
  State<GlobalChatScreen> createState() => _GlobalChatScreenState();
}

class _GlobalChatScreenState extends State<GlobalChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  String _activeChannel = 'market';

  final List<Map<String, String>> _channels = [
    {
      'id': 'market',
      'label': '📈 Market',
      'placeholder': 'What\'s your market take?',
    },
    {
      'id': 'ranked',
      'label': '🏆 Ranked',
      'placeholder': 'Flex your rank or talk ranked...',
    },
    {
      'id': 'tips',
      'label': '💡 Tips',
      'placeholder': 'Share a strategy or tip...',
    },
    {
      'id': 'hot',
      'label': '🔥 Hot Takes',
      'placeholder': 'Drop your hottest take...',
    },
  ];

  final List<String> _emojiOptions = ['🔥', '💯', '💎', '💀', '🚀', '😂'];

  // ── Delete post ──

  Future<void> _deletePost(String postId, String? imageUrl) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0d1018),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Post',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to delete this post?',
            style: TextStyle(color: Color(0xFF567090), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF567090))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Color(0xFFcf6679), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete the post doc
      await _firestore
          .collection('globalChat')
          .doc(_activeChannel)
          .collection('posts')
          .doc(postId)
          .delete();

      // Delete image from storage if exists
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await _storage.refFromURL(imageUrl).delete();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: const Color(0xFFcf6679),
          ),
        );
      }
    }
  }

  // ── Reactions ──

  Future<void> _addReaction(String postId, String emoji) async {
    final ref = _firestore
        .collection('globalChat')
        .doc(_activeChannel)
        .collection('posts')
        .doc(postId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final reactions = Map<String, int>.from(snap.data()?['reactions'] ?? {});
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      tx.update(ref, {'reactions': reactions});
    });
  }

  // ── Relative time ──

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final date = ts.toDate();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070e),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00ff87),
        onPressed: _openPostComposer,
        child: const Icon(Icons.edit_rounded, color: Colors.black, size: 22),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildChannelTabs(),
            _buildOnlineStrip(),
            Expanded(child: _buildPostFeed()),
          ],
        ),
      ),
    );
  }

  // ── Header ──

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

  // ── Channel tabs ──

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
                    color: isActive
                        ? const Color(0xFF00ff87)
                        : Colors.transparent,
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

  // ── Online strip ──

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

  // ── Post feed ──

  Widget _buildPostFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('globalChat')
          .doc(_activeChannel)
          .collection('posts')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00ff87)),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.forum_outlined,
                    color: Color(0xFF1a2535), size: 48),
                const SizedBox(height: 12),
                Text(
                  'No posts yet — be the first!',
                  style: TextStyle(
                    color: const Color(0xFF567090).withValues(alpha: 0.7),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return _buildPostCard(docs[i].id, data);
          },
        );
      },
    );
  }

  // ── Post card ──

  Widget _buildPostCard(String postId, Map<String, dynamic> data) {
    final username = data['username'] ?? 'Player';
    final text = data['text'] ?? '';
    final tier = data['tier'] ?? 'bronze';
    final globalRank = data['globalRank'] ?? 9999;
    final reactions = Map<String, int>.from(data['reactions'] ?? {});
    final commentCount = data['commentCount'] ?? 0;
    final imageUrl = data['imageUrl'] as String?;
    final ts = data['timestamp'] as Timestamp?;

    final initials = username.length >= 2
        ? username.substring(0, 2).toUpperCase()
        : username.toUpperCase();
    final tierEmoji = _tierEmoji(tier);
    final rankStr = globalRank <= 100 ? '#$globalRank' : tier.toUpperCase();
    final isMe = data['uid'] == _auth.currentUser?.uid;

    return GestureDetector(
      onLongPress: () => _showReactionPicker(postId, _emojiOptions),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0d1018),
          border: Border.all(color: const Color(0xFF1a2535)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Row(
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
                          : _tierGradient(tier),
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isMe ? 'You' : username,
                            style: TextStyle(
                              color:
                                  isMe ? const Color(0xFF00ff87) : _tierColor(tier),
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _tierBadge(tierEmoji, rankStr, tier),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _relativeTime(ts),
                        style: const TextStyle(
                          color: Color(0xFF2d4055),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                if (isMe)
                  GestureDetector(
                    onTap: () => _deletePost(postId, imageUrl),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.more_horiz_rounded,
                          color: Color(0xFF567090), size: 20),
                    ),
                  ),
              ],
            ),

            // ── Text body ──
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],

            // ── Image ──
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 200,
                        color: const Color(0xFF121720),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF00ff87),
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) => Container(
                      height: 100,
                      color: const Color(0xFF121720),
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Color(0xFF567090), size: 32),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // ── Action bar ──
            const SizedBox(height: 12),
            Row(
              children: [
                // Reactions
                if (reactions.isNotEmpty)
                  Expanded(child: _buildReactions(postId, reactions))
                else
                  const Spacer(),

                // Comment button
                GestureDetector(
                  onTap: () => _openCommentsSheet(postId),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121720),
                      border: Border.all(color: const Color(0xFF1a2535)),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            color: Color(0xFF567090), size: 14),
                        if (commentCount > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$commentCount',
                            style: const TextStyle(
                              color: Color(0xFF567090),
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Reactions ──

  Widget _buildReactions(String postId, Map<String, int> reactions) {
    return Wrap(
      spacing: 4,
      children: reactions.entries.map((e) {
        return GestureDetector(
          onTap: () => _addReaction(postId, e.key),
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

  // ── Reaction picker ──

  void _showReactionPicker(String postId, List<String> emojis) {
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
                          _addReaction(postId, e);
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

  // ── Post composer ──

  void _openPostComposer() {
    final channelInfo =
        _channels.firstWhere((c) => c['id'] == _activeChannel);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PostComposerSheet(
        channel: _activeChannel,
        placeholder: channelInfo['placeholder']!,
        firestore: _firestore,
        auth: _auth,
        storage: _storage,
      ),
    );
  }

  // ── Comments sheet ──

  void _openCommentsSheet(String postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CommentsSheet(
        channel: _activeChannel,
        postId: postId,
        firestore: _firestore,
        auth: _auth,
      ),
    );
  }

  // ── Tier helpers ──

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

// ═══════════════════════════════════════════════════════════════════
// Post Composer Sheet
// ═══════════════════════════════════════════════════════════════════

class _PostComposerSheet extends StatefulWidget {
  final String channel;
  final String placeholder;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseStorage storage;

  const _PostComposerSheet({
    required this.channel,
    required this.placeholder,
    required this.firestore,
    required this.auth,
    required this.storage,
  });

  @override
  State<_PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<_PostComposerSheet> {
  final _textController = TextEditingController();
  Uint8List? _imageBytes;
  bool _posting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 75,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
    });
  }

  Future<void> _submitPost() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _imageBytes == null) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    setState(() => _posting = true);

    try {
      // Get ranked profile
      final profileDoc = await widget.firestore
          .collection('rankedProfiles')
          .doc(user.uid)
          .get();

      final username = profileDoc.exists
          ? (profileDoc.data()?['username'] ?? 'Player')
          : 'Player';
      final tier = profileDoc.exists
          ? (profileDoc.data()?['tier'] ?? 'bronze')
          : 'bronze';
      final globalRank = profileDoc.exists
          ? (profileDoc.data()?['globalRank'] ?? 9999)
          : 9999;

      // Create post doc first to get ID
      final postRef = widget.firestore
          .collection('globalChat')
          .doc(widget.channel)
          .collection('posts')
          .doc();

      String? imageUrl;

      // Upload image if present
      if (_imageBytes != null) {
        final path = 'globalChat/${widget.channel}/${postRef.id}.jpg';
        final ref = widget.storage.ref(path);
        final metadata = SettableMetadata(contentType: 'image/jpeg');
        await ref.putData(_imageBytes!, metadata);
        imageUrl = await ref.getDownloadURL();
      }

      // Write post
      await postRef.set({
        'uid': user.uid,
        'username': username,
        'text': text,
        'imageUrl': imageUrl,
        'tier': tier,
        'globalRank': globalRank,
        'timestamp': FieldValue.serverTimestamp(),
        'reactions': <String, int>{},
        'commentCount': 0,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post: $e'),
            backgroundColor: const Color(0xFFcf6679),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.3),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF0d1018),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0xFF1a2535)),
          left: BorderSide(color: Color(0xFF1a2535)),
          right: BorderSide(color: Color(0xFF1a2535)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF1a2535),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Row(
              children: [
                const Text(
                  'New Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  _channelLabel(widget.channel),
                  style: const TextStyle(
                    color: Color(0xFF567090),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Text input
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: TextField(
              controller: _textController,
              autofocus: true,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle:
                    const TextStyle(color: Color(0xFF567090), fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF1a2535)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF1a2535)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF00ff87)),
                ),
                filled: true,
                fillColor: const Color(0xFF080b14),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),

          // Image preview
          if (_imageBytes != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Image.memory(
                        _imageBytes!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _imageBytes = null;
                      }),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Bottom row
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _posting ? null : _pickImage,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF121720),
                      border: Border.all(color: const Color(0xFF1a2535)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.image_outlined,
                        color: Color(0xFF567090), size: 20),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _posting ? null : _submitPost,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: _posting
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF00ff87), Color(0xFF00e676)],
                            ),
                      color: _posting ? const Color(0xFF1a2535) : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _posting
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFF00ff87)
                                    .withValues(alpha: 0.22),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Color(0xFF567090),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Post',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
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

  String _channelLabel(String id) {
    switch (id) {
      case 'market':
        return '📈 Market';
      case 'ranked':
        return '🏆 Ranked';
      case 'tips':
        return '💡 Tips';
      case 'hot':
        return '🔥 Hot Takes';
      default:
        return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Comments Sheet
// ═══════════════════════════════════════════════════════════════════

class _CommentsSheet extends StatefulWidget {
  final String channel;
  final String postId;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const _CommentsSheet({
    required this.channel,
    required this.postId,
    required this.firestore,
    required this.auth,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _commentController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final user = widget.auth.currentUser;
    if (user == null) return;

    setState(() => _sending = true);
    _commentController.clear();

    try {
      final profileDoc = await widget.firestore
          .collection('rankedProfiles')
          .doc(user.uid)
          .get();
      final username = profileDoc.exists
          ? (profileDoc.data()?['username'] ?? 'Player')
          : 'Player';

      final postRef = widget.firestore
          .collection('globalChat')
          .doc(widget.channel)
          .collection('posts')
          .doc(widget.postId);

      final commentRef = postRef.collection('comments').doc();

      final batch = widget.firestore.batch();
      batch.set(commentRef, {
        'uid': user.uid,
        'username': username,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {'commentCount': FieldValue.increment(1)});
      await batch.commit();
    } catch (e) {
      // Silently handle
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final date = ts.toDate();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (ctx, scrollController) {
        return Container(
          padding: EdgeInsets.only(bottom: bottomInset),
          decoration: const BoxDecoration(
            color: Color(0xFF0d1018),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: Color(0xFF1a2535)),
              left: BorderSide(color: Color(0xFF1a2535)),
              right: BorderSide(color: Color(0xFF1a2535)),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF1a2535),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Comments',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const Divider(color: Color(0xFF1a2535), height: 1),

              // Comments list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: widget.firestore
                      .collection('globalChat')
                      .doc(widget.channel)
                      .collection('posts')
                      .doc(widget.postId)
                      .collection('comments')
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
                  builder: (ctx, snap) {
                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00ff87)),
                      );
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No comments yet',
                          style: TextStyle(
                            color: Color(0xFF567090),
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final data =
                            docs[i].data() as Map<String, dynamic>;
                        final isMe =
                            data['uid'] == widget.auth.currentUser?.uid;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
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
                                  ),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Center(
                                  child: Text(
                                    () {
                                      final n = (data['username'] ?? 'PL') as String;
                                      return n.length >= 2
                                          ? n.substring(0, 2).toUpperCase()
                                          : n.toUpperCase();
                                    }(),
                                    style: TextStyle(
                                      color:
                                          isMe ? Colors.black : Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          isMe
                                              ? 'You'
                                              : (data['username'] ??
                                                  'Player'),
                                          style: TextStyle(
                                            color: isMe
                                                ? const Color(0xFF00ff87)
                                                : Colors.white,
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _relativeTime(
                                              data['timestamp']
                                                  as Timestamp?),
                                          style: const TextStyle(
                                            color: Color(0xFF2d4055),
                                            fontSize: 9,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      data['text'] ?? '',
                                      style: const TextStyle(
                                        color: Color(0xFFc0c8d4),
                                        fontSize: 13,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Comment input
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: const BoxDecoration(
                  border:
                      Border(top: BorderSide(color: Color(0xFF1a2535))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF080b14),
                          border:
                              Border.all(color: const Color(0xFF1a2535)),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: TextField(
                          controller: _commentController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: TextStyle(
                                color: Color(0xFF567090), fontSize: 12),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          onSubmitted: (_) => _addComment(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sending ? null : _addComment,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00ff87),
                              Color(0xFF00e676)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded,
                                color: Colors.black, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
