// ═══════════════════════════════════════════════════════
// models.dart  –  ALL MarketWars data models
// ═══════════════════════════════════════════════════════

// ── USER PROFILE ──
class UserProfile {
  final String id;
  final String username;
  final String email;
  double cashBalance;
  double totalValue;
  final DateTime createdAt;
  static const double startingBalance = 10000.0;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.cashBalance,
    required this.totalValue,
    required this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, String id) =>
      UserProfile(
        id: id,
        username: map['username'] ?? '',
        email: map['email'] ?? '',
        cashBalance: (map['cashBalance'] ?? startingBalance).toDouble(),
        totalValue: (map['totalValue'] ?? startingBalance).toDouble(),
        createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'username': username,
        'email': email,
        'cashBalance': cashBalance,
        'totalValue': totalValue,
        'createdAt': createdAt,
      };
}

// ── PORTFOLIO HOLDING (long position) ──
class PortfolioHolding {
  final String symbol, companyName;
  double shares, averageCost, currentPrice;

  PortfolioHolding({
    required this.symbol,
    required this.companyName,
    required this.shares,
    required this.averageCost,
    required this.currentPrice,
  });

  double get totalValue => shares * currentPrice;
  double get totalCost => shares * averageCost;
  double get gainLoss => totalValue - totalCost;
  double get gainLossPercent =>
      totalCost > 0 ? (gainLoss / totalCost) * 100 : 0;

