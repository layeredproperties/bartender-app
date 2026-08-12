import '../models/shift_totals.dart';
import '../models/tip_out_result.dart';

enum BarbackMode { flatAmount, percentageOfTips, percentageOfSales }

/// Core tip-out math for the Bartender App.
///
/// ## The Algorithm (locked — do not change without updating tests)
///
/// Given:
///   - `TT` = total tips = CC + SC (credit card tips + service charge tips)
///   - `N`  = number of bartenders
///   - `BB` = total barback tip-out (the amount the barback receives)
///   - `B`  = number of barbacks
///
/// ### Step 1 — Split each pool separately
/// Each pool (CC and SC) is split among the N bartenders, either equally
/// or proportionally by hours. Each pool is split independently so that
/// each pool sums exactly to its total. Any rounding remainder (a penny
/// or two) is added to the user's line (or the first bartender if the
/// user isn't in the pool).
///
/// ### Step 2 — Apply the barback deduction
/// The barback tip-out is NOT deducted from the CC+SC pool. Instead:
///   - `X` = BB / N  — the total barback pool (what each bartender's app
///     shows as the barback's tip-out).
///   - Each bartender's deduction = X / N.
/// Because N bartenders each give up `X / N`, the bartenders collectively
/// give up exactly `X` — which is exactly what the barbacks receive.
/// This deduction is split proportionally between the bartender's CC and
/// SC amounts by the CC/SC ratio, so the displayed numbers are
/// Evention-ready (no separate "Barback Tip-Out" line).
///
/// ### Step 3 — Share the barback pool among the barbacks
/// The barback pool `X` is split proportionally between CC and SC by the
/// CC/SC ratio, then shared equally among the `B` barbacks. With a single
/// barback this reduces to that barback receiving all of `X`. Splitting
/// (rather than giving every barback `X`) is what keeps the books
/// balanced when more than one barback works the shift.
///
/// ### Step 4 — Penny reconciliation
/// All line items (bartenders + barbacks) are summed. If the total
/// differs from TT by a penny, the remainder is added to the barback's
/// line (or the user's line if there's no barback). This guarantees:
///
///     Σ(bartender lines) + Σ(barback lines) = TT exactly
///
/// ### Worked example
/// 3 bartenders (You, Bob, Carol), TT = $1000 (CC = $800, SC = $200),
/// BB = $100, 1 barback.
///
/// Step 1 — Pool split (remainderTo = 'You'):
///   CC: $800/3 = $266.67 each → sum = $800.01, remainder = -$0.01
///       → You gets $266.66
///   SC: $200/3 = $66.67 each → sum = $200.01, remainder = -$0.01
///       → You gets $66.66
///   You = {cc: 266.66, sc: 66.66}
///   Bob = {cc: 266.67, sc: 66.67}
///   Carol = {cc: 266.67, sc: 66.67}
///
/// Step 2 — Barback deduction (X = BB/N = $100/3 = $33.33,
///          deduction = X/N = $33.33/3 = $11.11):
///   Split: CC = $11.11 × 0.8 = $8.89, SC = $11.11 − $8.89 = $2.22
///   You:   cc = 266.66 − 8.89 = 257.77, sc = 66.66 − 2.22 = 64.44
///   Bob:   cc = 266.67 − 8.89 = 257.78, sc = 66.67 − 2.22 = 64.45
///   Carol: cc = 266.67 − 8.89 = 257.78, sc = 66.67 − 2.22 = 64.45
///
/// Step 3 — Barback pool (X = $33.33, shared by 1 barback):
///   Split: CC = $33.33 × 0.8 = $26.66, SC = $33.33 − $26.66 = $6.67
///   Barback = {cc: 26.66, sc: 6.67}
///
/// Step 4 — Sum check:
///   You:   257.77 + 64.44 = 322.21
///   Bob:   257.78 + 64.45 = 322.23
///   Carol: 257.78 + 64.45 = 322.23
///   Barback: 26.66 + 6.67 = 33.33
///   Total: 322.21 + 322.23 + 322.23 + 33.33 = $1000.00 ✓
class TipCalculator {
  // Calculate the total barback cut based on the selected mode
  static double calculateBarbackCut({
    required ShiftTotals totals,
    required BarbackMode mode,
    required double value,
  }) {
    switch (mode) {
      case BarbackMode.flatAmount:
        return roundToCents(value);
      case BarbackMode.percentageOfTips:
        return roundToCents(totals.totalTips * (value / 100.0));
      case BarbackMode.percentageOfSales:
        return roundToCents(totals.sales * (value / 100.0));
    }
  }

