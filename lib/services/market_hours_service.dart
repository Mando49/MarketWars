// ─────────────────────────────────────────
// MARKET HOURS SERVICE
// Centralized U.S. market calendar for
// Market Wars. Used by match scoring,
// matchmaking, league scoring, and UI
// (market status pill).
// ─────────────────────────────────────────

/// All times are U.S. Eastern (ET).
/// Pre-market:  4:00 AM – 9:30 AM ET
/// Regular:     9:30 AM – 4:00 PM ET
/// After-hours: 4:00 PM – 8:00 PM ET
///
/// Match windows use pre-market open (4:00 AM ET)
/// as the start and regular close (4:00 PM ET) as the end.
class MarketHoursService {
  // ── Constants ──────────────────────────

  /// Pre-market opens at 4:00 AM ET.
  static const int preMarketOpenHour = 4;
  static const int preMarketOpenMinute = 0;

  /// Regular session opens at 9:30 AM ET.
  static const int regularOpenHour = 9;
  static const int regularOpenMinute = 30;

  /// Regular session closes at 4:00 PM ET.
  static const int regularCloseHour = 16;
  static const int regularCloseMinute = 0;

  /// After-hours ends at 8:00 PM ET.
  static const int afterHoursCloseHour = 20;
  static const int afterHoursCloseMinute = 0;

  // ── ET offset ──────────────────────────

  /// Returns the current UTC offset for U.S. Eastern Time.
  /// EDT (March second Sunday – November first Sunday): UTC-4
  /// EST (rest of year): UTC-5
  static Duration get _etOffset {
    final now = DateTime.now().toUtc();
    return _isEDT(now) ? const Duration(hours: -4) : const Duration(hours: -5);
  }

  /// Convert a UTC DateTime to Eastern Time.
  static DateTime toET(DateTime utc) => utc.toUtc().add(_etOffset);

  /// Convert an Eastern Time DateTime to UTC.
  static DateTime fromET(DateTime et) =>
      DateTime.utc(et.year, et.month, et.day, et.hour, et.minute, et.second)
          .subtract(_etOffset);

  /// Check if a UTC date falls within U.S. Eastern Daylight Time.
  static bool _isEDT(DateTime utc) {
    final year = utc.year;

    // Second Sunday of March at 2:00 AM ET → clocks spring forward
    final marchFirst = DateTime.utc(year, 3, 1);
    final marchSecondSunday =
        marchFirst.add(Duration(days: (7 - marchFirst.weekday) % 7 + 7));
    final edtStart =
        marchSecondSunday.add(const Duration(hours: 7)); // 2 AM EST = 7 AM UTC

    // First Sunday of November at 2:00 AM ET → clocks fall back
    final novFirst = DateTime.utc(year, 11, 1);
    final novFirstSunday =
        novFirst.add(Duration(days: (7 - novFirst.weekday) % 7));
    final edtEnd =
        novFirstSunday.add(const Duration(hours: 6)); // 2 AM EDT = 6 AM UTC

    return utc.isAfter(edtStart) && utc.isBefore(edtEnd);
  }

  // ── Market holidays ────────────────────

  /// Returns all market-closed holidays for a given year.
  /// Source: NYSE/NASDAQ observed holiday schedule.
  static List<DateTime> _holidaysForYear(int year) {
    final holidays = <DateTime>[];

    // New Year's Day — Jan 1 (or observed)
    holidays.add(_observedHoliday(DateTime(year, 1, 1)));

    // MLK Day — third Monday of January
    holidays.add(_nthWeekday(year, 1, DateTime.monday, 3));

    // Presidents' Day — third Monday of February
    holidays.add(_nthWeekday(year, 2, DateTime.monday, 3));

    // Good Friday — varies (2 days before Easter Sunday)
    holidays.add(_goodFriday(year));

    // Memorial Day — last Monday of May
    holidays.add(_lastWeekday(year, 5, DateTime.monday));

    // Juneteenth — June 19 (or observed)
    holidays.add(_observedHoliday(DateTime(year, 6, 19)));

    // Independence Day — July 4 (or observed)
    holidays.add(_observedHoliday(DateTime(year, 7, 4)));

    // Labor Day — first Monday of September
    holidays.add(_nthWeekday(year, 9, DateTime.monday, 1));

    // Thanksgiving — fourth Thursday of November
    holidays.add(_nthWeekday(year, 11, DateTime.thursday, 4));

    // Christmas — Dec 25 (or observed)
    holidays.add(_observedHoliday(DateTime(year, 12, 25)));

    return holidays;
  }

