import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/imported_shift.dart';
import '../services/csv_export_service.dart';

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
      final path = result?.files.single.path;
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

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

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
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
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
                    _row('Credit Card Tips', _money(shift.creditCardTips)),
                    _row('Service Charge Tips', _money(shift.serviceChargeTips)),
                    _row('Net Sales', _money(shift.sales)),
                    if (shift.barbackCut > 0)
                      _row('Barback Tip-Out', _money(shift.barbackCut)),
                    const Divider(),
                    _row('Total Tips', _money(shift.totalTips), bold: true),
                    if (shift.barbacks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Barbacks', style: theme.textTheme.titleSmall),
                      ...shift.barbacks.entries.map(
                        (e) => _row(
                          e.key,
                          _money((e.value['cc'] ?? 0) + (e.value['sc'] ?? 0)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text('Bartenders', style: theme.textTheme.titleSmall),
                    ...shift.bartenders.entries.map(
                      (e) => _row(
                        e.key,
                        _money((e.value['cc'] ?? 0) + (e.value['sc'] ?? 0)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_duplicate) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This exact shift already appears in your tip log.',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                    child: Text(_duplicate ? 'Add Anyway' : 'Add to My Tip Log'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