  factory PortfolioHolding.fromMap(Map<String, dynamic> map) =>
      PortfolioHolding(
        symbol: map['symbol'] ?? '',
        companyName: map['companyName'] ?? '',
        shares: (map['shares'] ?? 0).toDouble(),
        averageCost: (map['averageCost'] ?? 0).toDouble(),
        currentPrice: (map['currentPrice'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'symbol': symbol,
        'companyName': companyName,
        'shares': shares,
        'averageCost': averageCost,
        'currentPrice': currentPrice,
      };
}

// ── SHORT POSITION ──
// Player bets stock goes DOWN. They profit when currentPrice < priceAtShort.
class ShortPosition {
  final String symbol, companyName;
  double shares, priceAtShort, currentPrice;

  ShortPosition({
    required this.symbol,
    required this.companyName,
    required this.shares,
    required this.priceAtShort,
    required this.currentPrice,
  });

  // Cash received when the short was opened
  double get proceeds => shares * priceAtShort;
  // Current cost to buy back
  double get totalValue => shares * currentPrice;
  // Positive = stock went down (profit). Negative = stock went up (loss).
  double get gainLoss => proceeds - totalValue;
  double get gainLossPercent => proceeds > 0 ? (gainLoss / proceeds) * 100 : 0;

  factory ShortPosition.fromMap(Map<String, dynamic> map) => ShortPosition(
        symbol: map['symbol'] ?? '',
        companyName: map['companyName'] ?? '',
        shares: (map['shares'] ?? 0).toDouble(),
        priceAtShort: (map['priceAtShort'] ?? 0).toDouble(),
        currentPrice: (map['currentPrice'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'symbol': symbol,
        'companyName': companyName,
        'shares': shares,
        'priceAtShort': priceAtShort,
        'currentPrice': currentPrice,
      };
}

// ── TRADE ──
enum TradeType { buy, sell, short, coverShort }

class Trade {
  final String id, symbol, companyName;
  final TradeType type;
  final double shares, pricePerShare, totalAmount;
  final DateTime timestamp;

  Trade({
    required this.id,
    required this.symbol,
    required this.companyName,
    required this.type,
    required this.shares,
    required this.pricePerShare,
    required this.totalAmount,
    required this.timestamp,
  });

  factory Trade.fromMap(Map<String, dynamic> map, String id) => Trade(
        id: id,
        symbol: map['symbol'] ?? '',
        companyName: map['companyName'] ?? '',
        type: TradeType.values.firstWhere(
          (t) => t.name == (map['type'] ?? 'buy'),
          orElse: () => TradeType.buy,
        ),
        shares: (map['shares'] ?? 0).toDouble(),
        pricePerShare: (map['pricePerShare'] ?? 0).toDouble(),
        totalAmount: (map['totalAmount'] ?? 0).toDouble(),
        timestamp: (map['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'symbol': symbol,
        'companyName': companyName,
        'type': type.name,
        'shares': shares,
        'pricePerShare': pricePerShare,
        'totalAmount': totalAmount,
        'timestamp': timestamp,
      };
}

// ── STOCK QUOTE ──
class StockQuote {
  final double currentPrice, change, changePercent, high, low, open, prevClose;

  StockQuote({
    required this.currentPrice,
    required this.change,
    required this.changePercent,
    required this.high,
    required this.low,
    required this.open,
    required this.prevClose,
  });

  factory StockQuote.fromJson(Map<String, dynamic> json) => StockQuote(
        currentPrice: (json['c'] ?? 0).toDouble(),
        change: (json['d'] ?? 0).toDouble(),
        changePercent: (json['dp'] ?? 0).toDouble(),
        high: (json['h'] ?? 0).toDouble(),
        low: (json['l'] ?? 0).toDouble(),
        open: (json['o'] ?? 0).toDouble(),
        prevClose: (json['pc'] ?? 0).toDouble(),
      );

  bool get isPositive => changePercent >= 0;
}

// ── STOCK SEARCH RESULT ──
class StockResult {
  final String symbol, description, type;
  StockResult(
      {required this.symbol, required this.description, required this.type});

  factory StockResult.fromJson(Map<String, dynamic> json) => StockResult(
        symbol: json['symbol'] ?? '',
        description: json['description'] ?? '',
        type: json['type'] ?? '',
      );
}

// ── TRENDING STOCK ──
class TrendingStock {
  final int rank;
  final String symbol, companyName;
  final double price, changePercent;
  final bool isUp;
  final List<double> sparkline;

  TrendingStock({
    required this.rank,
    required this.symbol,
    required this.companyName,
    required this.price,
    required this.changePercent,
    required this.isUp,
    required this.sparkline,
  });

  factory TrendingStock.fromFinnhub({
    required int rank,
    required String symbol,
    required String companyName,
    required double price,
    required double changePercent,
  }) {
    final isUp = changePercent >= 0;
    final base = price / (1 + changePercent / 100);
    final step = (price - base) / 6;
    final spark = List.generate(7, (i) {
      final noise = (i % 2 == 0 ? 0.4 : -0.3) * price * 0.005;
      return base + step * i + noise;
    });
    return TrendingStock(
      rank: rank,
      symbol: symbol,
      companyName: companyName,
      price: price,
      changePercent: changePercent,
      isUp: isUp,
      sparkline: spark,
    );
  }
}

// ── LEAGUE ──
enum LeagueStatus { pending, drafting, active, playoffs, complete }

class League {
  final String id, name, commissionerUID, inviteCode;
  final bool isPublic;
  final int maxPlayers, currentWeek, totalWeeks, playoffWeeks, playoffTeams;
  LeagueStatus status;
  final DateTime createdAt;
  List<String> members;
  String? tier;
  // 'unique' = FF style (no duplicate picks), 'open' = same stock allowed
  final String draftMode;
  final double startingBalance;
  final DateTime? startDate;

  League({
    required this.id,
    required this.name,
    required this.commissionerUID,
    required this.inviteCode,
    required this.isPublic,
    required this.maxPlayers,
    required this.currentWeek,
    required this.totalWeeks,
    required this.playoffWeeks,
    required this.playoffTeams,
    required this.status,
    required this.createdAt,
    required this.members,
    this.tier,
    this.draftMode = 'unique',
    this.startingBalance = 10000.0,
    this.startDate,
  });

  /// Calculate the current week based on startDate. Returns 1 if no startDate.
  int get calculatedWeek {
    if (startDate == null) return currentWeek > 0 ? currentWeek : 1;
    final days = DateTime.now().difference(startDate!).inDays;
    final week = (days ~/ 7) + 1;
    return week.clamp(1, totalWeeks);
  }

  int get playoffStartWeek => totalWeeks - playoffWeeks + 1;
  double get weekProgress => totalWeeks > 0 ? currentWeek / totalWeeks : 0;
  bool get isUniqueDraft => draftMode == 'unique';

  factory League.fromMap(Map<String, dynamic> map, String id) {
    return League(
        id: id,
        name: map['name'] ?? map['leagueName'] ?? '',
        commissionerUID: map['commissionerUID'] ?? '',
        inviteCode: map['inviteCode'] ?? '',
        isPublic: map['isPublic'] ?? false,
        maxPlayers: map['maxPlayers'] ?? 8,
        currentWeek: map['currentWeek'] ?? 0,
        totalWeeks: map['totalWeeks'] ?? map['seasonLength'] ?? 12,
        playoffWeeks: map['playoffWeeks'] ?? 3,
        playoffTeams: map['playoffTeams'] ?? 4,
        status: LeagueStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => LeagueStatus.pending,
        ),
        createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
        members: List<String>.from(map['members'] ?? []),
        tier: map['tier'],
        draftMode: map['draftMode'] ?? 'unique',
        startingBalance: (map['startingBalance'] ?? 10000).toDouble(),
        startDate: map['startDate'] != null
            ? (map['startDate'] is String
                ? DateTime.tryParse(map['startDate'])
                : (map['startDate'] as dynamic).toDate())
            : null,
      );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'commissionerUID': commissionerUID,
        'inviteCode': inviteCode,
        'isPublic': isPublic,
        'maxPlayers': maxPlayers,
        'currentWeek': currentWeek,
        'totalWeeks': totalWeeks,
        'playoffWeeks': playoffWeeks,
        'playoffTeams': playoffTeams,
        'status': status.name,
        'createdAt': createdAt,
        'members': members,
        'draftMode': draftMode,
        'startingBalance': startingBalance,
        if (tier != null) 'tier': tier,
      };
}

// ── LEAGUE MEMBER ──
class LeagueMember {
  final String id, username, leagueId;
  int wins, losses;
  double totalValue, cashBalance;
  int seed;
  bool isEliminated;

  LeagueMember({
    required this.id,
    required this.username,
    required this.leagueId,
    required this.wins,
    required this.losses,
    required this.totalValue,
    required this.cashBalance,
    required this.seed,
    required this.isEliminated,
  });

  String get record => '$wins-$losses';
  double gainLoss(double startingBalance) => totalValue - startingBalance;
  double gainLossPercent(double startingBalance) {
    if (startingBalance == 0) return 0;
    return (gainLoss(startingBalance) / startingBalance) * 100;
  }

  factory LeagueMember.fromMap(Map<String, dynamic> map, String id) =>
      LeagueMember(
        id: id,
        username: map['username'] ?? '',
        leagueId: map['leagueId'] ?? '',
        wins: map['wins'] ?? 0,
        losses: map['losses'] ?? 0,
        totalValue:
            (map['totalValue'] ?? UserProfile.startingBalance).toDouble(),
        cashBalance:
            (map['cashBalance'] ?? UserProfile.startingBalance).toDouble(),
        seed: map['seed'] ?? 1,
        isEliminated: map['isEliminated'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'username': username,
        'leagueId': leagueId,
        'wins': wins,
        'losses': losses,
        'totalValue': totalValue,
        'cashBalance': cashBalance,
        'seed': seed,
        'isEliminated': isEliminated,
      };
}

// ── MATCHUP ──
class Matchup {
  final String id, leagueId, homeUID, awayUID, homeUsername, awayUsername;
  final int week;
  double homeValue, awayValue;
  String? winnerId;
  final bool isPlayoff;

  Matchup({
    required this.id,
    required this.leagueId,
    required this.week,
    required this.homeUID,
    required this.awayUID,
    required this.homeValue,
    required this.awayValue,
    required this.homeUsername,
    required this.awayUsername,
    this.winnerId,
    required this.isPlayoff,
  });

  bool get isComplete => winnerId != null;
  double get leadAmount => (homeValue - awayValue).abs();
  double valueFor(String uid) => uid == homeUID ? homeValue : awayValue;
  String opponentUID(String uid) => uid == homeUID ? awayUID : homeUID;
  String opponentUsername(String uid) =>
      uid == homeUID ? awayUsername : homeUsername;

  factory Matchup.fromMap(Map<String, dynamic> map, String id) => Matchup(
        id: id,
        leagueId: map['leagueId'] ?? '',
        week: map['week'] ?? 0,
        homeUID: map['homeUID'] ?? '',
        awayUID: map['awayUID'] ?? '',
        homeValue: (map['homeValue'] ?? 0).toDouble(),
        awayValue: (map['awayValue'] ?? 0).toDouble(),
        homeUsername: map['homeUsername'] ?? '',
        awayUsername: map['awayUsername'] ?? '',
        winnerId: map['winnerId'],
        isPlayoff: map['isPlayoff'] ?? false,
      );
}

// ── CHAT MESSAGE ──
class ChatMessage {
  final String id, leagueId, senderUID, senderUsername, text;
  final Map<String, int> reactions;
  final bool isSystemEvent;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.leagueId,
    required this.senderUID,
    required this.senderUsername,
    required this.text,
    required this.reactions,
    required this.isSystemEvent,
    required this.timestamp,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map, String id) =>
      ChatMessage(
        id: id,
        leagueId: map['leagueId'] ?? '',
        senderUID: map['senderUID'] ?? '',
        senderUsername: map['senderUsername'] ?? '',
        text: map['text'] ?? '',
        reactions: Map<String, int>.from(map['reactions'] ?? {}),
        isSystemEvent: map['isSystemEvent'] ?? false,
        timestamp: (map['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'leagueId': leagueId,
        'senderUID': senderUID,
        'senderUsername': senderUsername,
        'text': text,
        'reactions': reactions,
        'isSystemEvent': isSystemEvent,
        'timestamp': timestamp,
      };
}

// ── DRAFT PICK ──
class DraftPick {
  final String id, leagueId, pickedByUID, pickedByUsername, symbol, companyName;
  final int round, pickNumber;
  final double priceAtDraft;
  final DateTime timestamp;

  DraftPick({
    required this.id,
    required this.leagueId,
    required this.round,
    required this.pickNumber,
    required this.pickedByUID,
    required this.pickedByUsername,
    required this.symbol,
    required this.companyName,
    required this.priceAtDraft,
    required this.timestamp,
  });

  factory DraftPick.fromMap(Map<String, dynamic> map, String id) => DraftPick(
        id: id,
        leagueId: map['leagueId'] ?? '',
        round: map['round'] ?? 1,
        pickNumber: map['pickNumber'] ?? 1,
        pickedByUID: map['pickedByUID'] ?? '',
        pickedByUsername: map['pickedByUsername'] ?? '',
        symbol: map['symbol'] ?? '',
        companyName: map['companyName'] ?? '',
        priceAtDraft: (map['priceAtDraft'] ?? 0).toDouble(),
        timestamp: (map['timestamp'] as dynamic)?.toDate() ?? DateTime.now(),
      );
}

// ── RANKED TIER ──
enum RankTier { bronze, silver, gold, diamond, champion }

extension RankTierExt on RankTier {
  String get label {
    const labels = ['Bronze', 'Silver', 'Gold', 'Diamond', 'Champion'];
    return labels[index];
  }

  String get emoji {
    const emojis = ['🥉', '🥈', '🥇', '💎', '👑'];
    return emojis[index];
  }

  int get minPoints {
    const mins = [0, 1000, 2000, 3000, 4000];
    return mins[index];
  }

  int get maxPoints {
    const maxs = [999, 1999, 2999, 3999, 999999];
    return maxs[index];
  }

  RankTier? get next {
    const all = RankTier.values;
    return index < all.length - 1 ? all[index + 1] : null;
  }

  static RankTier fromPoints(int pts) {
    if (pts >= 4000) return RankTier.champion;
    if (pts >= 3000) return RankTier.diamond;
    if (pts >= 2000) return RankTier.gold;
    if (pts >= 1000) return RankTier.silver;
    return RankTier.bronze;
  }
}

// ── RANKED PROFILE ──
class RankedProfile {
  final String uid, username, seasonId;
  int totalPoints, seasonPoints, globalRank, wins, losses, leagueWins;
  double bestWeekROI;
  DateTime lastUpdated;

  RankedProfile({
    required this.uid,
    required this.username,
    required this.totalPoints,
    required this.seasonPoints,
    required this.globalRank,
    required this.wins,
    required this.losses,
    required this.leagueWins,
    required this.bestWeekROI,
    required this.seasonId,
    required this.lastUpdated,
  });

  RankTier get tier => RankTierExt.fromPoints(seasonPoints);
  int get totalGames => wins + losses;
  double get winRate => totalGames > 0 ? wins / totalGames : 0;
  int get pointsToNextTier {
    final next = tier.next;
    return next == null ? 0 : next.minPoints - seasonPoints;
  }

  double get tierProgress {
    final t = tier;
    final range = t.maxPoints - t.minPoints + 1;
    return ((seasonPoints - t.minPoints) / range).clamp(0.0, 1.0);
  }

  factory RankedProfile.fromMap(Map<String, dynamic> map, String uid) =>
      RankedProfile(
        uid: uid,
        username: map['username'] ?? '',
        totalPoints: map['totalPoints'] ?? 0,
        seasonPoints: map['seasonPoints'] ?? 0,
        globalRank: map['globalRank'] ?? 9999,
        wins: map['wins'] ?? 0,
        losses: map['losses'] ?? 0,
        leagueWins: map['leagueWins'] ?? 0,
        bestWeekROI: (map['bestWeekROI'] ?? 0).toDouble(),
        seasonId: map['seasonId'] ?? '',
        lastUpdated:
            (map['lastUpdated'] as dynamic)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'username': username,
        'totalPoints': totalPoints,
        'seasonPoints': seasonPoints,
        'globalRank': globalRank,
        'wins': wins,
        'losses': losses,
        'leagueWins': leagueWins,
        'bestWeekROI': bestWeekROI,
        'seasonId': seasonId,
        'lastUpdated': lastUpdated,
        'tier': tier.name,
      };
}

// ── POINTS SYSTEM ──
class PointsSystem {
  static const int matchupWin = 100;
  static const int matchupLoss = -40;
  static const int leagueWin = 500;
  static const int reachPlayoffs = 200;
  static const int weekROI10pct = 150;
  static const int weekROI20pct = 300;
  static const int quickMatchBonus = 20;
}

// ── SEASON ──
class Season {
  final String id, name;
  final DateTime startDate, endDate;
  final bool isActive;

  Season({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  Duration get timeRemaining => endDate.difference(DateTime.now());
  int get daysLeft => timeRemaining.inDays;
  int get hoursLeft => timeRemaining.inHours % 24;
  int get minutesLeft => timeRemaining.inMinutes % 60;
  int get secondsLeft => timeRemaining.inSeconds % 60;

  factory Season.fromMap(Map<String, dynamic> map, String id) => Season(
        id: id,
        name: map['name'] ?? '',
        startDate: (map['startDate'] as dynamic)?.toDate() ?? DateTime.now(),
        endDate: (map['endDate'] as dynamic)?.toDate() ?? DateTime.now(),
        isActive: map['isActive'] ?? false,
      );
}

// ── LEADERBOARD ENTRY ──
class LeaderboardEntry {
  final String uid, username;
  final int rank, points, pointsDelta, wins, losses;
  final RankTier tier;

  LeaderboardEntry({
    required this.uid,
    required this.username,
    required this.rank,
    required this.points,
    required this.pointsDelta,
    required this.tier,
    required this.wins,
    required this.losses,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map, String uid) =>
      LeaderboardEntry(
        uid: uid,
        username: map['username'] ?? '',
        rank: map['rank'] ?? 0,
        points: map['seasonPoints'] ?? 0,
        pointsDelta: map['pointsDelta'] ?? 0,
        tier: RankTierExt.fromPoints(map['seasonPoints'] ?? 0),
        wins: map['wins'] ?? 0,
        losses: map['losses'] ?? 0,
      );
}

// ── 1v1 CHALLENGE ──
enum ChallengeStatus { pending, picking, active, complete }

class Challenge {
  final String id;
  final String challengerUID, challengerUsername;
  final String opponentUID, opponentUsername;
  final String opponentContact; // email or phone used to find them
  final String duration; // '1day' or '1week'
  final int rosterSize; // 3, 5, or 11
  ChallengeStatus status;
  final DateTime createdAt;
  DateTime? startDate;
  List<Map<String, dynamic>> challengerPicks;
  List<Map<String, dynamic>> opponentPicks;
  double challengerValue, opponentValue;
  double challengerCost, opponentCost;
  String? winnerId;

  Challenge({
    required this.id,
    required this.challengerUID,
    required this.challengerUsername,
    required this.opponentUID,
    required this.opponentUsername,
    this.opponentContact = '',
    required this.duration,
    required this.rosterSize,
    required this.status,
    required this.createdAt,
    this.startDate,
    this.challengerPicks = const [],
    this.opponentPicks = const [],
    this.challengerValue = 0,
    this.opponentValue = 0,
    this.challengerCost = 0,
    this.opponentCost = 0,
    this.winnerId,
  });

  bool get isSectorMode => rosterSize == 11;
  String get durationLabel => duration == '1day' ? '1 Day' : '1 Week';
  bool get isComplete => status == ChallengeStatus.complete;

  double pctChangeFor(String uid) {
    final cost = uid == challengerUID ? challengerCost : opponentCost;
    final value = uid == challengerUID ? challengerValue : opponentValue;
    if (cost <= 0) return 0;
    return ((value - cost) / cost) * 100;
  }

  double valueFor(String uid) =>
      uid == challengerUID ? challengerValue : opponentValue;

  String opponentOf(String uid) =>
      uid == challengerUID ? opponentUID : challengerUID;

  String opponentNameOf(String uid) =>
      uid == challengerUID ? opponentUsername : challengerUsername;

  factory Challenge.fromMap(Map<String, dynamic> map, String id) => Challenge(
        id: id,
        challengerUID: map['challengerUID'] ?? '',
        challengerUsername: map['challengerUsername'] ?? '',
        opponentUID: map['opponentUID'] ?? '',
        opponentUsername: map['opponentUsername'] ?? '',
        opponentContact: map['opponentContact'] ?? '',
        duration: map['duration'] ?? '1week',
        rosterSize: map['rosterSize'] ?? 5,
        status: ChallengeStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => ChallengeStatus.pending,
        ),
        createdAt: (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
        startDate: map['startDate'] != null
            ? (map['startDate'] is String
                ? DateTime.tryParse(map['startDate'])
                : (map['startDate'] as dynamic).toDate())
            : null,
        challengerPicks:
            List<Map<String, dynamic>>.from(map['challengerPicks'] ?? []),
        opponentPicks:
            List<Map<String, dynamic>>.from(map['opponentPicks'] ?? []),
        challengerValue: (map['challengerValue'] ?? 0).toDouble(),
        opponentValue: (map['opponentValue'] ?? 0).toDouble(),
        challengerCost: (map['challengerCost'] ?? 0).toDouble(),
        opponentCost: (map['opponentCost'] ?? 0).toDouble(),
        winnerId: map['winnerId'],
      );

  Map<String, dynamic> toMap() => {
        'challengerUID': challengerUID,
        'challengerUsername': challengerUsername,
        'opponentUID': opponentUID,
        'opponentUsername': opponentUsername,
        'opponentContact': opponentContact,
        'duration': duration,
        'rosterSize': rosterSize,
        'status': status.name,
        'createdAt': createdAt,
        'startDate': startDate,
        'challengerPicks': challengerPicks,
        'opponentPicks': opponentPicks,
        'challengerValue': challengerValue,
        'opponentValue': opponentValue,
        'challengerCost': challengerCost,
        'opponentCost': opponentCost,
        'winnerId': winnerId,
      };
}

// ── MATCHMAKING REQUEST ──
class MatchmakingRequest {
  final String uid, username;
  final RankTier tier;
  final DateTime createdAt;
  String status;

  MatchmakingRequest({
    required this.uid,
    required this.username,
    required this.tier,
    required this.createdAt,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'username': username,
        'tier': tier.name,
        'createdAt': createdAt,
        'status': status,
      };
}