  /// Early close days (1:00 PM ET close).
  /// Typically: day before Independence Day, day after Thanksgiving,
  /// Christmas Eve (if weekday).
  static List<DateTime> _earlyCloseDays(int year) {
    final days = <DateTime>[];

    // Day before July 4 (if July 3 is a weekday and not itself a holiday)
    final july3 = DateTime(year, 7, 3);
    if (july3.weekday >= DateTime.monday && july3.weekday <= DateTime.friday) {
      days.add(july3);
    }

    // Day after Thanksgiving (Black Friday)
    final thanksgiving = _nthWeekday(year, 11, DateTime.thursday, 4);
    days.add(thanksgiving.add(const Duration(days: 1)));

    // Christmas Eve — Dec 24 if weekday
    final dec24 = DateTime(year, 12, 24);
    if (dec24.weekday >= DateTime.monday && dec24.weekday <= DateTime.friday) {
      days.add(dec24);
    }

    return days;
  }

  // ── Helper: nth weekday of month ───────

  static DateTime _nthWeekday(int year, int month, int weekday, int n) {
    var d = DateTime(year, month, 1);
    int count = 0;
    while (true) {
      if (d.weekday == weekday) {
        count++;
        if (count == n) return d;
      }
      d = d.add(const Duration(days: 1));
    }
  }

  static DateTime _lastWeekday(int year, int month, int weekday) {
    var d = DateTime(year, month + 1, 0); // last day of month
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  /// If a holiday falls on Saturday, observed Friday.
  /// If it falls on Sunday, observed Monday.
  static DateTime _observedHoliday(DateTime date) {
    if (date.weekday == DateTime.saturday) {
      return date.subtract(const Duration(days: 1));
    }
    if (date.weekday == DateTime.sunday) {
      return date.add(const Duration(days: 1));
    }
    return date;
  }

  /// Compute Good Friday using the Anonymous Gregorian algorithm.
  static DateTime _goodFriday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    final easter = DateTime(year, month, day);
    return easter.subtract(const Duration(days: 2));
  }

  // ── Public API ─────────────────────────

  /// Check if a given date (in ET) is a market holiday.
  static bool isHoliday(DateTime dateET) {
    final holidays = _holidaysForYear(dateET.year);
    return holidays.any((h) =>
        h.year == dateET.year &&
        h.month == dateET.month &&
        h.day == dateET.day);
  }

  /// Check if a given date (in ET) is an early close day (1 PM ET).
  static bool isEarlyClose(DateTime dateET) {
    final days = _earlyCloseDays(dateET.year);
    return days.any((d) =>
        d.year == dateET.year &&
        d.month == dateET.month &&
        d.day == dateET.day);
  }

  /// Check if a given date is a regular trading day (weekday, not a holiday).
  static bool isTradingDay(DateTime dateET) {
    if (dateET.weekday == DateTime.saturday ||
        dateET.weekday == DateTime.sunday) {
      return false;
    }
    return !isHoliday(dateET);
  }

  /// Get the market close hour for a given date (16 or 13 for early close).
  static int closeHourForDate(DateTime dateET) =>
      isEarlyClose(dateET) ? 13 : regularCloseHour;

  // ── Market status (for UI pill) ────────

