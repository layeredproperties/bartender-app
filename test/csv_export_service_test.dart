import 'dart:io';

import 'package:bartender_tip_out/models/shift_totals.dart';
import 'package:bartender_tip_out/models/tip_out_result.dart';
import 'package:bartender_tip_out/services/csv_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tip_out_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final totals = ShiftTotals(
    creditCardTips: 320.5,
    serviceChargeTips: 40,
    sales: 1200,
  );
  final result = const TipOutResult(
    bartenders: {
      'You': {'cc': 200.25, 'sc': 25.0},
      'Bob': {'cc': 120.25, 'sc': 15.0},
    },
    barbacks: {
      'Charlie': {'cc': 0.0, 'sc': 0.0},
    },
  );
  final timestamp = DateTime(2026, 8, 11, 15, 45);

  group('buildShareableCsv / parseShareableCsv round-trip', () {
    test('parsed fields match what was shared', () {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final parsed = CsvExportService.parseShareableCsv(csv);

      expect(parsed.dateStr, '2026-08-11');
      expect(parsed.timeStr, '15:45');
      expect(parsed.creditCardTips, 320.5);
      expect(parsed.serviceChargeTips, 40.0);
      expect(parsed.sales, 1200.0);
      expect(parsed.barbackCut, 30.0);
      expect(parsed.bartenders['You'], {'cc': 200.25, 'sc': 25.0});
      expect(parsed.bartenders['Bob'], {'cc': 120.25, 'sc': 15.0});
      expect(parsed.barbacks['Charlie'], {'cc': 0.0, 'sc': 0.0});
      // rawRows should be reusable verbatim as the appended log lines.
      expect(parsed.rawRows.length, 4); // totals + 2 bartenders + 1 barback
    });

    test('handles a name containing a comma via quoting', () {
      final commaResult = const TipOutResult(
        bartenders: {
          'Smith, John': {'cc': 100.0, 'sc': 10.0},
        },
        barbacks: {},
      );
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: commaResult,
        barbackCut: 0,
      );

      final parsed = CsvExportService.parseShareableCsv(csv);
      expect(parsed.bartenders.containsKey('Smith, John'), isTrue);
    });

    test('throws FormatException for unrecognized content', () {
      expect(
        () => CsvExportService.parseShareableCsv('not,a,tip,out,file'),
        throwsFormatException,
      );
    });

    test('throws FormatException when the totals row is missing', () {
      const header =
          'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,Barback Cut';
      const body = '2026-08-11,15:45,Bartender,Bob,120.25,15.00,,';
      expect(
        () => CsvExportService.parseShareableCsv('$header\n$body'),
        throwsFormatException,
      );
    });
  });

  group('writeShareableFile', () {
    test('writes a file whose contents parse back correctly', () async {
      final path = await CsvExportService.writeShareableFile(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final content = await File(path).readAsString();
      final parsed = CsvExportService.parseShareableCsv(content);
      expect(parsed.dateStr, '2026-08-11');
      expect(parsed.creditCardTips, 320.5);
    });
  });

  group('hasDuplicateShift / importShift', () {
    test('a freshly imported shift is not a duplicate until imported', () async {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );
      final shift = CsvExportService.parseShareableCsv(csv);

      expect(await CsvExportService.hasDuplicateShift(shift.totalsRowLine),
          isFalse);

      await CsvExportService.importShift(shift);

      expect(await CsvExportService.hasDuplicateShift(shift.totalsRowLine),
          isTrue);
    });

    test('importShift appends rows the local log can read back', () async {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );
      final shift = CsvExportService.parseShareableCsv(csv);

      await CsvExportService.importShift(shift);

      expect(await CsvExportService.hasDataForDate(timestamp), isTrue);
    });

    test('importing the same shift twice creates two duplicate blocks '
        '(caller is expected to check hasDuplicateShift first)', () async {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );
      final shift = CsvExportService.parseShareableCsv(csv);

      await CsvExportService.importShift(shift);
      await CsvExportService.importShift(shift);

      final logFile = File('${tempDir.path}/tip_out_log.csv');
      final lines =
          (await logFile.readAsLines()).where((l) => l.trim().isNotEmpty);
      // header + 4 rows, twice
      expect(lines.length, 1 + 4 * 2);
    });
  });
}
