import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/imported_shift.dart';
import '../models/shift_totals.dart';
import '../models/tip_out_result.dart';

class CsvExportService {
  static const String _fileName = 'tip_out_log.csv';
  static const String _header =
      'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,Barback Cut';

  static Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Check whether the log already contains rows for [date].
  static Future<bool> hasDataForDate(DateTime date) async {
    final file = await _logFile();
    if (!await file.exists()) return false;

    final target = _dateStr(date);
    final lines = await file.readAsLines();
    // Skip the header row and compare the parsed Date column rather
    // than using startsWith, which could match a longer date string.
    return lines.skip(1).any((line) => _firstField(line) == target);
  }

  /// Append a shift entry to the CSV log file.
  static Future<String> appendShift({
    required DateTime timestamp,
    required ShiftTotals totals,
    required TipOutResult result,
    required double barbackCut,
  }) async {
    final file = await _logFile();

    if (!await file.exists()) {
      await file.writeAsString('$_header\n');
    }

    final rows = _buildRows(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: barbackCut,
    );

    await file.writeAsString(rows, mode: FileMode.append, flush: true);
    return file.path;
  }

  /// Replace the rows for [timestamp]'s date with a fresh set.
  ///
  /// This is the "redo the shift" path: every row for that day is
  /// dropped and replaced. Use [appendShift] to log a second shift on
  /// the same day without discarding the first.
  static Future<String> overwriteToday({
    required DateTime timestamp,
    required ShiftTotals totals,
    required TipOutResult result,
    required double barbackCut,
  }) async {
    final file = await _logFile();

    if (!await file.exists()) {
      return appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: barbackCut,
      );
    }

    final target = _dateStr(timestamp);
    final lines = await file.readAsLines();

