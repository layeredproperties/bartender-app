import 'package:tip_out/models/money.dart';
import 'package:tip_out/models/pools.dart';
import 'package:tip_out/models/shift_totals.dart';
import 'package:tip_out/services/tip_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressions for bugs found in review. Each test names the behaviour
/// that used to be wrong.
void main() {
  _barbackModeSemantics();
  _proportionalBarbackDeduction();

  group('duplicate names', () {
    test('calculateShift rejects a repeated bartender name', () {
      // Two bartenders called Mike used to collapse into one map entry:
      // the pool was split three ways, only two lines were written, and
      // the orphaned share was handed to whoever absorbed the rounding
      // remainder. $900 came out as You $600 / Mike $300.
      expect(
        () => TipCalculator.calculateShift(
          totals: const ShiftTotals(creditCardTips: 900, serviceChargeTips: 0),
          bartenderNames: ['You', 'Mike', 'Mike'],
          barbackNames: const [],
          userName: 'You',
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Mike'),
        )),
      );
    });

    test('calculateShift rejects a repeated barback name', () {
      expect(
        () => TipCalculator.calculateShift(
          totals: const ShiftTotals(creditCardTips: 900, serviceChargeTips: 0),
          bartenderNames: const ['You'],
          barbackNames: ['Barry', 'Barry'],
          userName: 'You',
          barbackCut: 50,
        ),
        throwsArgumentError,
      );
    });

    test('a name shared between a bartender and a barback is fine', () {
      // Only collisions within a single group collapse a map entry.
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 900, serviceChargeTips: 0),
        bartenderNames: const ['You'],
        barbackNames: const ['You'],
        userName: 'You',
        barbackCut: 90,
      );
      expect(result.totalDistributed, 900.0);
    });
  });

  group('penny reconciliation', () {
    test('distributes the pool exactly, with no floating point drift', () {
      // Used to come back as 1000.0000000000001.
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 800, serviceChargeTips: 200),
        bartenderNames: const ['You', 'Bob', 'Carol'],
        barbackNames: const [],
        userName: 'You',
      );

      expect(result.totalDistributed, 1000.0);
    });

    test('stays exact with barbacks in the mix', () {
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 800, serviceChargeTips: 200),
        bartenderNames: const ['You', 'Bob', 'Carol'],
        barbackNames: const ['Dave'],
        userName: 'You',
        barbackCut: 100,
      );

      expect(result.totalDistributed, 1000.0);
      // The worked example in the TipCalculator docstring.
      expect(result.bartenders['You'], const Pools(cc: 257.77, sc: 64.44));
      expect(result.bartenders['Bob'], const Pools(cc: 257.78, sc: 64.45));
      expect(result.barbacks['Dave'], const Pools(cc: 26.66, sc: 6.67));
    });

    test('a service-charge-only shift never grows a credit card line', () {
      // The remainder was unconditionally added to `cc`, inventing a
      // credit card amount on a shift that had none.
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 0, serviceChargeTips: 1000),
        bartenderNames: const ['You', 'Bob', 'Carol'],
        barbackNames: const ['Dave'],
        userName: 'You',
        barbackCut: 100,
      );

      for (final pools in result.bartenders.values) {
        expect(pools.cc, 0.0);
      }
      expect(result.barbacks['Dave']!.cc, 0.0);
      expect(result.totalDistributed, 1000.0);
    });

    test('a credit-card-only shift never grows a service charge line', () {
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 1000, serviceChargeTips: 0),
        bartenderNames: const ['You', 'Bob', 'Carol'],
        barbackNames: const ['Dave'],
        userName: 'You',
        barbackCut: 100,
      );

      for (final pools in result.bartenders.values) {
        expect(pools.sc, 0.0);
      }
      expect(result.totalDistributed, 1000.0);
    });
  });

  group('solo shifts', () {
    test('rounds the solo payout to the cent', () {
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(
          creditCardTips: 100.005,
          serviceChargeTips: 20.001,
        ),
        bartenderNames: const ['Michael'],
        barbackNames: const [],
        userName: 'Michael',
        isSolo: true,
      );

      expect(result.bartenders['Michael'], const Pools(cc: 100.01, sc: 20.0));
    });
  });

  group('no bartenders', () {
    test('distributes nothing rather than inventing a split', () {
      // The team screen blocks this; the calculator documents it.
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 500, serviceChargeTips: 100),
        bartenderNames: const [],
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 100,
      );

      expect(result.bartenders, isEmpty);
      expect(result.totalDistributed, 0.0);
    });
  });

  group('Pools', () {
    test('total is free of float noise', () {
      expect(const Pools(cc: 257.77, sc: 64.44).total, 322.21);
    });

    test('addRemainder targets the pool that is in play', () {
      expect(const Pools(cc: 10, sc: 5).addRemainder(0.01).cc, 10.01);
      expect(const Pools(cc: 0, sc: 5).addRemainder(0.01).sc, 5.01);
      expect(const Pools(cc: 0, sc: 0).addRemainder(0.01).cc, 0.01);
    });

    test('equality is by value', () {
      expect(const Pools(cc: 1, sc: 2), const Pools(cc: 1, sc: 2));
      expect(const Pools(cc: 1, sc: 2), isNot(const Pools(cc: 2, sc: 1)));
    });
  });
}