  /// Run the full shift calculation (steps 1–4 above).
  ///
  /// [bartenderNames] and [barbackNames] must be free of duplicates;
  /// duplicate names would collapse into a single map entry.
  ///
  /// When [isSolo] is true the user keeps the entire pool and no
  /// barback deduction is applied.
  ///
  /// Returns a [TipOutResult] whose `totalDistributed` is guaranteed to
  /// equal `totals.totalTips` (to the cent) whenever there is at least
  /// one bartender.
  static TipOutResult calculateShift({
    required ShiftTotals totals,
    required List<String> bartenderNames,
    required List<String> barbackNames,
    required String userName,
    bool isSolo = false,
    double barbackCut = 0.0,
    bool equalSplit = true,
    Map<String, double>? hours,
  }) {
    final cc = totals.creditCardTips;
    final sc = totals.serviceChargeTips;
    final totalTips = cc + sc;

    if (isSolo) {
      return TipOutResult(
        bartenders: {
          userName: {'cc': cc, 'sc': sc},
        },
        barbacks: const {},
      );
    }

    if (bartenderNames.isEmpty) {
      return const TipOutResult.empty();
    }

    // Whoever absorbs sub-penny rounding: the user when they worked,
    // otherwise the first bartender on the list.
    final remainderTo = bartenderNames.contains(userName)
        ? userName
        : bartenderNames.first;

    // STEP 1 — Split each pool separately so each sums to its total.
    final bartenders = splitPoolsSeparately(
      netPools: {'cc': cc, 'sc': sc},
      bartenderNames: bartenderNames,
      equalSplit: equalSplit,
      hours: hours ?? const {},
      remainderTo: remainderTo,
    );

    // The barback pool: X = BB / N. This is both what the barbacks
    // receive in total and what the bartenders collectively give up.
    final barbackPool = barbackNames.isEmpty
        ? 0.0
        : barbackLineItem(
            barbackCut: barbackCut,
            bartenderCount: bartenderNames.length,
          );

    // STEP 2 — Deduct each bartender's share of the barback pool,
    // split proportionally so the displayed numbers are Evention-ready.
    if (barbackPool > 0) {
      final deduction = barbackDeductionPerBartender(
        barbackCut: barbackCut,
        bartenderCount: bartenderNames.length,
      );
      final deductionSplit = splitDeductionProportionally(
        deduction: deduction,
        creditCardTips: cc,
        serviceChargeTips: sc,
      );
      for (final name in bartenderNames) {
        bartenders[name]!['cc'] = roundToCents(
          (bartenders[name]!['cc'] ?? 0) - deductionSplit['cc']!,
        );
        bartenders[name]!['sc'] = roundToCents(
          (bartenders[name]!['sc'] ?? 0) - deductionSplit['sc']!,
        );
      }
    }

    // STEP 3 — Share the barback pool among the barbacks. Dividing by
    // the barback count (rather than paying each one the full pool)
    // keeps the payout equal to what the bartenders gave up.
    final barbacks = <String, Map<String, double>>{};
    if (barbackNames.isNotEmpty) {
      final poolSplit = splitDeductionProportionally(
        deduction: barbackPool,
        creditCardTips: cc,
        serviceChargeTips: sc,
      );
      final count = barbackNames.length;
      for (final name in barbackNames) {
        barbacks[name] = {
          'cc': roundToCents(poolSplit['cc']! / count),
          'sc': roundToCents(poolSplit['sc']! / count),
        };
      }
    }

    final result = TipOutResult(bartenders: bartenders, barbacks: barbacks);

    // STEP 4 — Penny reconciliation so the lines sum to TT exactly.
    final remainder = roundToCents(totalTips - result.totalDistributed);
    if (remainder != 0) {
      if (barbacks.isNotEmpty) {
        final first = barbackNames.first;
        barbacks[first]!['cc'] = roundToCents(
          (barbacks[first]!['cc'] ?? 0) + remainder,
        );
      } else {
        final target =
            bartenders.containsKey(userName) ? userName : bartenders.keys.first;
        bartenders[target]!['cc'] = roundToCents(
          (bartenders[target]!['cc'] ?? 0) + remainder,
        );
      }
    }

    return result;
  }

