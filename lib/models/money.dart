/// Money parsing, rounding, and formatting shared by the calculator,
/// the CSV service, and the screens.
library;

/// Round to the nearest cent (2 decimal places).
///
/// Every value that reaches the UI or the CSV log goes through this, so
/// accumulated floating-point noise never escapes the calculator.
double roundToCents(double value) => (value * 100).roundToDouble() / 100;

/// Format a value as a display string with a leading `$`.
String formatMoney(double value) => '\$${value.toStringAsFixed(2)}';

/// Format a value as a bare CSV field (no currency symbol).
String formatAmount(double value) => value.toStringAsFixed(2);

/// Matches a currency symbol, whitespace (including non-breaking space,
/// which iOS/macOS insert when pasting), and thousands separators.
final _noise = RegExp(r'[\s  $£€]');

/// Parse a user-entered amount, tolerating the ways people actually type
/// money: `$1,200.50`, `1 200,50`, `450`, ` 75.50 `.
///
/// Returns `null` when the text isn't a number at all, so callers can
/// show an error instead of silently treating it as `0` — the old
/// `double.tryParse(text) ?? 0.0` turned a mistyped `1,200.50` into a
/// $0.00 shift with no warning.
///
/// An empty or whitespace-only string parses to `0`, which is what the
/// optional fields (net sales, service charge) expect.
double? parseAmount(String raw) {
  var text = raw.replaceAll(_noise, '');
  if (text.isEmpty) return 0;

  // Disambiguate the comma: `1,200` is a thousands separator, `1,50` is
  // a decimal separator. A comma followed by exactly three digits at the
  // end of the number is thousands; anything else is a decimal point.
  if (!text.contains('.')) {
    final decimalComma = RegExp(r'^-?\d+,\d{1,2}$');
    text = decimalComma.hasMatch(text)
        ? text.replaceFirst(',', '.')
        : text.replaceAll(',', '');
  } else {
    text = text.replaceAll(',', '');
  }

  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return value;
}
