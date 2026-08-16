import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/imported_shift.dart';
import '../models/money.dart';
import '../models/pools.dart';
import '../models/shift_totals.dart';
import '../models/tip_out_result.dart';

class CsvExportService {
  static const String _fileName = 'tip_out_log.csv';

  /// Rows a teammate sent you, tagged so "Replace Today" can leave them
  /// alone.
  static const String sourceLocal = 'Local';
  static const String sourceImported = 'Imported';

  static const String _header =
      'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,'
      'Barback Cut,Source';

  /// The pre-Source header. Files shared by an older build of the app
  /// still parse; rows already in a local log are treated as [sourceLocal].
  static const String _legacyHeader =
      'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,'
      'Barback Cut';

  /// Number of columns before Source — the part of a row that identifies
  /// a shift, and so the part duplicate detection compares.
  static const int _sourceIndex = 8;

  /// Resolve `name` inside `dir`, creating the directory first.
  ///
  /// `File.writeAsString` creates the file but not the directories above
  /// it. On macOS `getTemporaryDirectory()` returns a per-bundle
  /// `Library/Caches/<bundle-id>` path that the OS has not necessarily
  /// created yet, so sharing a shift from a fresh install threw
  /// `PathNotFoundException` instead of producing a file. Creating the
  /// directory is a no-op once it exists.
  static Future<File> _fileIn(Directory dir, String name) async {
    await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  static Future<File> _logFile() async =>
      _fileIn(await getApplicationDocumentsDirectory(), _fileName);

  /// Check whether the log already contains rows for [date].
  static Future<bool> hasDataForDate(DateTime date) async {
    final file = await _logFile();
    if (!await file.exists()) return false;

    final target = _dateStr(date);
    final lines = await file.readAsLines();
    // Compare the parsed Date column rather than using startsWith,
    // which could match a longer date string.
    return lines
        .where((line) => !_isHeader(line))
        .any((line) => _firstField(line) == target);
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

    await file.writeAsString(
      _buildRows(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: barbackCut,
      ),
      mode: FileMode.append,
      flush: true,
    );
    return file.path;
  }

  /// Replace this device's own rows for [timestamp]'s date with a fresh
  /// set.
  ///
  /// This is the "redo the shift" path. Rows a teammate shared with you
  /// are kept: they're tagged [sourceImported] and are not this shift to
  /// redo, so wiping them would silently destroy data the user never
  /// entered here. Use [appendShift] to log a second shift on the same
  /// day without discarding the first.
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

    // Keep every row except this device's own rows for the target date.
    final kept = lines.where((line) {
      if (line.trim().isEmpty || _isHeader(line)) return false;
      final sameDay = _firstField(line) == target;
      return !(sameDay && _sourceOf(line) == sourceLocal);
    });

    final buffer = StringBuffer()..writeln(_header);
    for (final line in kept) {
      buffer.writeln(line);
    }
    buffer.write(_buildRows(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: barbackCut,
    ));

    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  /// How many rows in the log for [date] came from a teammate — what
  /// "Replace Today" will now preserve rather than delete.
  static Future<int> importedRowCountForDate(DateTime date) async {
    final file = await _logFile();
    if (!await file.exists()) return 0;

    final target = _dateStr(date);
    final lines = await file.readAsLines();
    return lines
        .where((line) => !_isHeader(line) && line.trim().isNotEmpty)
        .where((line) =>
            _firstField(line) == target && _sourceOf(line) == sourceImported)
        .length;
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
    final name = 'tip_out_shift_${_dateStr(timestamp)}_'
        '${_pad(timestamp.hour)}${_pad(timestamp.minute)}.csv';
    final file = await _fileIn(await getTemporaryDirectory(), name);
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

    if (lines.isEmpty || !_isHeader(lines.first)) {
      throw const FormatException('Not a recognized tip-out shift file.');
    }

    final rows = lines.skip(1).toList();

    String? totalsRowLine;
    String? dateStr;
    String? timeStr;
    var cc = 0.0, sc = 0.0, sales = 0.0, barbackCut = 0.0;
    final barbacks = <String, Pools>{};
    final bartenders = <String, Pools>{};

    Pools poolsFrom(List<String> fields) => Pools(
          cc: double.tryParse(fields[4]) ?? 0,
          sc: double.tryParse(fields[5]) ?? 0,
        );

    for (final row in rows) {
      final fields = _splitRow(row);
      if (fields.length < _sourceIndex) continue;

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
          barbacks[fields[3]] = poolsFrom(fields);
        case 'Bartender':
          bartenders[fields[3]] = poolsFrom(fields);
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
  ///
  /// The Source column is excluded from the comparison, since importing
  /// re-tags the row and it would otherwise never match.
  static Future<bool> hasDuplicateShift(String totalsRowLine) async {
    final file = await _logFile();
    if (!await file.exists()) return false;
    final key = _shiftKey(totalsRowLine);
    final lines = await file.readAsLines();
    return lines.any((line) => !_isHeader(line) && _shiftKey(line) == key);
  }

  /// Append an imported shift's rows to the local log, creating it with
  /// a header if needed.
  ///
  /// Every amount is copied through exactly as it appeared in the shared
  /// file, so the numbers can't drift from what the recipient previewed.
  /// Only the Source column is rewritten, tagging the rows
  /// [sourceImported] so [overwriteToday] leaves them alone.
  static Future<String> importShift(ImportedShift shift) async {
    final file = await _logFile();

    if (!await file.exists()) {
      await file.writeAsString('$_header\n');
    }

    final buffer = StringBuffer();
    for (final row in shift.rawRows) {
      buffer.writeln(_withSource(row, sourceImported));
    }

    await file.writeAsString(
      buffer.toString(),
      mode: FileMode.append,
      flush: true,
    );
    return file.path;
  }

  /// Build the row block for one shift: a totals row, then one row per
  /// barback, then one row per bartender.
  static String _buildRows({
    required DateTime timestamp,
    required ShiftTotals totals,
    required TipOutResult result,
    required double barbackCut,
    String source = sourceLocal,
  }) {
    final buffer = StringBuffer();
    final date = _dateStr(timestamp);
    final time = '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}';

    buffer.writeln(_row([
      date,
      time,
      'Shift Totals',
      '',
      formatAmount(totals.creditCardTips),
      formatAmount(totals.serviceChargeTips),
      formatAmount(totals.sales),
      formatAmount(barbackCut),
      source,
    ]));

    void writePeople(String type, Map<String, Pools> people) {
      people.forEach((name, pools) {
        buffer.writeln(_row([
          date,
          time,
          type,
          name,
          formatAmount(pools.cc),
          formatAmount(pools.sc),
          '',
          '',
          source,
        ]));
      });
    }

    writePeople('Barback', result.barbacks);
    writePeople('Bartender', result.bartenders);

    return buffer.toString();
  }

  static bool _isHeader(String line) {
    final trimmed = line.trim();
    return trimmed == _header || trimmed == _legacyHeader;
  }

  /// The identity of a shift row, ignoring the Source column.
  static String _shiftKey(String line) =>
      _row(_splitRow(line).take(_sourceIndex).toList());

  /// The Source column of a row. Rows written before the column existed
  /// are treated as local, which preserves the old overwrite behaviour
  /// for logs created by an earlier build.
  static String _sourceOf(String line) {
    final fields = _splitRow(line);
    if (fields.length <= _sourceIndex) return sourceLocal;
    final value = fields[_sourceIndex].trim();
    return value.isEmpty ? sourceLocal : value;
  }

  /// Return [line] with its Source column set to [source], appending the
  /// column when the row came from a pre-Source file.
  static String _withSource(String line, String source) {
    final fields = _splitRow(line);
    while (fields.length < _sourceIndex) {
      fields.add('');
    }
    if (fields.length == _sourceIndex) {
      fields.add(source);
    } else {
      fields[_sourceIndex] = source;
    }
    return _row(fields);
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

  static String _dateStr(DateTime date) =>
      '${date.year}-${_pad(date.month)}-${_pad(date.day)}';

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
