import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tip_out/models/pools.dart';
import 'package:tip_out/models/shift_totals.dart';
import 'package:tip_out/models/tip_out_result.dart';
import 'package:tip_out/services/csv_export_service.dart';

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

  final lunch = DateTime(2026, 8, 11, 11, 30);
  final dinner = DateTime(2026, 8, 11, 19, 15);

  Future<void> save(DateTime at, {double cc = 320.5}) =>
      CsvExportService.appendShift(
        timestamp: at,
        totals: ShiftTotals(
          creditCardTips: cc,
          serviceChargeTips: 40,
          sales: 1200,
        ),
        result: result,
        barbackCut: 30,
      );

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

  group('localShiftsForDate', () {
    test('lists this device\'s shifts for the date, oldest first', () async {
      await save(lunch);
      await save(dinner);
      await importTeammateShift();

      final shifts = await CsvExportService.localShiftsForDate(lunch);

      expect(shifts.map((s) => s.timeStr), ['11:30', '19:15']);
      expect(shifts.first.totalTips, 360.5);
    });

    test('excludes shifts a teammate shared', () async {
      await importTeammateShift();
      expect(await CsvExportService.localShiftsForDate(lunch), isEmpty);
    });

    test('excludes other dates', () async {
      await save(DateTime(2026, 8, 10, 20, 0));
      expect(await CsvExportService.localShiftsForDate(lunch), isEmpty);
    });

    test('renders the time the way a schedule reads', () async {
      await save(lunch);
      await save(dinner);
      final shifts = await CsvExportService.localShiftsForDate(lunch);
      expect(shifts.map((s) => s.displayTime), ['11:30 AM', '7:15 PM']);
    });
  });

  group('replaceShift', () {
    test('redoing one shift of a double leaves the other alone', () async {
      // The bug: "Replace Today" replaced every shift on the date, so
      // fixing the dinner numbers silently destroyed the lunch shift.
      await save(lunch, cc: 100);
      await save(dinner, cc: 200);

      final shifts = await CsvExportService.localShiftsForDate(lunch);
      final dinnerShift = shifts.firstWhere((s) => s.timeStr == '19:15');

      await CsvExportService.replaceShift(
        totalsRowLine: dinnerShift.totalsRowLine,
        timestamp: dinner,
        totals: const ShiftTotals(creditCardTips: 999, serviceChargeTips: 1),
        result: result,
        barbackCut: 30,
      );

      final after = await CsvExportService.localShiftsForDate(lunch);
      expect(after.length, 2, reason: 'the lunch shift must survive');
      expect(after.firstWhere((s) => s.timeStr == '11:30').creditCardTips, 100);
      expect(after.firstWhere((s) => s.timeStr == '19:15').creditCardTips, 999);
    });

    test('keeps the log in chronological order', () async {
      await save(lunch, cc: 100);
      await save(dinner, cc: 200);

      final shifts = await CsvExportService.localShiftsForDate(lunch);
      await CsvExportService.replaceShift(
        totalsRowLine: shifts.first.totalsRowLine,
        timestamp: lunch,
        totals: const ShiftTotals(creditCardTips: 111, serviceChargeTips: 0),
        result: result,
        barbackCut: 0,
      );

      // The replacement sits where the original did, not appended last.
      final after = await CsvExportService.localShiftsForDate(lunch);
      expect(after.map((s) => s.timeStr), ['11:30', '19:15']);
      expect(after.first.creditCardTips, 111);
    });

    test('keeps shifts a teammate shared for the same date', () async {
      await importTeammateShift();
      await save(dinner);

      final shifts = await CsvExportService.localShiftsForDate(dinner);
      await CsvExportService.replaceShift(
        totalsRowLine: shifts.single.totalsRowLine,
        timestamp: dinner,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final body = await logFile.readAsString();
      expect(body.contains('Bob'), isTrue,
          reason: 'imported teammate row must survive');
      expect(body.contains(CsvExportService.sourceImported), isTrue);
      expect(RegExp('Bartender,You').allMatches(body).length, 1);
    });

    test('leaves other dates alone', () async {
      await save(DateTime(2026, 8, 10, 20, 0));
      await save(dinner);

      final shifts = await CsvExportService.localShiftsForDate(dinner);
      await CsvExportService.replaceShift(
        totalsRowLine: shifts.single.totalsRowLine,
        timestamp: dinner,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      final body = await logFile.readAsString();
      expect(body.contains('2026-08-10'), isTrue);
      expect(body.contains('2026-08-11'), isTrue);
    });

    test('still writes the shift if the target has since vanished', () async {
      await save(lunch);
      final shifts = await CsvExportService.localShiftsForDate(lunch);
      final key = shifts.single.totalsRowLine;

      // Simulate the log being cleared between listing and saving.
      await logFile.delete();

      await CsvExportService.replaceShift(
        totalsRowLine: key,
        timestamp: dinner,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      expect((await CsvExportService.localShiftsForDate(dinner)).length, 1);
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

      // An imported shift is not offered as one of yours to redo.
      expect(await CsvExportService.localShiftsForDate(lunch), isEmpty);

      await save(dinner);
      final shifts = await CsvExportService.localShiftsForDate(dinner);
      await CsvExportService.replaceShift(
        totalsRowLine: shifts.single.totalsRowLine,
        timestamp: dinner,
        totals: totals,
        result: result,
        barbackCut: 30,
      );

      expect((await logFile.readAsString()).contains('Bob'), isTrue);
    });

    test('duplicate detection ignores the Source column', () async {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: dinner,
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
