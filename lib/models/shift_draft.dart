import '../services/tip_calculator.dart';
import 'person.dart';
import 'shift_totals.dart';

/// Everything collected about the shift in progress, passed down the
/// Tips → Team → Barback → Hours → Results chain.
///
/// Each screen adds its own piece with [copyWith] rather than every
/// screen re-declaring and hand-forwarding the same five constructor
/// arguments — which is how `userName` ended up re-defaulting to `'You'`
/// at three separate layers.
class ShiftDraft {
  final ShiftTotals totals;
  final String userName;

  /// Where the shift was worked. Null when the user didn't pick one.
  final String? location;
  final List<Person> selectedPeople;
  final bool isSolo;
  final double barbackCut;

  /// How [barbackCut] was arrived at. A flat amount is the group's total
  /// payout and gets split; a percentage was computed from this
  /// bartender's own figures and is reported in full.
  final BarbackMode barbackMode;
  final bool equalSplit;

  /// Bartender name -> hours worked. Null when [equalSplit] is true.
  final Map<String, double>? hours;

  const ShiftDraft({
    required this.totals,
    required this.userName,
    this.location,
    this.selectedPeople = const [],
    this.isSolo = false,
    this.barbackCut = 0.0,
    this.barbackMode = BarbackMode.flatAmount,
    this.equalSplit = true,
    this.hours,
  });

  List<Person> get bartenders =>
      selectedPeople.where((p) => p.role == Role.bartender).toList();

  List<Person> get barbacks =>
      selectedPeople.where((p) => p.role == Role.barback).toList();

  ShiftDraft copyWith({
    ShiftTotals? totals,
    String? userName,
    String? location,
    List<Person>? selectedPeople,
    bool? isSolo,
    double? barbackCut,
    BarbackMode? barbackMode,
    bool? equalSplit,
    Map<String, double>? hours,
    bool clearHours = false,
  }) {
    return ShiftDraft(
      totals: totals ?? this.totals,
      userName: userName ?? this.userName,
      location: location ?? this.location,
      selectedPeople: selectedPeople ?? this.selectedPeople,
      isSolo: isSolo ?? this.isSolo,
      barbackCut: barbackCut ?? this.barbackCut,
      barbackMode: barbackMode ?? this.barbackMode,
      equalSplit: equalSplit ?? this.equalSplit,
      hours: clearHours ? null : (hours ?? this.hours),
    );
  }
}