  /// Returns the current market status string and emoji.
  /// Call with DateTime.now().toUtc() or let it default.
  static MarketStatus currentStatus([DateTime? utcNow]) {
    final now = toET(utcNow ?? DateTime.now().toUtc());

    if (!isTradingDay(now)) {
      return MarketStatus.closed;
    }

    final minutes = now.hour * 60 + now.minute;
    const preOpen = preMarketOpenHour * 60 + preMarketOpenMinute;
    const regOpen = regularOpenHour * 60 + regularOpenMinute;
    final closeHour = closeHourForDate(now);
    final regClose = closeHour * 60;
    const afterClose = afterHoursCloseHour * 60;

    if (minutes >= preOpen && minutes < regOpen) {
      return MarketStatus.preMarket;
    }
    if (minutes >= regOpen && minutes < regClose) {
      return MarketStatus.open;
    }
    if (minutes >= regClose && minutes < afterClose) {
      return MarketStatus.afterHours;
    }
    return MarketStatus.closed;
  }

  // ── Match window calculations ──────────

  /// Given a match start time (UTC) and duration type,
  /// returns the start and end times (UTC) for the match window.
  ///
  /// Daily Duel ('1day'):
  ///   Starts at next pre-market open (4:00 AM ET).
  ///   Ends at that day's market close (4:00 PM ET, or 1:00 PM if early close).
  ///   If already past pre-market open today, starts next trading day.
  ///
  /// Weekly War ('1week'):
  ///   Starts at Monday 4:00 AM ET of the next upcoming trading week.
  ///   Ends at Friday 4:00 PM ET of that same week.
  ///   If it's currently Mon–Thu before pre-market, starts this week's Monday.
  ///   If it's Fri after close or weekend, starts next Monday.
  static MatchWindow calculateMatchWindow({
    required DateTime matchCreatedUtc,
    required String duration,
  }) {
    final createdET = toET(matchCreatedUtc);

    if (duration == '1day') {
      return _dailyWindow(createdET);
    } else {
      return _weeklyWindow(createdET);
    }
  }

