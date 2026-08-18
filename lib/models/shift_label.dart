/// How a shift is titled wherever it's reported — the copy text, the
/// share sheet, and the tip log.
library;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `Tue, Aug 18 2026`.
///
/// Written by hand rather than pulling in `intl`: the app needs one
/// format in one language, and a date package is a lot of weight — plus
/// locale data — for that.
String formatShiftDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]}, ${_months[date.month - 1]} '
    '${date.day} ${date.year}';

/// The shift's headline: the date, plus where it was worked when the
/// user picked somewhere.
///
/// Location is optional, so this degrades to just the date rather than
/// leaving a dangling separator.
String shiftLabel(DateTime date, String? location) {
  final where = location?.trim() ?? '';
  final when = formatShiftDate(date);
  return where.isEmpty ? when : '$when — $where';
}
