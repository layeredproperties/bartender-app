import 'pools.dart';

/// A shift parsed from a shared tip-out CSV file, ready for preview and
/// import into the local tip log.
///
/// [totalsRowLine] is the exact formatted "Shift Totals" row from the
/// shared file — it's the key used to detect whether this shift already
/// exists in the local log (see `CsvExportService.hasDuplicateShift`).
class ImportedShift {
  final String dateStr;
  final String timeStr;
  final double creditCardTips;
  final double serviceChargeTips;
  final double sales;
  final double barbackCut;

  /// Name -> line item for barback rows in the file.
  final Map<String, Pools> barbacks;

  /// Name -> line item for bartender rows in the file.
  final Map<String, Pools> bartenders;

  /// The raw CSV rows (excluding header) exactly as they appeared in the
  /// shared file — appended to the local log on import so the figures
  /// can't drift from what was displayed in the preview. Only the Source
  /// column is rewritten on import (see `CsvExportService.importShift`);
  /// every amount is passed through untouched.
  final List<String> rawRows;

  final String totalsRowLine;

  const ImportedShift({
    required this.dateStr,
    required this.timeStr,
    required this.creditCardTips,
    required this.serviceChargeTips,
    required this.sales,
    required this.barbackCut,
    required this.barbacks,
    required this.bartenders,
    required this.rawRows,
    required this.totalsRowLine,
  });

  double get totalTips => creditCardTips + serviceChargeTips;
}