/// The barback deduction follows the same weights as the payout, so an
/// hourly shift charges each bartender in proportion to the hours they
/// worked. It used to be a flat X/N regardless of hours, which made a
/// short shift subsidise a long one.
void _proportionalBarbackDeduction() {
  group('barback deduction on an hourly split', () {
    test('charges each bartender in proportion to their hours', () {
      // The worked example in the TipCalculator docstring.
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 1000, serviceChargeTips: 0),
        bartenderNames: const ['You', 'Bob'],
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 200,
        equalSplit: false,
        hours: const {'You': 10, 'Bob': 2},
      );

      // You worked 10 of 12 hours and covers 10/12 of the $100 pool.
      expect(result.bartenders['You'], const Pools(cc: 750.0));
      // Bob worked 2 of 12 hours: $16.67, not the old flat $50.
      expect(result.bartenders['Bob'], const Pools(cc: 150.0));
      expect(result.barbacks['Barry'], const Pools(cc: 100.0));
      expect(result.totalDistributed, 1000.0);
    });

    test('the bartenders collectively give up exactly the barback pool', () {
      const gross = {'You': 833.33, 'Bob': 166.67};
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 1000, serviceChargeTips: 0),
        bartenderNames: const ['You', 'Bob'],
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 200,
        equalSplit: false,
        hours: const {'You': 10, 'Bob': 2},
      );

      final givenUp = gross.entries.fold<double>(
        0,
        (sum, e) => sum + e.value - result.bartenders[e.key]!.total,
      );
      expect(roundToCents(givenUp), result.totalBarbackPayout);
    });

    test('an equal split still deducts a flat X/N', () {
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 1000, serviceChargeTips: 0),
        bartenderNames: const ['You', 'Bob'],
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 200,
      );

      // X = 100, each share is 1/2, so each gives up $50.
      expect(result.bartenders['You'], const Pools(cc: 450.0));
      expect(result.bartenders['Bob'], const Pools(cc: 450.0));
      expect(result.barbacks['Barry'], const Pools(cc: 100.0));
      expect(result.totalDistributed, 1000.0);
    });

    test('uneven hours still reconcile to the exact total', () {
      // Weights that do not divide cleanly, so rounding has to be
      // absorbed somewhere.
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 800, serviceChargeTips: 200),
        bartenderNames: const ['You', 'Bob', 'Carol'],
        barbackNames: const ['Dave'],
        userName: 'You',
        barbackCut: 100,
        equalSplit: false,
        hours: const {'You': 7.5, 'Bob': 3.25, 'Carol': 1.75},
      );

      expect(result.totalDistributed, 1000.0);
      expect(result.hasNegativeLines, isFalse);
    });

    test('falls back to an equal deduction when hours are unusable', () {
      final result = TipCalculator.calculateShift(
        totals: const ShiftTotals(creditCardTips: 1000, serviceChargeTips: 0),
        bartenderNames: const ['You', 'Bob'],
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 200,
        equalSplit: false,
        hours: const {},
      );

      expect(result.totalDistributed, 1000.0);
    });
  });

  group('splitWeights', () {
    test('equal split weights sum to one', () {
      final weights = TipCalculator.splitWeights(
        bartenderNames: const ['You', 'Bob', 'Carol'],
        equalSplit: true,
        hours: const {},
      );

      expect(weights.values.reduce((a, b) => a + b), closeTo(1.0, 1e-12));
      expect(weights['You'], closeTo(1 / 3, 1e-12));
    });

    test('hourly weights track hours', () {
      final weights = TipCalculator.splitWeights(
        bartenderNames: const ['You', 'Bob'],
        equalSplit: false,
        hours: const {'You': 10, 'Bob': 2},
      );

      expect(weights['You'], closeTo(10 / 12, 1e-12));
      expect(weights['Bob'], closeTo(2 / 12, 1e-12));
    });

    test('zero total hours falls back to an equal split', () {
      final weights = TipCalculator.splitWeights(
        bartenderNames: const ['You', 'Bob'],
        equalSplit: false,
        hours: const {'You': 0, 'Bob': 0},
      );

      expect(weights['You'], 0.5);
      expect(weights['Bob'], 0.5);
    });
  });
}