  /// Calculate the total barback pool: X = BB / N
  /// where BB is the total barback tip-out and N is the number of
  /// bartenders. This is what each bartender's app shows as the
  /// barback's tip-out, and is shared among the barbacks in step 3.
  static double barbackLineItem({
    required double barbackCut,
    required int bartenderCount,
  }) {
    if (bartenderCount <= 0) return 0;
    return roundToCents(barbackCut / bartenderCount);
  }

  /// Calculate each bartender's barback deduction: X / N
  /// where X = BB / N. This is the amount deducted from each
  /// bartender's line for the barback tip-out.
  static double barbackDeductionPerBartender({
    required double barbackCut,
    required int bartenderCount,
  }) {
    if (bartenderCount <= 0) return 0;
    final x = roundToCents(barbackCut / bartenderCount);
    return roundToCents(x / bartenderCount);
  }

  /// Split a barback deduction amount proportionally between the
  /// CC and SC pools based on the ratio of each pool to total tips.
  ///
  /// The CC portion is computed first and rounded to cents:
  ///   `ccPortion = round(deduction × CC / (CC + SC))`
  /// The SC portion is the remainder:
  ///   `scPortion = deduction − ccPortion`
  /// This guarantees `ccPortion + scPortion = deduction` exactly.
  ///
  /// Returns a map with 'cc' and 'sc' keys.
  static Map<String, double> splitDeductionProportionally({
    required double deduction,
    required double creditCardTips,
    required double serviceChargeTips,
  }) {
    final totalTips = creditCardTips + serviceChargeTips;
    if (totalTips <= 0) {
      return {'cc': 0.0, 'sc': 0.0};
    }
    final ccPortion = roundToCents(deduction * creditCardTips / totalTips);
    final scPortion = roundToCents(deduction - ccPortion);
    return {'cc': ccPortion, 'sc': scPortion};
  }

  /// Round to the nearest cent (2 decimal places).
  static double roundToCents(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  /// Split a single pool equally. Rounds each share to cents.
  static double equalSplit(double pool, int count) {
    if (count <= 0) return 0;
    return roundToCents(pool / count);
  }

  /// Split a single pool proportionally by hours.
  /// `share = pool × personHours / totalHours`, rounded to cents.
  static double hourlySplit({
    required double pool,
    required double personHours,
    required double totalHours,
  }) {
    if (totalHours <= 0) return 0;
    return roundToCents(pool * personHours / totalHours);
  }

  /// Split each tip pool (cc, sc) separately for each bartender.
  ///
  /// Each pool is split independently so that each pool sums exactly
  /// to its total. Any rounding remainder (a penny or two) is added
  /// to the person specified by `remainderTo` (or nobody if null).
  ///
  /// Returns a map of person name -> { 'cc': amount, 'sc': amount }.
  static Map<String, Map<String, double>> splitPoolsSeparately({
    required Map<String, double> netPools,
    required List<String> bartenderNames,
    required bool equalSplit,
    required Map<String, double> hours,
    String? remainderTo,
  }) {
    final result = <String, Map<String, double>>{};

    if (bartenderNames.isEmpty) return result;

    for (final name in bartenderNames) {
      result[name] = {'cc': 0.0, 'sc': 0.0};
    }

    // Split each pool separately
    for (final poolKey in ['cc', 'sc']) {
      final poolAmount = netPools[poolKey] ?? 0.0;
      if (poolAmount <= 0) continue;

      if (equalSplit) {
        final perPerson = TipCalculator.equalSplit(
          poolAmount,
          bartenderNames.length,
        );
        for (final name in bartenderNames) {
          result[name]![poolKey] = perPerson;
        }
      } else {
        final totalHours = bartenderNames.fold<double>(
          0.0,
          (sum, name) => sum + (hours[name] ?? 0),
        );
        for (final name in bartenderNames) {
          final personHours = hours[name] ?? 0;
          result[name]![poolKey] = hourlySplit(
            pool: poolAmount,
            personHours: personHours,
            totalHours: totalHours,
          );
        }
      }

      // Hand any rounding remainder to the designated person so the
      // pool sums exactly to its total.
      final totalDistributed = bartenderNames.fold<double>(
        0.0,
        (sum, name) => sum + (result[name]![poolKey] ?? 0),
      );
      final remainder = roundToCents(poolAmount - totalDistributed);
      if (remainder != 0 && remainderTo != null) {
        result[remainderTo]![poolKey] =
            (result[remainderTo]![poolKey] ?? 0) + remainder;
      }
    }

    return result;
  }
}
