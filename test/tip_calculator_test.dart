import 'package:flutter_test/flutter_test.dart';
import 'package:bartender_tip_out/models/shift_totals.dart';
import 'package:bartender_tip_out/services/tip_calculator.dart';

void main() {
  group('TipCalculator', () {
    group('calculateBarbackCut', () {
      test('calculates flat amount barback cut', () {
        final shiftTotals = ShiftTotals(
          creditCardTips: 800.0,
          serviceChargeTips: 100.0,
        );

        final result = TipCalculator.calculateBarbackCut(
          totals: shiftTotals,
          mode: BarbackMode.flatAmount,
          value: 100.0,
        );
        expect(result, 100.0);
      });

      test('calculates percentage of tips barback cut', () {
        final shiftTotals = ShiftTotals(
          creditCardTips: 800.0,
          serviceChargeTips: 100.0,
        );

        final result = TipCalculator.calculateBarbackCut(
          totals: shiftTotals,
          mode: BarbackMode.percentageOfTips,
          value: 10.0,
        );
        expect(result, 90.0); // 10% of 900
      });

      test('calculates percentage of sales barback cut', () {
        final shiftTotals = ShiftTotals(
          creditCardTips: 800.0,
          serviceChargeTips: 100.0,
          sales: 5000.0,
        );

        final result = TipCalculator.calculateBarbackCut(
          totals: shiftTotals,
          mode: BarbackMode.percentageOfSales,
          value: 2.0,
        );
        expect(result, 100.0); // 2% of 5000
      });
    });


    group('barbackLineItem', () {
      test('calculates barback line item: X = BB / N', () {
        // 3 bartenders, $90 total barback cut
        // X = 90 / 3 = 30
        final result = TipCalculator.barbackLineItem(
          barbackCut: 90.0,
          bartenderCount: 3,
        );
        expect(result, 30.0);
      });

      test('calculates barback line item for 2 bartenders', () {
        // 2 bartenders, $100 total barback cut
        // X = 100 / 2 = 50
        final result = TipCalculator.barbackLineItem(
          barbackCut: 100.0,
          bartenderCount: 2,
        );
        expect(result, 50.0);
      });

      test('handles zero bartender count', () {
        final result = TipCalculator.barbackLineItem(
          barbackCut: 90.0,
          bartenderCount: 0,
        );
        expect(result, 0.0);
      });
    });

    group('barbackDeductionPerBartender', () {
      test('calculates per-bartender barback deduction: X / N', () {
        // 3 bartenders, $90 total barback cut
        // X = 90 / 3 = 30
        // Deduction per bartender = 30 / 3 = 10
        final result = TipCalculator.barbackDeductionPerBartender(
          barbackCut: 90.0,
          bartenderCount: 3,
        );
        expect(result, 10.0);
      });

      test('calculates per-bartender barback deduction for 2 bartenders', () {
        // 2 bartenders, $100 total barback cut
        // X = 100 / 2 = 50
        // Deduction per bartender = 50 / 2 = 25
        final result = TipCalculator.barbackDeductionPerBartender(
          barbackCut: 100.0,
          bartenderCount: 2,
        );
        expect(result, 25.0);
      });

      test('handles zero bartender count', () {
        final result = TipCalculator.barbackDeductionPerBartender(
          barbackCut: 90.0,
          bartenderCount: 0,
        );
        expect(result, 0.0);
      });
    });

    group('splitDeductionProportionally', () {
      test('splits deduction proportionally by CC/SC ratio', () {
        // $11.11 deduction, CC = $800, SC = $200, total = $1000
        // CC portion = 11.11 * 800/1000 = 8.888 -> 8.89
        // SC portion = 11.11 - 8.89 = 2.22
        final result = TipCalculator.splitDeductionProportionally(
          deduction: 11.11,
          creditCardTips: 800.0,
          serviceChargeTips: 200.0,
        );
        expect(result['cc'], 8.89);
        expect(result['sc'], 2.22);
        // The split must sum exactly to the deduction
        expect(result['cc']! + result['sc']!, closeTo(11.11, 0.001));
      });

      test('splits barback line item proportionally', () {
        // $33.33 barback line, CC = $800, SC = $200, total = $1000
        // CC portion = 33.33 * 800/1000 = 26.664 -> 26.66
        // SC portion = 33.33 - 26.66 = 6.67
        final result = TipCalculator.splitDeductionProportionally(
          deduction: 33.33,
          creditCardTips: 800.0,
          serviceChargeTips: 200.0,
        );
        expect(result['cc'], 26.66);
        expect(result['sc'], 6.67);
        // The split must sum exactly to the deduction
        expect(result['cc']! + result['sc']!, closeTo(33.33, 0.001));
      });

      test('handles zero total tips', () {
        final result = TipCalculator.splitDeductionProportionally(
          deduction: 10.0,
          creditCardTips: 0.0,
          serviceChargeTips: 0.0,
        );
        expect(result['cc'], 0.0);
        expect(result['sc'], 0.0);
      });

      test('handles all tips in one pool', () {
        // All tips are CC, so the entire deduction goes to CC
        final result = TipCalculator.splitDeductionProportionally(
          deduction: 10.0,
          creditCardTips: 100.0,
          serviceChargeTips: 0.0,
        );
        expect(result['cc'], 10.0);
        expect(result['sc'], 0.0);
      });
    });

    group('roundToCents', () {
      test('rounds to nearest cent', () {
        expect(TipCalculator.roundToCents(33.333), 33.33);
        expect(TipCalculator.roundToCents(33.335), 33.34);
        expect(TipCalculator.roundToCents(100.0), 100.0);
      });
    });

    group('splitPoolsSeparately', () {
      test('adds rounding remainder to specified person', () {
        final result = TipCalculator.splitPoolsSeparately(
          netPools: {'cc': 1000.0, 'sc': 0.0},
          bartenderNames: ['You', 'Bob', 'Carol'],
          equalSplit: true,
          hours: {},
          remainderTo: 'You',
        );

        // 1000 / 3 = 333.33 each, remainder 0.01 goes to 'You'
        expect(result['You']!['cc'], 333.34);
        expect(result['Bob']!['cc'], 333.33);
        expect(result['Carol']!['cc'], 333.33);
      });

      test('does not add remainder when remainderTo is null', () {
        final result = TipCalculator.splitPoolsSeparately(
          netPools: {'cc': 1000.0, 'sc': 0.0},
          bartenderNames: ['You', 'Bob', 'Carol'],
          equalSplit: true,
          hours: {},
        );

        // 1000 / 3 = 333.33 each, remainder 0.01 is not added
        expect(result['You']!['cc'], 333.33);
        expect(result['Bob']!['cc'], 333.33);
        expect(result['Carol']!['cc'], 333.33);
      });
    });

    group('equalSplit', () {
      test('splits pool equally', () {
        expect(TipCalculator.equalSplit(900.0, 3), 300.0);
      });

      test('splits pool to the penny', () {
        // 100.00 / 3 = 33.333... -> rounds to 33.33
        expect(TipCalculator.equalSplit(100.0, 3), 33.33);
      });

      test('handles zero count', () {
        expect(TipCalculator.equalSplit(900.0, 0), 0.0);
      });
    });

    group('hourlySplit', () {
      test('splits pool proportionally by hours', () {
        final result = TipCalculator.hourlySplit(
          pool: 900.0,
          personHours: 8.0,
          totalHours: 12.0,
        );
        expect(result, 600.0);
      });

      test('handles zero total hours', () {
        final result = TipCalculator.hourlySplit(
          pool: 900.0,
          personHours: 8.0,
          totalHours: 0.0,
        );
        expect(result, 0.0);
      });
    });

    group('calculateShift', () {
      final totals = ShiftTotals(
        creditCardTips: 800.0,
        serviceChargeTips: 200.0,
        sales: 5000.0,
      );

      test('distributes every cent of the pool', () {
        final result = TipCalculator.calculateShift(
          totals: totals,
          bartenderNames: ['You', 'Bob', 'Carol'],
          barbackNames: ['Dave'],
          userName: 'You',
          isSolo: false,
          barbackCut: 90.0,
          equalSplit: true,
        );

        expect(result.totalDistributed, closeTo(1000.0, 0.005));
        expect(result.hasNegativeLines, isFalse);
      });

      test('splits the barback cut across multiple barbacks', () {
        final result = TipCalculator.calculateShift(
          totals: totals,
          bartenderNames: ['You', 'Bob'],
          barbackNames: ['Dave', 'Erin'],
          userName: 'You',
          isSolo: false,
          barbackCut: 100.0,
          equalSplit: true,
        );

        // The barback pool is X = BB / N = 100 / 2 = $50, shared by the
        // two barbacks. Previously each barback was paid the full X,
        // which over-distributed the pool whenever more than one worked.
        final dave = result.barbacks['Dave']!.values.reduce((a, b) => a + b);
        final erin = result.barbacks['Erin']!.values.reduce((a, b) => a + b);
        expect(dave, closeTo(25.0, 0.01));
        expect(erin, closeTo(25.0, 0.01));
        expect(result.totalDistributed, closeTo(1000.0, 0.005));
      });

      test('uses the real user name on a solo shift', () {
        final result = TipCalculator.calculateShift(
          totals: totals,
          bartenderNames: ['Michael'],
          barbackNames: const [],
          userName: 'Michael',
          isSolo: true,
        );

        // The solo path used to hard-code the label 'You'.
        expect(result.bartenders.keys, contains('Michael'));
        expect(result.bartenders['Michael']!['cc'], 800.0);
        expect(result.bartenders['Michael']!['sc'], 200.0);
      });

      test('flags negative lines when the barback cut exceeds tips', () {
        final result = TipCalculator.calculateShift(
          totals: totals,
          bartenderNames: ['You', 'Bob'],
          barbackNames: ['Dave'],
          userName: 'You',
          isSolo: false,
          // X = 6000 / 2 = 3000, so each bartender gives up $1500 from a
          // $500 share — deep into the negative.
          barbackCut: 6000.0,
          equalSplit: true,
        );

        expect(result.hasNegativeLines, isTrue);
      });

      test('splits by hours when equalSplit is false', () {
        final result = TipCalculator.calculateShift(
          totals: ShiftTotals(creditCardTips: 900.0, serviceChargeTips: 0.0),
          bartenderNames: ['You', 'Bob'],
          barbackNames: const [],
          userName: 'You',
          isSolo: false,
          equalSplit: false,
          hours: {'You': 8.0, 'Bob': 4.0},
        );

        expect(result.bartenders['You']!['cc'], closeTo(600.0, 0.01));
        expect(result.bartenders['Bob']!['cc'], closeTo(300.0, 0.01));
      });
    });
  });
}
