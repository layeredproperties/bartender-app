import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../models/logged_shift.dart';
import '../models/money.dart';
import '../models/pools.dart';
import '../models/shift_draft.dart';
import '../models/tip_out_result.dart';
import '../services/csv_export_service.dart';
import '../services/tip_calculator.dart';
import '../widgets/money_row.dart';

class ResultsScreen extends StatefulWidget {
  final ShiftDraft draft;

  const ResultsScreen({super.key, required this.draft});

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

  /// All calculation lives in [TipCalculator] so it can be unit tested;
  /// this screen only renders the result.
  TipOutResult _calculate() {
    final draft = widget.draft;
    return TipCalculator.calculateShift(
      totals: draft.totals,
      // Names are unique by construction — the roster screen rejects
      // duplicates — so they're passed straight through. Silently
      // de-duplicating here is what used to hide the collision.
      bartenderNames: draft.bartenders.map((p) => p.name).toList(),
      barbackNames: draft.barbacks.map((p) => p.name).toList(),
      userName: draft.userName,
      isSolo: draft.isSolo,
      barbackCut: draft.barbackCut,
      barbackMode: draft.barbackMode,
      equalSplit: draft.equalSplit,
      hours: draft.hours,
    );
  }

  String _buildShareText() {
    final totals = widget.draft.totals;
    final buffer = StringBuffer()
      ..writeln('Tip-Out Results')
      ..writeln('Total Tips: ${formatMoney(totals.totalTips)}')
      ..writeln(
        'CC: ${formatMoney(totals.creditCardTips)}  '
        'SC: ${formatMoney(totals.serviceChargeTips)}',
      )
      ..writeln();

    void writeGroup(String heading, Map<String, Pools> people) {
      if (people.isEmpty) return;
      buffer.writeln('$heading:');
      people.forEach((name, pools) {
        buffer.writeln(
          '  $name — CC ${formatMoney(pools.cc)}, '
          'SC ${formatMoney(pools.sc)}',
        );
      });
      buffer.writeln();
    }

    writeGroup('Barbacks', _result.barbacks);
    writeGroup('Bartenders', _result.bartenders);

    return buffer.toString();
  }

  Future<void> _copyResults() async {
    // Clipboard works on every platform; the old implementation shelled
    // out to `pbcopy`, which crashes on iOS and Android.
    await Clipboard.setData(ClipboardData(text: _buildShareText()));
    if (!mounted) return;
    _notify('Results copied to clipboard');
  }

  /// Shares a small CSV file (in addition to the human-readable text)
  /// so a teammate who receives it can import it straight into their
  /// own tip log via the Home screen's Import action, instead of
  /// retyping the numbers.
  Future<void> _shareResults() async {
    try {
      final path = await CsvExportService.writeShareableFile(
        timestamp: DateTime.now(),
        totals: widget.draft.totals,
        result: _result,
        barbackCut: widget.draft.barbackCut,
      );
      await Share.shareXFiles(
        [XFile(path, mimeType: 'text/csv')],
        text: _buildShareText(),
        subject: 'Tip-Out Results',
      );
    } catch (e) {
      if (!mounted) return;
      _notify('Could not share results: $e');
    }
  }

  /// Saving is explicit rather than a side effect of opening this
  /// screen, and reports success or failure to the user.
  Future<void> _saveToCsv() async {
    if (_saving) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    try {
      // Which of today's own shifts, if any, this save might replace.
      final existing = await CsvExportService.localShiftsForDate(now);
      _SaveAction action = const _SaveAction.append();
      if (existing.isNotEmpty) {
        if (!mounted) return;
        final choice = await _askSaveAction(existing);
        if (choice == null) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        action = choice;
      }

      final replaceKey = action.replaceKey;
      final path = replaceKey == null
          ? await CsvExportService.appendShift(
              timestamp: now,
              totals: widget.draft.totals,
              result: _result,
              barbackCut: widget.draft.barbackCut,
            )
          : await CsvExportService.replaceShift(
              totalsRowLine: replaceKey,
              timestamp: now,
              totals: widget.draft.totals,
              result: _result,
              barbackCut: widget.draft.barbackCut,
            );

      if (!mounted) return;
      setState(() {
        _csvPath = path;
        _saving = false;
      });
      _notify('Shift saved to tip log');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('Could not save log: $e');
    }
  }

  /// Ask whether this is another shift or a redo of a specific one.
  ///
  /// Each shift already saved today is offered individually, identified
  /// by the time it was saved and what it paid out. A single "Replace
  /// Today" button used to take every shift on the date with it, so
  /// fixing one half of a double silently destroyed the other.
  ///
  /// Returns null if the user cancels.
  Future<_SaveAction?> _askSaveAction(List<LoggedShift> existing) {
    final single = existing.length == 1;
    return showDialog<_SaveAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(single
            ? 'You already saved a shift today'
            : 'You already saved ${existing.length} shifts today'),
        children: [
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Add as a new shift'),
            subtitle: Text(single
                ? 'Keeps the shift you already saved'
                : 'Keeps all ${existing.length}'),
            onTap: () =>
                Navigator.pop(dialogContext, const _SaveAction.append()),
          ),
          const Divider(height: 1),
          for (final shift in existing)
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text('Replace the ${shift.displayTime} shift'),
              subtitle: Text('${formatMoney(shift.totalTips)} in tips'),
              onTap: () => Navigator.pop(
                dialogContext,
                _SaveAction.replace(shift.totalsRowLine),
              ),
            ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(dialogContext),
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
      _notify('Could not open file: ${result.message}');
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final totals = draft.totals;

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
                  MoneyRow(
                      'Credit Card Tips', formatMoney(totals.creditCardTips)),
                  MoneyRow('Service Charge Tips',
                      formatMoney(totals.serviceChargeTips)),
                  MoneyRow('Net Sales', formatMoney(totals.sales)),
                  if (!draft.isSolo && draft.barbackCut > 0)
                    MoneyRow('Barback Tip-Out', formatMoney(draft.barbackCut)),
                  const Divider(),
                  MoneyRow('Total Tips', formatMoney(totals.totalTips),
                      bold: true),
                ],
              ),
            ),
          ),
          // A shift with no bartenders distributes nothing. The team
          // screen blocks it, but say so plainly rather than showing a
          // screen of $0.00 lines if it ever gets here.
          if (_result.bartenders.isEmpty && totals.totalTips > 0)
            const WarningCard(
              'No bartenders were selected, so there is nobody to split '
              'these tips between. Go back and select who worked.',
            ),
          if (_result.hasNegativeLines)
            const WarningCard(
              'The barback tip-out is larger than this shift can support, '
              'so some line items are negative. Go back and lower the '
              'tip-out.',
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
              child: MoneyRow(
                'Total Distributed',
                formatMoney(_result.totalDistributed),
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
            icon: const Icon(Icons.copy),
            label: const Text('Copy Results'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _shareResults,
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

  Widget _personCard(String name, Pools pools) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // Zero and negative rows are shown rather than hidden, so
            // the displayed lines always add up to the total.
            MoneyRow('Credit Card Tips', formatMoney(pools.cc)),
            MoneyRow('Service Charge Tips', formatMoney(pools.sc)),
            const Divider(),
            MoneyRow('Total', formatMoney(pools.total), bold: true),
          ],
        ),
      ),
    );
  }
}

/// What to do when the tip log already holds shifts for today.
class _SaveAction {
  /// The "Shift Totals" row of the shift being redone, or null to add
  /// this one alongside what's already there.
  final String? replaceKey;

  const _SaveAction.append() : replaceKey = null;
  const _SaveAction.replace(this.replaceKey);
}
