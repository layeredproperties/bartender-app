import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tip_out/models/pools.dart';
import 'package:tip_out/models/shift_totals.dart';
import 'package:tip_out/models/tip_out_result.dart';
import 'package:tip_out/services/csv_export_service.dart';

/// Reproduces a fresh install, where the OS has handed back a directory
/// path it has not actually created.
///
/// On macOS `getTemporaryDirectory()` returns
/// `~/Library/Containers/<bundle>/Data/Library/Caches/<bundle>`, and that
/// last component does not exist until something makes it. Sharing a
/// shift used to fail with:
///
///   PathNotFoundException: Cannot open file, path = '.../Caches/
///   com.layeredproperties.tipout/tip_out_shift_2026-08-16_1036.csv'
///   (OS Error: No such file or directory, errno = 2)
class _MissingDirPathProvider extends PathProviderPlatform {
  _MissingDirPathProvider(this.root);
  final String root;

  // Deliberately nested and never created.
  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/Documents';

  @override
  Future<String?> getTemporaryPath() async => '$root/Library/Caches/bundle.id';
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tip_out_missing_dir');
    // Point at a subpath of tempDir that does not exist.
    PathProviderPlatform.instance =
        _MissingDirPathProvider('${tempDir.path}/fresh_install');
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
  final timestamp = DateTime(2026, 8, 16, 10, 36);

  test('writeShareableFile creates its directory instead of throwing',
      () async {
    final path = await CsvExportService.writeShareableFile(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: 30,
    );

    expect(File(path).existsSync(), isTrue);
    final parsed =
        CsvExportService.parseShareableCsv(await File(path).readAsString());
    expect(parsed.creditCardTips, 320.5);
  });

  test('appendShift creates the documents directory on a fresh install',
      () async {
    final path = await CsvExportService.appendShift(
      timestamp: timestamp,
      totals: totals,
      result: result,
      barbackCut: 30,
    );

    expect(File(path).existsSync(), isTrue);
    expect(await CsvExportService.hasDataForDate(timestamp), isTrue);
  });

  test('read-only checks are safe before anything has been written',
      () async {
    expect(await CsvExportService.hasDataForDate(timestamp), isFalse);
    expect(await CsvExportService.hasDuplicateShift('anything'), isFalse);
    expect(await CsvExportService.importedRowCountForDate(timestamp), 0);
  });
}