  /// Calculate the next Daily Duel window.
  static MatchWindow _dailyWindow(DateTime createdET) {
    var candidate = DateTime(
      createdET.year,
      createdET.month,
      createdET.day,
      preMarketOpenHour,
      preMarketOpenMinute,
    );

    // If we're already past pre-market open today, move to next day
    if (createdET.hour > preMarketOpenHour ||
        (createdET.hour == preMarketOpenHour &&
            createdET.minute >= preMarketOpenMinute)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    // Skip to next trading day if weekend or holiday
    candidate = _nextTradingDay(candidate);

    final closeHour = closeHourForDate(candidate);
    final end = DateTime(
      candidate.year,
      candidate.month,
      candidate.day,
      closeHour,
      0,
    );

    return MatchWindow(
      startUtc: fromET(candidate),
      endUtc: fromET(end),
      startET: candidate,
      endET: end,
    );
  }

  /// Calculate the next Weekly War window.
  static MatchWindow _weeklyWindow(DateTime createdET) {
    // Find the Monday of the target week
    DateTime monday;

    final todayIsWeekday = createdET.weekday >= DateTime.monday &&
        createdET.weekday <= DateTime.friday;
    final beforePreMarket = createdET.hour < preMarketOpenHour;

    if (todayIsWeekday &&
        createdET.weekday == DateTime.monday &&
        beforePreMarket) {
      // It's Monday before pre-market — use this Monday
      monday = DateTime(createdET.year, createdET.month, createdET.day);
    } else if (todayIsWeekday &&
        createdET.weekday < DateTime.friday &&
        beforePreMarket) {
      // Mon–Thu before pre-market — still use this week's Monday
      // Actually, to be fair, start next Monday so both players get a full week
      monday = _nextMonday(createdET);
    } else {
      // Friday after open, or weekend — next Monday
      monday = _nextMonday(createdET);
    }

    // Make sure Monday is a trading day; if Monday is a holiday, use Tuesday
    var start = DateTime(
      monday.year,
      monday.month,
      monday.day,
      preMarketOpenHour,
      preMarketOpenMinute,
    );
    start = _nextTradingDay(start);

    // Friday of that same week
    var friday = monday.add(const Duration(days: 4));
    // If Friday is a holiday, use the last trading day of that week (Thu, Wed, etc.)
    while (!isTradingDay(friday)) {
      friday = friday.subtract(const Duration(days: 1));
    }

    final closeHour = closeHourForDate(friday);
    final end = DateTime(
      friday.year,
      friday.month,
      friday.day,
      closeHour,
      0,
    );

    return MatchWindow(
      startUtc: fromET(start),
      endUtc: fromET(end),
      startET: start,
      endET: end,
    );
  }

  /// Advance a date to the next trading day if it's a weekend or holiday.
  static DateTime _nextTradingDay(DateTime dateET) {
    var d = DateTime(
        dateET.year, dateET.month, dateET.day, dateET.hour, dateET.minute);
    while (!isTradingDay(d)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  /// Get the next Monday on or after a given date.
  static DateTime _nextMonday(DateTime dateET) {
    var d = dateET.add(const Duration(days: 1));
    while (d.weekday != DateTime.monday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }

  // ── League week boundaries ─────────────

  /// Returns the start (Monday 4 AM ET) and end (Friday close ET)
  /// for a given league week number, starting from the league's
  /// season start date.
  ///
  /// [seasonStartUtc] is the UTC timestamp of when the season started.
  /// [weekNumber] is 1-indexed.
  static MatchWindow leagueWeekWindow({
    required DateTime seasonStartUtc,
    required int weekNumber,
  }) {
    final seasonStartET = toET(seasonStartUtc);

    // Find the Monday of the week the season started
    var firstMonday = seasonStartET;
    while (firstMonday.weekday != DateTime.monday) {
      firstMonday = firstMonday.subtract(const Duration(days: 1));
    }

    // Add (weekNumber - 1) weeks
    final targetMonday = firstMonday.add(Duration(days: 7 * (weekNumber - 1)));

    final start = DateTime(
      targetMonday.year,
      targetMonday.month,
      targetMonday.day,
      preMarketOpenHour,
      preMarketOpenMinute,
    );

    var friday = targetMonday.add(const Duration(days: 4));
    while (!isTradingDay(friday)) {
      friday = friday.subtract(const Duration(days: 1));
    }
    final closeHour = closeHourForDate(friday);
    final end = DateTime(
      friday.year,
      friday.month,
      friday.day,
      closeHour,
      0,
    );

    return MatchWindow(
      startUtc: fromET(start),
      endUtc: fromET(end),
      startET: start,
      endET: end,
    );
  }
}

// ── Data classes ─────────────────────────

enum MarketStatus {
  preMarket, // ☀️ Pre-Market
  open, // 🟢 Market Open
  afterHours, // 🌙 After Hours
  closed, // ⛔ Closed
}

extension MarketStatusDisplay on MarketStatus {
  String get label {
    switch (this) {
      case MarketStatus.preMarket:
        return 'Pre-Market';
      case MarketStatus.open:
        return 'Market Open';
      case MarketStatus.afterHours:
        return 'After Hours';
      case MarketStatus.closed:
        return 'Closed';
    }
  }

  String get emoji {
    switch (this) {
      case MarketStatus.preMarket:
        return '☀️';
      case MarketStatus.open:
        return '🟢';
      case MarketStatus.afterHours:
        return '🌙';
      case MarketStatus.closed:
        return '⛔';
    }
  }
}

class MatchWindow {
  final DateTime startUtc;
  final DateTime endUtc;
  final DateTime startET;
  final DateTime endET;

  const MatchWindow({
    required this.startUtc,
    required this.endUtc,
    required this.startET,
    required this.endET,
  });

  /// Human-readable description, e.g. "Mon Mar 16, 4:00 AM – 4:00 PM ET"
  String get description {
    final months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    String fmt(DateTime d) {
      final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      final min = d.minute.toString().padLeft(2, '0');
      return '${days[d.weekday]} ${months[d.month]} ${d.day}, $h:$min $ampm ET';
    }

    return '${fmt(startET)} → ${fmt(endET)}';
  }

  /// Whether the match window has started.
  bool get hasStarted => DateTime.now().toUtc().isAfter(startUtc);

  /// Whether the match window has ended.
  bool get hasEnded => DateTime.now().toUtc().isAfter(endUtc);

  /// Duration remaining until the window ends.
  Duration get remaining => endUtc.difference(DateTime.now().toUtc());
}
