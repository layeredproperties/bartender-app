import 'money.dart';
import 'pools.dart';

/// The outcome of a shift tip-out calculation.
///
/// Both [bartenders] and [barbacks] map a person's name to their
/// Evention-ready line item.
///
/// The class guarantees (see `TipCalculator.calculateShift`) that
/// [totalDistributed] equals the shift's total tips exactly.
class TipOutResult {
  final Map<String, Pools> bartenders;
  final Map<String, Pools> barbacks;

  const TipOutResult({
    required this.bartenders,
    required this.barbacks,
  });

  const TipOutResult.empty()
      : bartenders = const {},
        barbacks = const {};

  /// Rounded so the running float error of summing many cent values
  /// can't leak out (the sum of a $1000 three-way split used to come
  /// back as `1000.0000000000001`).
  static double _sum(Map<String, Pools> group) =>
      roundToCents(group.values.fold(0.0, (sum, pools) => sum + pools.total));

  /// Sum of every line item across both groups and both pools.
  double get totalDistributed => roundToCents(_sum(bartenders) + _sum(barbacks));

  /// Total paid out to barbacks.
  double get totalBarbackPayout => _sum(barbacks);

  /// True when any line item came out negative, which means the barback
  /// tip-out was larger than the pool could support.
  bool get hasNegativeLines =>
      bartenders.values.any((p) => p.hasNegative) ||
      barbacks.values.any((p) => p.hasNegative);
}
