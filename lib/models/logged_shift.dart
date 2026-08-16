/// A shift already saved to the local tip log.
///
/// Used to offer the user a specific shift to redo. Working a double and
/// wanting to fix the second set of numbers should not cost you the
/// first, so replacement is scoped to one of these rather than to a
/// whole date.
class LoggedShift {
  final String dateStr;

  /// As stored in the log, 24-hour `HH:MM`.
  final String timeStr;

  final double creditCardTips;
  final double serviceChargeTips;
  final double sales;
  final double barbackCut;

  /// The exact "Shift Totals" row this shift begins with — the key used
  /// to find it again in `CsvExportService.replaceShift`.
  final String totalsRowLine;

  const LoggedShift({
    required this.dateStr,
    required this.timeStr,
    required this.creditCardTips,
    required this.serviceChargeTips,
    required this.sales,
    required this.barbackCut,
    required this.totalsRowLine,
  });

  double get totalTips => creditCardTips + serviceChargeTips;

  /// `14:05` rendered as `2:05 PM`, for display next to the other
  /// times a bartender reads on a schedule.
  String get displayTime {
    final parts = timeStr.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts.first) : null;
    if (hour == null || hour < 0 || hour > 23) return timeStr;
    final suffix = hour < 12 ? 'AM' : 'PM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${parts[1]} $suffix';
  }
}
