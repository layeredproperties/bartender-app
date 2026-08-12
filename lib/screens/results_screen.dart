import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../models/person.dart';
import '../models/shift_totals.dart';
import '../models/tip_out_result.dart';
import '../services/csv_export_service.dart';
import '../services/tip_calculator.dart';

class ResultsScreen extends StatefulWidget {
  final ShiftTotals totals;
  final List<Person> selectedPeople;
  final bool isSolo;
  final double barbackCut;
  final bool equalSplit;
  final Map<String, double>? hours;
  final String userName;

  const ResultsScreen({
    super.key,
    required this.totals,
    required this.selectedPeople,
    required this.isSolo,
    this.barbackCut = 0.0,
    this.equalSplit = true,
    this.hours,
    this.userName = 'You',
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final TipOutResult _result;
  String? _csvPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _result = _calculate();
  }

  /// All calculation now lives in [TipCalculator] so it can be unit
  /// tested; this screen only renders the result.
  TipOutResult _calculate() {
    final bartenderNames = widget.selectedPeople
        .where((p) => p.role == Role.bartender)
        .map((p) => p.name)
        .toSet()
        .toList();
    final barbackNames = widget.selectedPeople
        .where((p) => p.role == Role.barback)
        .map((p) => p.name)
        .toSet()
        .toList();

    return TipCalculator.calculateShift(
      totals: widget.totals,
      bartenderNames: bartenderNames,
      barbackNames: barbackNames,
      userName: widget.userName,
      isSolo: widget.isSolo,
      barbackCut: widget.barbackCut,
      equalSplit: widget.equalSplit,
      hours: widget.hours,
    );
  }

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  String _buildShareText() {
    final buffer = StringBuffer()
      ..writeln('Tip-Out Results')
      ..writeln('Total Tips: ${_money(widget.totals.totalTips)}')
      ..writeln(
        'CC: ${_money(widget.totals.creditCardTips)}  '
        'SC: ${_money(widget.totals.serviceChargeTips)}',
      )
      ..writeln();

    if (_result.barbacks.isNotEmpty) {
      buffer.writeln('Barbacks:');
      _result.barbacks.forEach((name, pools) {
        buffer.writeln(
          '  $name — CC ${_money(pools['cc'] ?? 0)}, '
          'SC ${_money(pools['sc'] ?? 0)}',
        );
      });
      buffer.writeln();
    }

    buffer.writeln('Bartenders:');
    _result.bartenders.forEach((name, pools) {
      buffer.writeln(
        '  $name — CC ${_money(pools['cc'] ?? 0)}, '
        'SC ${_money(pools['sc'] ?? 0)}',
      );
    });

    return buffer.toString();
  }

  Future<void> _copyResults() async {
    // Clipboard works on every platform; the old implementation shelled
    // out to `pbcopy`, which crashes on iOS and Android.
    await Clipboard.setData(ClipboardData(text: _buildShareText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Results copied to clipboard')),
    );
  }

  /// Shares a small CSV file (in addition to the human-readable text)
  /// so a teammate who receives it can import it straight into their
  /// own tip log via the Home screen's Import action, instead of
  /// retyping the numbers.
  Future<void> _shareResults() async {
    try {
      final path = await CsvExportService.writeShareableFile(
        timestamp: DateTime.now(),
        totals: widget.totals,
        result: _result,
        barbackCut: widget.barbackCut,
      );
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv')],
        text: _buildShareText(),
        subject: 'Tip-Out Results',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share results: $e')),
      );
    }
  }

  /// Saving is explicit rather than a side effect of opening this
  /// screen, and reports success or failure to the user.
  Future<void> _saveToCsv() async {
    if (_saving) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    try {
      var overwrite = false;
      if (await CsvExportService.hasDataForDate(now)) {
        if (!mounted) return;
        final choice = await _askDuplicateDate();
        if (choice == null) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        overwrite = choice;
      }

      final path = overwrite
          ? await CsvExportService.overwriteToday(
              timestamp: now,
              totals: widget.totals,
              result: _result,
              barbackCut: widget.barbackCut,
            )
          : await CsvExportService.appendShift(
              timestamp: now,
              totals: widget.totals,
              result: _result,
              barbackCut: widget.barbackCut,
            );

      if (!mounted) return;
      setState(() {
        _csvPath = path;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift saved to tip log')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save log: $e')),
      );
    }
  }

  /// Returns true to overwrite the day, false to append a second
  /// shift, or null if the user cancels.
  Future<bool?> _askDuplicateDate() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entry Already Exists'),
        content: const Text(
          'The log already has an entry for today. Add this as a second '
          'shift, or replace today\'s entries?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Add Second Shift'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace Today'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCsv() async {
    final path = _csvPath;
    if (path == null) return;
    // OpenFilex works across platforms; `Process.run('open', ...)` was
    // macOS-only and unavailable on iOS/Android.
    final result = await OpenFilex.open(path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: ${result.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalTips = widget.totals.totalTips;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shift Totals', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _row('Credit Card Tips',
                      _money(widget.totals.creditCardTips)),
                  _row('Service Charge Tips',
                      _money(widget.totals.serviceChargeTips)),
                  _row('Net Sales', _money(widget.totals.sales)),
                  if (!widget.isSolo && widget.barbackCut > 0)
                    _row('Barback Tip-Out', _money(widget.barbackCut)),
                  const Divider(),
                  _row('Total Tips', _money(totalTips), bold: true),
                ],
              ),
            ),
          ),
          if (_result.hasNegativeLines)
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
                        'The barback tip-out is larger than this shift can '
                        'support, so some line items are negative. Go back '
                        'and lower the tip-out.',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_result.barbacks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Barbacks', style: theme.textTheme.titleMedium),
            ..._result.barbacks.entries.map(
              (e) => _personCard(e.key, e.value),
            ),
          ],
          const SizedBox(height: 8),
          Text('Bartenders', style: theme.textTheme.titleMedium),
          ..._result.bartenders.entries.map(
            (e) => _personCard(e.key, e.value),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _row(
                'Total Distributed',
                _money(_result.totalDistributed),
                bold: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _saveToCsv,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: Text(_saving ? 'Saving…' : 'Save to Tip Log'),
          ),
          if (_csvPath != null)
            TextButton.icon(
              onPressed: _openCsv,
              icon: const Icon(Icons.description),
              label: const Text('Open Tip Log'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyResults,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
            icon: const Icon(Icons.copy),
            label: const Text('Copy Results'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _shareResults,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Start New Shift'),
          ),
        ],
      ),
    );
  }

  Widget _personCard(String name, Map<String, double> pools) {
    final cc = pools['cc'] ?? 0;
    final sc = pools['sc'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Zero and negative rows are shown rather than hidden, so
            // the displayed lines always add up to the total.
            _row('Credit Card Tips', _money(cc)),
            _row('Service Charge Tips', _money(sc)),
            const Divider(),
            _row('Total', _money(cc + sc), bold: true),
          ],
        ),
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
