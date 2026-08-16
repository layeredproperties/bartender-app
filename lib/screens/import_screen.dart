import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/imported_shift.dart';
import '../models/money.dart';
import '../models/pools.dart';
import '../services/csv_export_service.dart';
import '../widgets/money_row.dart';

/// Lets the user pick a shift CSV a teammate shared with them (via
/// AirDrop, Messages, etc. — saved to Files/Downloads) and add it to
/// their own tip log, after previewing it and checking for duplicates.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportedShift? _preview;
  bool _duplicate = false;
  bool _busy = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _duplicate = false;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      // `files.single` throws when the picker returns an empty
      // selection; firstOrNull treats it as a cancel, which is what it
      // is.
      final path = result?.files.firstOrNull?.path;
      if (path == null) {
        // User cancelled the picker.
        if (mounted) setState(() => _busy = false);
        return;
      }

      final content = await File(path).readAsString();
      final shift = CsvExportService.parseShareableCsv(content);
      final duplicate =
          await CsvExportService.hasDuplicateShift(shift.totalsRowLine);

      if (!mounted) return;
      setState(() {
        _preview = shift;
        _duplicate = duplicate;
        _busy = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read that file: $e';
        _busy = false;
      });
    }
  }

  Future<void> _confirmImport() async {
    final shift = _preview;
    if (shift == null) return;

    setState(() => _busy = true);
    try {
      await CsvExportService.importShift(shift);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift added to your tip log')),
      );
      setState(() {
        _preview = null;
        _duplicate = false;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import: $e')),
      );
    }
  }

  void _dismissPreview() {
    setState(() {
      _preview = null;
      _duplicate = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shift = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Import Shift Data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Import a tip-out shift a teammate shared with you. It will '
            'be added as new rows in your tip log.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('Choose Shared File'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (shift != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${shift.dateStr}  ${shift.timeStr}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    MoneyRow('Credit Card Tips',
                        formatMoney(shift.creditCardTips)),
                    MoneyRow('Service Charge Tips',
                        formatMoney(shift.serviceChargeTips)),
                    MoneyRow('Net Sales', formatMoney(shift.sales)),
                    if (shift.barbackCut > 0)
                      MoneyRow(
                          'Barback Tip-Out', formatMoney(shift.barbackCut)),
                    const Divider(),
                    MoneyRow('Total Tips', formatMoney(shift.totalTips),
                        bold: true),
                    ..._group(theme, 'Barbacks', shift.barbacks),
                    ..._group(theme, 'Bartenders', shift.bartenders),
                  ],
                ),
              ),
            ),
            if (_duplicate) ...[
              const SizedBox(height: 16),
              const WarningCard(
                'This exact shift already appears in your tip log.',
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _dismissPreview,
                    child: Text(_duplicate ? 'Skip' : 'Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _confirmImport,
                    child:
                        Text(_duplicate ? 'Add Anyway' : 'Add to My Tip Log'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _group(
    ThemeData theme,
    String heading,
    Map<String, Pools> people,
  ) {
    if (people.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Text(heading, style: theme.textTheme.titleSmall),
      ...people.entries.map(
        (e) => MoneyRow(e.key, formatMoney(e.value.total)),
      ),
    ];
  }
}