    // Keep the header plus every row from a different date.
    final kept = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      if (i == 0 && line == _header) {
        continue; // header re-added below
      }
      if (_firstField(line) == target) continue;
      kept.add(line);
    }

    final rows = _buildRows(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: barbackCut,
    );

    final buffer = StringBuffer()..writeln(_header);
    for (final line in kept) {
      buffer.writeln(line);
    }
    buffer.write(rows);

    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  /// Build a standalone CSV (header + one shift's rows) suitable for
  /// sharing to another bartender's device. [parseShareableCsv] reads
  /// this exact format back on the receiving end.
  static String buildShareableCsv({
    required DateTime timestamp,
    required ShiftTotals totals,
    required TipOutResult result,
    required double barbackCut,
  }) {
    final buffer = StringBuffer()..writeln(_header);
    buffer.write(_buildRows(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: barbackCut,
    ));
    return buffer.toString();
  }

  /// Write [buildShareableCsv]'s output to a temp file and return its
  /// path, ready to hand to `Share.shareXFiles`.
  static Future<String> writeShareableFile({
    required DateTime timestamp,
    required ShiftTotals totals,
    required TipOutResult result,
    required double barbackCut,
  }) async {
    final dir = await getTemporaryDirectory();
    final name = 'tip_out_shift_${_dateStr(timestamp)}_'
        '${_pad(timestamp.hour)}${_pad(timestamp.minute)}.csv';
    final file = File('${dir.path}/$name');
    await file.writeAsString(buildShareableCsv(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: barbackCut,
    ));
    return file.path;
  }

  /// Parse a shared shift CSV, as produced by [buildShareableCsv], into
  /// its component fields for preview/import.
  ///
  /// Throws a [FormatException] if [content] doesn't look like a
  /// tip-out shift file.
  static ImportedShift parseShareableCsv(String content) {
    final lines = content
        .split(RegExp(r'\r\n|\n|\r'))
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty || lines.first.trim() != _header) {
      throw const FormatException('Not a recognized tip-out shift file.');
    }

    final rows = lines.skip(1).toList();

    String? totalsRowLine;
    String? dateStr;
    String? timeStr;
    var cc = 0.0, sc = 0.0, sales = 0.0, barbackCut = 0.0;
    final barbacks = <String, Map<String, double>>{};
    final bartenders = <String, Map<String, double>>{};

    for (final row in rows) {
      final fields = _splitRow(row);
      if (fields.length < 8) continue;

      switch (fields[2]) {
        case 'Shift Totals':
          totalsRowLine = row;
          dateStr = fields[0];
          timeStr = fields[1];
          cc = double.tryParse(fields[4]) ?? 0;
          sc = double.tryParse(fields[5]) ?? 0;
          sales = double.tryParse(fields[6]) ?? 0;
          barbackCut = double.tryParse(fields[7]) ?? 0;
        case 'Barback':
          barbacks[fields[3]] = {
            'cc': double.tryParse(fields[4]) ?? 0,
            'sc': double.tryParse(fields[5]) ?? 0,
          };
        case 'Bartender':
          bartenders[fields[3]] = {
            'cc': double.tryParse(fields[4]) ?? 0,
            'sc': double.tryParse(fields[5]) ?? 0,
          };
      }
    }

    if (totalsRowLine == null || dateStr == null || timeStr == null) {
      throw const FormatException('Missing shift totals row.');
    }

    return ImportedShift(
      dateStr: dateStr,
      timeStr: timeStr,
      creditCardTips: cc,
      serviceChargeTips: sc,
      sales: sales,
      barbackCut: barbackCut,
      barbacks: barbacks,
      bartenders: bartenders,
      rawRows: rows,
      totalsRowLine: totalsRowLine,
    );
  }

  /// True when [totalsRowLine] (the exact "Shift Totals" row from a
  /// shared file) already appears in the local log — i.e. this exact
  /// shift has already been saved or imported.
  static Future<bool> hasDuplicateShift(String totalsRowLine) async {
    final file = await _logFile();
    if (!await file.exists()) return false;
    final lines = await file.readAsLines();
    return lines.contains(totalsRowLine);
  }

  /// Append an imported shift's rows to the local log, creating it with
  /// a header if needed. Rows are appended verbatim, exactly as they
  /// appeared in the shared file, so the numbers can't drift from what
  /// the recipient previewed.
  static Future<String> importShift(ImportedShift shift) async {
    final file = await _logFile();

    if (!await file.exists()) {
      await file.writeAsString('$_header\n');
    }

    final buffer = StringBuffer();
    for (final row in shift.rawRows) {
      buffer.writeln(row);
    }

    await file.writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
    return file.path;
  }

  /// Build the row block for one shift: a totals row, then one row per
  /// barback, then one row per bartender.
  static String _buildRows({
    required DateTime timestamp,
    required ShiftTotals totals,
    required TipOutResult result,
    required double barbackCut,
  }) {
    final buffer = StringBuffer();
    final date = _dateStr(timestamp);
    final time = '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}';

    buffer.writeln(_row([
      date,
      time,
      'Shift Totals',
      '',
      _money(totals.creditCardTips),
      _money(totals.serviceChargeTips),
      _money(totals.sales),
      _money(barbackCut),
    ]));

    result.barbacks.forEach((name, pools) {
      buffer.writeln(_row([
        date,
        time,
        'Barback',
        name,
        _money(pools['cc'] ?? 0),
        _money(pools['sc'] ?? 0),
        '',
        '',
      ]));
    });

    result.bartenders.forEach((name, pools) {
      buffer.writeln(_row([
        date,
        time,
        'Bartender',
        name,
        _money(pools['cc'] ?? 0),
        _money(pools['sc'] ?? 0),
        '',
        '',
      ]));
    });

    return buffer.toString();
  }

  /// Join fields into a CSV row, quoting any field that contains a
  /// comma, quote, or newline (RFC 4180 style).
  static String _row(List<String> fields) => fields.map(_escape).join(',');

  static String _escape(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Read the first (Date) field of a row, honouring quoting.
  static String _firstField(String line) {
    if (line.startsWith('"')) {
      final end = line.indexOf('"', 1);
      return end == -1 ? line : line.substring(1, end);
    }
    final comma = line.indexOf(',');
    return comma == -1 ? line : line.substring(0, comma);
  }

  /// Split a CSV row into its fields, honouring RFC 4180 quoting
  /// (the inverse of [_row]/[_escape]).
  static List<String> _splitRow(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buffer.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buffer.write(char);
        }
      } else if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    fields.add(buffer.toString());
    return fields;
  }

  static String _money(double value) => value.toStringAsFixed(2);

  static String _dateStr(DateTime date) =>
      '${date.year}-${_pad(date.month)}-${_pad(date.day)}';

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
