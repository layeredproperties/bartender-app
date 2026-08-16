import 'money.dart';

/// One person's Evention-ready line item: the credit-card tip amount and
/// the service-charge tip amount.
///
/// This replaces the `Map<String, double>` with `'cc'`/`'sc'` string keys
/// that used to be threaded through the calculator, the CSV service, and
/// both result screens. Every read of that map needed a `?? 0` fallback
/// and a typo'd key failed silently at runtime; here both amounts always
/// exist and the field names are checked by the compiler.
class Pools {
  final double cc;
  final double sc;

  const Pools({this.cc = 0, this.sc = 0});

  static const Pools zero = Pools();

  /// The person's payout. Rounded because adding two exact cent values
  /// as doubles reintroduces representation noise (`257.77 + 64.44`
  /// evaluates to `322.21000000000004`).
  double get total => roundToCents(cc + sc);

  bool get hasNegative => cc < 0 || sc < 0;

  Pools operator +(Pools other) =>
      Pools(cc: cc + other.cc, sc: sc + other.sc);

  Pools operator -(Pools other) =>
      Pools(cc: cc - other.cc, sc: sc - other.sc);

  Pools operator /(num divisor) =>
      divisor == 0 ? zero : Pools(cc: cc / divisor, sc: sc / divisor);

  /// Round both amounts to the cent.
  Pools rounded() => Pools(cc: roundToCents(cc), sc: roundToCents(sc));

  /// Add [amount] to whichever pool is in play, preferring credit card.
  ///
  /// Used for penny reconciliation: on a service-charge-only shift,
  /// dropping the remainder into `cc` would invent a credit-card line
  /// out of nothing and break the Evention-ready framing.
  Pools addRemainder(double amount) => cc != 0 || sc == 0
      ? Pools(cc: roundToCents(cc + amount), sc: sc)
      : Pools(cc: cc, sc: roundToCents(sc + amount));

  Pools copyWith({double? cc, double? sc}) =>
      Pools(cc: cc ?? this.cc, sc: sc ?? this.sc);

  @override
  bool operator ==(Object other) =>
      other is Pools && other.cc == cc && other.sc == sc;

  @override
  int get hashCode => Object.hash(cc, sc);

  @override
  String toString() => 'Pools(cc: $cc, sc: $sc)';
}
