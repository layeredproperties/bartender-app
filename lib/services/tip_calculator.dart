import '../models/money.dart' as money;
import '../models/pools.dart';
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
///   - `X` — what this bartender reports as the barback's tip-out. For a
///     flat amount the user typed the *group's* payout, so `X = BB / N`.
///     For a percentage the figure was already computed from this
///     bartender's own tips or sales, so `X = BB` and it is reported in
///     full. The app never sees the other bartenders' numbers, so there
///     is no combined total a percentage could be divided by.
///   - Each bartender's deduction = `X × their share of the pool`, using
///     the same weights step 1 used: `1/N` on an equal split, or
///     `theirHours / totalHours` on an hourly one.
/// Because the shares sum to 1, the bartenders collectively give up
/// exactly `X` — which is exactly what the barbacks receive. On an equal
/// split this reduces to the flat `X / N` per bartender.
/// This deduction is split proportionally between the bartender's CC and
/// SC amounts by the CC/SC ratio, so the displayed numbers are
/// Evention-ready (no separate "Barback Tip-Out" line).
///
/// Weighting the deduction is what keeps an hourly shift fair: a
/// bartender who worked two of twelve hours covers a sixth of the
/// barback, not half of it.
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
/// differs from TT by a penny, the remainder is added to a bartender's
/// line — the user's when they worked, otherwise the first bartender's.
/// Never a barback's: that figure is reported to the POS and has to
/// match the rule exactly. This guarantees:
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
/// Step 2 — Barback deduction (X = BB/N = $100/3 = $33.33; equal split,
///          so each share is 1/3 and deduction = $33.33/3 = $11.11):
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
///
/// ### Worked example — hourly split
/// 2 bartenders (You 10h, Bob 2h), TT = $1000 (all CC), BB = $200,
/// 1 barback. X = BB/N = $100.
///
///   Step 1: You = 1000 × 10/12 = $833.33, Bob = 1000 × 2/12 = $166.67
///   Step 2: You gives up 100 × 10/12 = $83.33
///           Bob gives up 100 ×  2/12 = $16.67  (a flat split would have
///                                               charged Bob $50)
///           You = 833.33 − 83.33 = $750.00
///           Bob = 166.67 − 16.67 = $150.00
///   Step 3: Barback = $100.00
///   Total:  750.00 + 150.00 + 100.00 = $1000.00 ✓
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
  /// [bartenderNames] and [barbackNames] must each be free of duplicates.
  /// Every map in this file is keyed by name, so a repeated name would
  /// collapse two people into one line item and quietly hand the missing
  /// share to whoever absorbs the rounding remainder. That is a silent
  /// money error, so it throws an [ArgumentError] instead — the roster
  /// screens reject duplicate names before it can happen.
  ///
  /// When [isSolo] is true the user keeps the entire pool and no
  /// barback deduction is applied.
  ///
  /// Returns a [TipOutResult] whose `totalDistributed` is guaranteed to
  /// equal `totals.totalTips` (to the cent) whenever there is at least
  /// one bartender. With no bartenders it returns [TipOutResult.empty],
  /// which distributes nothing — callers must not reach that state with
  /// a non-zero pool.
  static TipOutResult calculateShift({
    required ShiftTotals totals,
    required List<String> bartenderNames,
    required List<String> barbackNames,
    required String userName,
    bool isSolo = false,
    double barbackCut = 0.0,
    BarbackMode barbackMode = BarbackMode.flatAmount,
    bool equalSplit = true,
    Map<String, double>? hours,
  }) {
    _assertNoDuplicates(bartenderNames, 'bartenderNames');
    _assertNoDuplicates(barbackNames, 'barbackNames');

    final cc = totals.creditCardTips;
    final sc = totals.serviceChargeTips;
    final totalTips = cc + sc;

    if (isSolo) {
      return TipOutResult(
        bartenders: {userName: Pools(cc: cc, sc: sc).rounded()},
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
      netPools: Pools(cc: cc, sc: sc),
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
            mode: barbackMode,
          );

    // STEP 2 — Deduct each bartender's share of the barback pool,
    // split proportionally so the displayed numbers are Evention-ready.
    if (barbackPool > 0) {
      final weights = splitWeights(
        bartenderNames: bartenderNames,
        equalSplit: equalSplit,
        hours: hours ?? const {},
      );
      for (final name in bartenderNames) {
        final deductionSplit = splitDeductionProportionally(
          deduction: roundToCents(barbackPool * weights[name]!),
          creditCardTips: cc,
          serviceChargeTips: sc,
        );
        bartenders[name] = (bartenders[name]! - deductionSplit).rounded();
      }
    }

    // STEP 3 — Share the barback pool among the barbacks. Dividing by
    // the barback count (rather than paying each one the full pool)
    // keeps the payout equal to what the bartenders gave up.
    final barbacks = <String, Pools>{};
    if (barbackNames.isNotEmpty) {
      final poolSplit = splitDeductionProportionally(
        deduction: barbackPool,
        creditCardTips: cc,
        serviceChargeTips: sc,
      );
      final share = (poolSplit / barbackNames.length).rounded();
      for (final name in barbackNames) {
        barbacks[name] = share;
      }
    }

    // STEP 4 — Penny reconciliation so the lines sum to TT exactly. The
    // remainder lands in whichever pool the recipient already has money
    // in, so a service-charge-only shift never grows a credit-card line.
    final result = TipOutResult(bartenders: bartenders, barbacks: barbacks);
    final remainder = roundToCents(totalTips - result.totalDistributed);
    if (remainder != 0) {
      // Always a bartender, never a barback. The barback's line is a
      // figure the user reports to the POS, and it has to match the rule
      // exactly — a "20% of tips" tip-out reading $200.01 is wrong even
      // though the books still balance. Bartender lines are take-home,
      // so they're the right place to absorb a stray cent.
      final target =
          bartenders.containsKey(userName) ? userName : bartenders.keys.first;
      bartenders[target] = bartenders[target]!.addRemainder(remainder);
    }

    return result;
  }

  static void _assertNoDuplicates(List<String> names, String label) {
    if (names.toSet().length == names.length) return;
    final seen = <String>{};
    final duplicates = names.where((n) => !seen.add(n)).toSet();
    throw ArgumentError.value(
      names,
      label,
      'duplicate names would collapse into one line item: '
      '${duplicates.join(', ')}',
    );
  }

  /// What this bartender reports as the barback's tip-out.
  ///
  /// Which depends entirely on the mode, because only one of them is a
  /// figure for the whole group:
  ///
  ///   - [BarbackMode.flatAmount] — the user typed what the *group*
  ///     owes the barback, the one number the app cannot work out for
  ///     itself. Split it: `BB / N`. A $90 payout across 3 bartenders
  ///     is $30 each.
  ///   - [BarbackMode.percentageOfTips] / [BarbackMode.percentageOfSales]
  ///     — the percentage was applied to *this* bartender's own tips or
  ///     sales, so the result is already personal. Report all of it.
  ///
  /// This app only ever sees one bartender's numbers; the copies running
  /// on their coworkers' phones can't talk to each other, so there is no
  /// combined total to divide a percentage by. Dividing one anyway was
  /// the bug: it shrank every reported percentage tip-out by a factor of
  /// N and underpaid the barback.
  static double barbackLineItem({
    required double barbackCut,
    required int bartenderCount,
    BarbackMode mode = BarbackMode.flatAmount,
  }) {
    if (bartenderCount <= 0) return 0;
    if (mode != BarbackMode.flatAmount) return roundToCents(barbackCut);
    return roundToCents(barbackCut / bartenderCount);
  }

  /// Each bartender's fraction of the pool: `1/N` on an equal split,
  /// `theirHours / totalHours` on an hourly one.
  ///
  /// The same weights drive both the payout (step 1) and the barback
  /// deduction (step 2), which is what keeps the two consistent.
  /// Falls back to an equal split when no usable hours were supplied.
  static Map<String, double> splitWeights({
    required List<String> bartenderNames,
    required bool equalSplit,
    required Map<String, double> hours,
  }) {
    if (bartenderNames.isEmpty) return const {};

    final totalHours = equalSplit
        ? 0.0
        : bartenderNames.fold<double>(
            0.0,
            (sum, name) => sum + (hours[name] ?? 0),
          );

    if (equalSplit || totalHours <= 0) {
      final share = 1 / bartenderNames.length;
      return {for (final name in bartenderNames) name: share};
    }

    return {
      for (final name in bartenderNames) name: (hours[name] ?? 0) / totalHours,
    };
  }

  /// One bartender's barback deduction: `X × share`, where X = BB / N
  /// and `share` is their fraction of the pool (see [splitWeights]).
  ///
  /// Because the shares sum to 1, the bartenders collectively give up
  /// exactly X — which is what the barbacks receive.
  static double barbackDeduction({
    required double barbackCut,
    required int bartenderCount,
    required double share,
  }) {
    if (bartenderCount <= 0) return 0;
    return roundToCents(
      barbackLineItem(
            barbackCut: barbackCut,
            bartenderCount: bartenderCount,
          ) *
          share,
    );
  }

  /// Each bartender's barback deduction on an equal split: X / N
  /// where X = BB / N.
  static double barbackDeductionPerBartender({
    required double barbackCut,
    required int bartenderCount,
  }) {
    if (bartenderCount <= 0) return 0;
    return barbackDeduction(
      barbackCut: barbackCut,
      bartenderCount: bartenderCount,
      share: 1 / bartenderCount,
    );
  }

  /// Split a barback deduction amount proportionally between the
  /// CC and SC pools based on the ratio of each pool to total tips.
  ///
  /// The CC portion is computed first and rounded to cents:
  ///   `ccPortion = round(deduction × CC / (CC + SC))`
  /// The SC portion is the remainder:
  ///   `scPortion = deduction − ccPortion`
  /// This guarantees `ccPortion + scPortion = deduction` exactly.
  static Pools splitDeductionProportionally({
    required double deduction,
    required double creditCardTips,
    required double serviceChargeTips,
  }) {
    final totalTips = creditCardTips + serviceChargeTips;
    if (totalTips <= 0) return Pools.zero;
    final ccPortion = roundToCents(deduction * creditCardTips / totalTips);
    return Pools(cc: ccPortion, sc: roundToCents(deduction - ccPortion));
  }

  /// Round to the nearest cent (2 decimal places).
  static double roundToCents(double value) => money.roundToCents(value);

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
  static Map<String, Pools> splitPoolsSeparately({
    required Pools netPools,
    required List<String> bartenderNames,
    required bool equalSplit,
    required Map<String, double> hours,
    String? remainderTo,
  }) {
    final result = <String, Pools>{};
    if (bartenderNames.isEmpty) return result;

    for (final name in bartenderNames) {
      result[name] = Pools.zero;
    }

    final totalHours = equalSplit
        ? 0.0
        : bartenderNames.fold<double>(
            0.0,
            (sum, name) => sum + (hours[name] ?? 0),
          );

    // Split each pool separately.
    for (final isCredit in const [true, false]) {
      final poolAmount = isCredit ? netPools.cc : netPools.sc;
      if (poolAmount <= 0) continue;

      double shareFor(String name) => equalSplit
          ? TipCalculator.equalSplit(poolAmount, bartenderNames.length)
          : hourlySplit(
              pool: poolAmount,
              personHours: hours[name] ?? 0,
              totalHours: totalHours,
            );

      var distributed = 0.0;
      for (final name in bartenderNames) {
        final share = shareFor(name);
        distributed += share;
        result[name] = isCredit
            ? result[name]!.copyWith(cc: share)
            : result[name]!.copyWith(sc: share);
      }

      // Hand any rounding remainder to the designated person so the pool
      // sums exactly to its total. Rounding here (rather than adding the
      // raw sum) is what keeps `totalDistributed` free of floating-point
      // drift like 1000.0000000000001.
      final remainder = roundToCents(poolAmount - distributed);
      if (remainder != 0 && remainderTo != null) {
        final current = result[remainderTo]!;
        result[remainderTo] = isCredit
            ? current.copyWith(cc: roundToCents(current.cc + remainder))
            : current.copyWith(sc: roundToCents(current.sc + remainder));
      }
    }

    return result;
  }
}
