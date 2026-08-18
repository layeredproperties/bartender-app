import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tip_out/models/pools.dart';
import 'package:tip_out/models/shift_label.dart';
import 'package:tip_out/models/shift_totals.dart';
import 'package:tip_out/models/tip_out_result.dart';
import 'package:tip_out/services/csv_export_service.dart';
import 'package:tip_out/services/settings_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  group('shiftLabel', () {
    final date = DateTime(2026, 8, 18);

    test('date alone when no location was picked', () {
      expect(shiftLabel(date, null), 'Tue, Aug 18 2026');
      expect(shiftLabel(date, ''), 'Tue, Aug 18 2026');
      expect(shiftLabel(date, '   '), 'Tue, Aug 18 2026');
    });

    test('date and location when one was', () {
      expect(shiftLabel(date, 'The Anchor Bar'),
          'Tue, Aug 18 2026 — The Anchor Bar');
    });

    test('formats each weekday and month correctly', () {
      expect(formatShiftDate(DateTime(2026, 1, 1)), 'Thu, Jan 1 2026');
      expect(formatShiftDate(DateTime(2026, 12, 31)), 'Thu, Dec 31 2026');
      expect(formatShiftDate(DateTime(2026, 8, 16)), 'Sun, Aug 16 2026');
    });
  });

  group('saved locations', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts empty rather than inventing bar names', () async {
      expect(await SettingsService.loadLocations(), isEmpty);
      expect((await SettingsService.loadAll()).locations, isEmpty);
    });

    test('round-trips in the order they were added', () async {
      await SettingsService.saveLocations(['The Anchor Bar', 'Harbour House']);
      expect(await SettingsService.loadLocations(),
          ['The Anchor Bar', 'Harbour House']);
    });

    test('drops blanks and case-insensitive repeats', () async {
      SharedPreferences.setMockInitialValues({
        'locations': ['The Anchor Bar', '  ', 'the anchor bar', 'Harbour House'],
      });
      expect(await SettingsService.loadLocations(),
          ['The Anchor Bar', 'Harbour House']);
    });
  });

  group('location in the tip log', () {
    late Directory tempDir;
    late File logFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tip_out_location');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
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
    final timestamp = DateTime(2026, 8, 18, 19, 15);

    test('is written and read back', () async {
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
        location: 'The Anchor Bar',
      );

      final shifts = await CsvExportService.localShiftsForDate(timestamp);
      expect(shifts.single.location, 'The Anchor Bar');
      expect(await logFile.readAsString(), contains('The Anchor Bar'));
    });

    test('is empty when the user skipped it', () async {
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
      );
      expect((await CsvExportService.localShiftsForDate(timestamp))
          .single.location, '');
    });

    test('survives a shared-file round trip', () async {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
        location: 'Harbour House',
      );
      expect(CsvExportService.parseShareableCsv(csv).location, 'Harbour House');
    });

    test('a name containing a comma survives quoting', () async {
      final csv = CsvExportService.buildShareableCsv(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
        location: 'Smith, Wesson & Co',
      );
      expect(CsvExportService.parseShareableCsv(csv).location,
          'Smith, Wesson & Co');
    });

    test('replacing a shift keeps the new location', () async {
      await CsvExportService.appendShift(
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
        location: 'The Anchor Bar',
      );
      final shift =
          (await CsvExportService.localShiftsForDate(timestamp)).single;

      await CsvExportService.replaceShift(
        totalsRowLine: shift.totalsRowLine,
        timestamp: timestamp,
        totals: totals,
        result: result,
        barbackCut: 30,
        location: 'Harbour House',
      );

      expect((await CsvExportService.localShiftsForDate(timestamp))
          .single.location, 'Harbour House');
    });
  });

  group('older files still parse', () {
    test('a pre-Location file (9 columns) reads back with no location', () {
      const header =
          'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,'
          'Barback Cut,Source';
      const body = '$header\n'
          '2026-08-18,19:15,Shift Totals,,320.50,40.00,1200.00,30.00,Local\n'
          '2026-08-18,19:15,Bartender,You,200.25,25.00,,,Local\n';

      final shift = CsvExportService.parseShareableCsv(body);
      expect(shift.location, '');
      expect(shift.creditCardTips, 320.5);
      expect(shift.bartenders['You'], const Pools(cc: 200.25, sc: 25.0));
    });

    test('a pre-Source file (8 columns) still reads back', () {
      const header =
          'Date,Time,Type,Name,Credit Card Tips,Service Charge Tips,Net Sales,'
          'Barback Cut';
      const body = '$header\n'
          '2026-08-18,19:15,Shift Totals,,320.50,40.00,1200.00,30.00\n'
          '2026-08-18,19:15,Bartender,You,200.25,25.00,,\n';

      final shift = CsvExportService.parseShareableCsv(body);
      expect(shift.location, '');
      expect(shift.creditCardTips, 320.5);
    });
  });
}
