import 'dart:io';

import 'package:tip_out/models/pools.dart';
import 'package:tip_out/models/shift_totals.dart';
import 'package:tip_out/models/tip_out_result.dart';
import 'package:tip_out/services/csv_export_service.dart';
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
  late File logFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tip_out_preserve_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    logFile = File('${tempDir.path}/tip_out_log.csv');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const totals = ShiftTotals(
    creditCardTips: 320.5,
    serviceChargeTips: 40,
    sales: 1200,
  );
  const result = TipOutResult(
    bartenders: {'You': Pools(cc: 200.25, sc: 25.0)},
    barbacks: {},
  );
  final timestamp = DateTime(2026, 8, 11, 15, 45);

  /// A shift a teammate shared, already sitting in the local log.
  Future<void> importTeammateShift() async {
    final csv = CsvExportService.buildShareableCsv(
      timestamp: DateTime(2026, 8, 11, 9, 0),
      totals: const ShiftTotals(creditCardTips: 88.0, serviceChargeTips: 12.0),
      result: const TipOutResult(
        bartenders: {'Bob': Pools(cc: 88.0, sc: 12.0)},
        barbacks: {},
      ),
      barbackCut: 0,
    );
    await CsvExportService.importShift(
      CsvExportService.parseShareableCsv(csv),
    );
  }

  group('overwriteToday', () {
    test('keeps rows a teammate shared for the same date', () async {
      // The bug: "Replace Today" dropped every row whose date matched,
      // including a teammate's imported shift the user never entered
      // here and had no way to get back.
      await importTeammateShift();
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      await CsvExportService.overwriteToday(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final body = await logFile.readAsString();
      expect(body.contains('Bob'), isTrue,
          reason: 'imported teammate row must survive');
      expect(body.contains(CsvExportService.sourceImported), isTrue);
      // The user's own shift is written once, not twice.
      expect(RegExp('Bartender,You').allMatches(body).length, 1);
    });

    test('still replaces this device\'s own rows for the date', () async {
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      await CsvExportService.overwriteToday(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final lines = (await logFile.readAsLines())
          .where((l) => l.trim().isNotEmpty)
          .toList();
      // header + one totals row + one bartender row
      expect(lines.length, 3);
    });

    test('leaves rows from other dates alone', () async {
      await CsvExportService.appendShift(
        timestamp: DateTime(2026, 8, 10, 20, 0),
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      await CsvExportService.overwriteToday(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final body = await logFile.readAsString();
      expect(body.contains('2026-08-10'), isTrue);
      expect(body.contains('2026-08-11'), isTrue);
    });
  });

  group('importedRowCountForDate', () {
    test('counts only imported rows for that date', () async {
      await importTeammateShift();
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      // totals row + one bartender row from the shared file
      expect(await CsvExportService.importedRowCountForDate(timestamp), 2);
      expect(
        await CsvExportService.importedRowCountForDate(DateTime(2026, 8, 10)),
        0,
      );
    });
  });

  group('legacy files', () {
    const legacyHeader =
        'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,'
        'Barback Cut';

    test('a pre-Source shared file still parses', () async {
      const legacy = '$legacyHeader\n'
          '2026-08-11,15:45,Shift Totals,,320.50,40.00,1200.00,30.00\n'
          '2026-08-11,15:45,Bartender,You,200.25,25.00,,\n';

      final shift = CsvExportService.parseShareableCsv(legacy);

      expect(shift.dateStr, '2026-08-11');
      expect(shift.creditCardTips, 320.5);
      expect(shift.bartenders['You'], const Pools(cc: 200.25, sc: 25.0));
    });

    test('importing a pre-Source file tags its rows as imported', () async {
      const legacy = '$legacyHeader\n'
          '2026-08-11,15:45,Shift Totals,,320.50,40.00,1200.00,30.00\n'
          '2026-08-11,15:45,Bartender,Bob,200.25,25.00,,\n';

      await CsvExportService.importShift(
        CsvExportService.parseShareableCsv(legacy),
      );
      await CsvExportService.overwriteToday(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      expect((await logFile.readAsString()).contains('Bob'), isTrue);
    });

    test('duplicate detection ignores the Source column', () async {
      // Importing rewrites Source, so comparing whole lines would report
      // an already-imported shift as new.
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
  });
}
