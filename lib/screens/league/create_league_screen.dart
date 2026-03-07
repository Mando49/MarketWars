import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'invite_players_screen.dart';

class CreateLeagueScreen extends StatefulWidget {
  const CreateLeagueScreen({super.key});
  @override
  State<CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends State<CreateLeagueScreen> {
  final _nameCtrl = TextEditingController();
  bool _creating = false;

  // Settings
  String _rosterMode = 'standard'; // 'standard' or 'sectors'
  int _rosterSize = 10;
  int _maxPlayers = 8;
  String _draftMode = 'unique'; // 'unique' or 'open'
  int _tradeLimit = 3;
  int _seasonLength = 12;
  int _playoffTeams = 4;
  int _startingBalance = 10000;

  static const _maxPlayerOptions = [2, 4, 6, 8, 10];
  static const _seasonOptions = [4, 6, 8, 10, 12];
  static const _playoffOptions = [2, 4, 8];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a league name'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }
    setState(() => _creating = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('leagues').doc();
      final inviteCode = _generateCode();

      await docRef.set({
        'name': name,
        'commissionerUID': uid,
        'rosterMode': _rosterMode,
        'rosterSize': _rosterMode == 'sectors' ? 11 : _rosterSize,
        'maxPlayers': _maxPlayers,
        'draftMode': _draftMode,
        'tradeLimit': _tradeLimit,
        'totalWeeks': _seasonLength,
        'playoffTeams': _playoffTeams,
        'startingBalance': _startingBalance,
        'scoringMode': 'weeklyPctChange',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'members': [uid],
        'inviteCode': inviteCode,
      });

      await db
          .collection('leagueCodes')
          .doc(inviteCode)
          .set({'leagueId': docRef.id});

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InvitePlayersScreen(
              leagueId: docRef.id,
              leagueName: name,
              inviteCode: inviteCode,
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
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create League'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x33FFD700),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'COMM',
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppTheme.gold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── League Name ──
          _label('LEAGUE NAME'),
          _inputCard(_nameCtrl, 'Wall Street Warriors...'),
          const SizedBox(height: 8),

          // ── Roster Mode ──
          _label('ROSTER MODE'),
          _optionCard(
            title: 'Standard',
            subtitle: 'Pick 5 to 15 stocks from any sector',
            selected: _rosterMode == 'standard',
            onTap: () => setState(() => _rosterMode = 'standard'),
          ),
          const SizedBox(height: 8),
          _optionCard(
            title: 'Sectors',
            subtitle: '11 stocks — one per GICS sector',
            selected: _rosterMode == 'sectors',
            onTap: () => setState(() => _rosterMode = 'sectors'),
          ),
          if (_rosterMode == 'standard') ...[
            const SizedBox(height: 12),
            _sliderSection(
              'ROSTER SIZE',
              _rosterSize.toDouble(),
              5,
              15,
              11,
              (v) => setState(() => _rosterSize = v.round()),
              suffix: ' stocks',
            ),
          ],
          const SizedBox(height: 8),

          // ── Max Players ──
          _label('MAX PLAYERS'),
          _chipRow(
            options: _maxPlayerOptions,
            selected: _maxPlayers,
            onSelect: (v) => setState(() => _maxPlayers = v),
            suffix: '',
          ),
          const SizedBox(height: 8),

          // ── Draft Mode ──
          _label('DRAFT MODE'),
          _optionCard(
            title: 'Unique',
            subtitle: 'Each stock can only be drafted once',
            selected: _draftMode == 'unique',
            onTap: () => setState(() => _draftMode = 'unique'),
          ),
          const SizedBox(height: 8),
          _optionCard(
            title: 'Open',
            subtitle: 'Multiple players can draft the same stock',
            selected: _draftMode == 'open',
            onTap: () => setState(() => _draftMode = 'open'),
          ),
          const SizedBox(height: 8),

          // ── Trade Limit ──
          _sliderSection(
            'TRADE LIMIT PER WEEK',
            _tradeLimit.toDouble(),
            0,
            5,
            6,
            (v) => setState(() => _tradeLimit = v.round()),
            suffix: _tradeLimit == 0 ? ' (no trades)' : ' trades',
          ),
          const SizedBox(height: 8),

          // ── Season Length ──
          _label('SEASON LENGTH'),
          _chipRow(
            options: _seasonOptions,
            selected: _seasonLength,
            onSelect: (v) => setState(() => _seasonLength = v),
            suffix: 'wk',
          ),
          const SizedBox(height: 8),

          // ── Playoff Teams ──
          _label('PLAYOFF TEAMS'),
          _chipRow(
            options: _playoffOptions,
            selected: _playoffTeams,
            onSelect: (v) => setState(() => _playoffTeams = v),
            suffix: '',
          ),
          const SizedBox(height: 8),

          // ── Starting Portfolio Value ──
          _label('STARTING PORTFOLIO VALUE'),
          _chipRow(
            options: const [10000, 50000, 100000],
            selected: _startingBalance,
            onSelect: (v) => setState(() => _startingBalance = v),
            suffix: '',
            formatAsCurrency: true,
          ),
          const SizedBox(height: 8),

          // ── Scoring Mode ──
          _label('SCORING MODE'),
          _optionCard(
            title: 'Weekly % Change',
            subtitle: 'Default — compare portfolio return each week',
            selected: true,
            onTap: () {},
          ),

          const SizedBox(height: 28),

          // ── Create Button ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _creating ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _creating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Create League',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ──

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
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

  Widget _inputCard(TextEditingController ctrl, String hint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          border: Border.all(color: AppTheme.border2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            border: InputBorder.none,
          ),
        ),
      );

  Widget _optionCard({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.greenDim : AppTheme.surface2,
            border: Border.all(
              color: selected ? AppTheme.greenBorder : AppTheme.border,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppTheme.green : AppTheme.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppTheme.green, size: 20),
            ],
          ),
        ),
      );

  Widget _sliderSection(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged, {
    String suffix = '',
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              border: Border.all(color: AppTheme.border2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${value.round()}$suffix',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                      ),
                    ),
                    Text(
                      '${min.round()} – ${max.round()}',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppTheme.green,
                    inactiveTrackColor: AppTheme.border2,
                    thumbColor: AppTheme.green,
                    overlayColor: AppTheme.green.withValues(alpha: 0.15),
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _chipRow({
    required List<int> options,
    required int selected,
    required ValueChanged<int> onSelect,
    required String suffix,
    bool formatAsCurrency = false,
  }) =>
      Row(
        children: options.map((v) {
          final isSelected = v == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(v),
              child: Container(
                margin: EdgeInsets.only(
                  right: v == options.last ? 0 : 8,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.greenDim : AppTheme.surface2,
                  border: Border.all(
                    color:
                        isSelected ? AppTheme.greenBorder : AppTheme.border,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    formatAsCurrency
                        ? AppTheme.currency(v, decimals: 0)
                        : '$v$suffix',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppTheme.green : AppTheme.text,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
    );
  }
}
