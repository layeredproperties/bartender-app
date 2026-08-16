class ShiftTotals {
  final double creditCardTips;
  final double serviceChargeTips;
  final double sales;

  const ShiftTotals({
    required this.creditCardTips,
    required this.serviceChargeTips,
    this.sales = 0.0,
  });

  double get totalTips => creditCardTips + serviceChargeTips;
}
