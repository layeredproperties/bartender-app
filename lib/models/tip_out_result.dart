/// The outcome of a shift tip-out calculation.
///
/// Both [bartenders] and [barbacks] map a person's name to their
/// Evention-ready line item: `{'cc': amount, 'sc': amount}`.
///
/// The class guarantees (see `TipCalculator.calculateShift`) that
/// [totalDistributed] equals the shift's total tips exactly.
class TipOutResult {
  final Map<String, Map<String, double>> bartenders;
  final Map<String, Map<String, double>> barbacks;

  const TipOutResult({
    required this.bartenders,
    required this.barbacks,
  });

  const TipOutResult.empty()
      : bartenders = const {},
        barbacks = const {};

  /// Sum of every line item across both groups and both pools.
  double get totalDistributed {
    var sum = 0.0;
    for (final pools in bartenders.values) {
      sum += (pools['cc'] ?? 0) + (pools['sc'] ?? 0);
    }
    for (final pools in barbacks.values) {
      sum += (pools['cc'] ?? 0) + (pools['sc'] ?? 0);
    }
    return sum;
  }

  /// Total paid out to barbacks.
  double get totalBarbackPayout {
    var sum = 0.0;
    for (final pools in barbacks.values) {
      sum += (pools['cc'] ?? 0) + (pools['sc'] ?? 0);
    }
    return sum;
  }

  /// True when any line item came out negative, which means the barback
  /// tip-out was larger than the pool could support.
  bool get hasNegativeLines {
    bool negative(Map<String, Map<String, double>> group) => group.values.any(
          (pools) => (pools['cc'] ?? 0) < 0 || (pools['sc'] ?? 0) < 0,
        );
    return negative(bartenders) || negative(barbacks);
  }
}