/// The barback tip-out means different things per mode, because this app
/// only ever sees one bartender's numbers — the copies running on
/// coworkers' phones can't talk to each other.
void _barbackModeSemantics() {
  const totals = ShiftTotals(
    creditCardTips: 800,
    serviceChargeTips: 200,
    sales: 5000,
  );
  const three = ['You', 'Bob', 'Carol'];

  group('barback line item by mode', () {
    test('a flat amount is the group payout, so it is split', () {
      // The user typed what the group owes — the one figure the app
      // cannot derive for itself. $90 across 3 bartenders is $30 each.
      expect(
        TipCalculator.barbackLineItem(
          barbackCut: 90,
          bartenderCount: 3,
          mode: BarbackMode.flatAmount,
        ),
        30.0,
      );
    });

    test('a percentage of tips is already personal, so it is not split', () {
      // 20% of this bartender's own $1000 in tips. Splitting it three
      // ways reported $66.67 where $200 was owed.
      expect(
        TipCalculator.barbackLineItem(
          barbackCut: 200,
          bartenderCount: 3,
          mode: BarbackMode.percentageOfTips,
        ),
        200.0,
      );
    });

    test('a percentage of sales is already personal too', () {
      expect(
        TipCalculator.barbackLineItem(
          barbackCut: 250,
          bartenderCount: 3,
          mode: BarbackMode.percentageOfSales,
        ),
        250.0,
      );
    });

    test('bartender count cannot affect a percentage', () {
      for (final n in [1, 2, 5, 9]) {
        expect(
          TipCalculator.barbackLineItem(
            barbackCut: 175,
            bartenderCount: n,
            mode: BarbackMode.percentageOfTips,
          ),
          175.0,
          reason: 'with $n bartenders',
        );
      }
    });
  });

  group('calculateShift honours the mode', () {
    test('flat: the reported figure is the group amount over N', () {
      final result = TipCalculator.calculateShift(
        totals: totals,
        bartenderNames: three,
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 90,
        barbackMode: BarbackMode.flatAmount,
      );
      expect(result.barbacks['Barry']!.total, 30.0);
      expect(result.totalDistributed, 1000.0);
    });

    test('percentage: the reported figure is the full amount', () {
      final result = TipCalculator.calculateShift(
        totals: totals,
        bartenderNames: three,
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 200, // 20% of this bartender's $1000
        barbackMode: BarbackMode.percentageOfTips,
      );
      expect(result.barbacks['Barry']!.total, 200.0);
      expect(result.totalDistributed, 1000.0);
    });

    test('percentage of sales reports in full as well', () {
      final result = TipCalculator.calculateShift(
        totals: totals,
        bartenderNames: three,
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 250, // 5% of $5000 in sales
        barbackMode: BarbackMode.percentageOfSales,
      );
      expect(result.barbacks['Barry']!.total, 250.0);
      expect(result.totalDistributed, 1000.0);
    });

    test('defaults to flat, so existing callers are unchanged', () {
      final result = TipCalculator.calculateShift(
        totals: totals,
        bartenderNames: three,
        barbackNames: const ['Barry'],
        userName: 'You',
        barbackCut: 90,
      );
      expect(result.barbacks['Barry']!.total, 30.0);
    });
  });
}
