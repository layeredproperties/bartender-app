import 'package:tip_out/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAmount', () {
    test('reads plain numbers', () {
      expect(parseAmount('450'), 450.0);
      expect(parseAmount('75.50'), 75.5);
      expect(parseAmount('  120.25  '), 120.25);
    });

    test('empty input is zero, not an error', () {
      expect(parseAmount(''), 0);
      expect(parseAmount('   '), 0);
    });

    test('strips currency symbols and thousands separators', () {
      // The old `double.tryParse(text) ?? 0.0` turned each of these into
      // a silent $0.00 shift.
      expect(parseAmount(r'$450'), 450.0);
      expect(parseAmount('1,200.50'), 1200.5);
      expect(parseAmount(r'$1,200.50'), 1200.5);
      expect(parseAmount('1,200'), 1200.0);
      expect(parseAmount('12,345,678'), 12345678.0);
    });

    test('treats a short trailing comma group as a decimal separator', () {
      expect(parseAmount('1,50'), 1.5);
      expect(parseAmount('1,5'), 1.5);
    });

    test('handles non-breaking space from pasted text', () {
      expect(parseAmount('1 200.50'), 1200.5);
    });

    test('returns null for text that is not a number', () {
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('12.34.56'), isNull);
      expect(parseAmount('--5'), isNull);
    });
  });

  group('roundToCents', () {
    test('rounds to the nearest cent', () {
      expect(roundToCents(33.333), 33.33);
      expect(roundToCents(33.335), 33.34);
      expect(roundToCents(1000.0000000000001), 1000.0);
    });
  });

  group('formatMoney', () {
    test('formats with a dollar sign and two decimals', () {
      expect(formatMoney(0), r'$0.00');
      expect(formatMoney(1234.5), r'$1234.50');
      expect(formatMoney(-8.891), r'$-8.89');
    });
  });
}
