import 'package:flutter/material.dart';

import '../models/money.dart';
import '../models/shift_draft.dart';
import '../services/tip_calculator.dart';
import '../widgets/money_row.dart';
import 'hours_screen.dart';

/// The wording for each payout mode, kept next to the enum instead of
/// spread across three parallel switch statements on the screen.
extension on BarbackMode {
  String get inputLabel => switch (this) {
        BarbackMode.flatAmount => 'Amount (\$)',
        BarbackMode.percentageOfTips => 'Percentage of Tips (%)',
        BarbackMode.percentageOfSales => 'Percentage of Sales (%)',
      };

  String get inputHint => switch (this) {
        BarbackMode.flatAmount => '0.00',
        BarbackMode.percentageOfTips => 'e.g. 20',
        BarbackMode.percentageOfSales => 'e.g. 5',
      };

  IconData get icon => this == BarbackMode.flatAmount
      ? Icons.attach_money
      : Icons.percent;

  /// Which shift figure the percentage applies to. Flat amounts don't
  /// depend on one, but total tips is still the useful context.
  bool get usesSales => this == BarbackMode.percentageOfSales;

  String summary(double value) => switch (this) {
        BarbackMode.flatAmount => formatMoney(value),
        BarbackMode.percentageOfTips =>
          '${value.toStringAsFixed(1)}% of tips',
        BarbackMode.percentageOfSales =>
          '${value.toStringAsFixed(1)}% of sales',
      };
}

class BarbackScreen extends StatefulWidget {
  final ShiftDraft draft;

  const BarbackScreen({super.key, required this.draft});

  @override
  State<BarbackScreen> createState() => _BarbackScreenState();
}

class _BarbackScreenState extends State<BarbackScreen> {
  BarbackMode _mode = BarbackMode.flatAmount;
  double _value = 0.0;
  bool _invalidInput = false;
  final TextEditingController _valueController = TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  double get _barbackCut => TipCalculator.calculateBarbackCut(
        totals: widget.draft.totals,
        mode: _mode,
        value: _value,
      );

  /// True when the user picked "% of sales" but never entered net sales
  /// on the tips screen — the cut silently computes to $0.00 otherwise.
  bool get _missingSales =>
      _mode.usesSales && widget.draft.totals.sales <= 0;

  void _onModeChanged(BarbackMode value) {
    setState(() {
      _mode = value;
      _value = 0.0;
      _invalidInput = false;
      _valueController.clear();
    });
  }

  void _onValueChanged(String text) {
    final parsed = parseAmount(text);
    setState(() {
      _invalidInput = parsed == null;
      _value = parsed ?? 0.0;
    });
  }

  void _continue() {
    if (_invalidInput) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a number like 20 or 15.50')),
      );
      return;
    }
    if (_missingSales) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Go back and enter net sales, or pick another mode'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HoursScreen(
          draft: widget.draft.copyWith(
            barbackCut: _barbackCut,
            barbackMode: _mode,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = widget.draft.totals;
    final names = widget.draft.barbacks.map((b) => b.name).join(', ');
    final contextAmount =
        _mode.usesSales ? totals.sales : totals.totalTips;
    final contextLabel = _mode.usesSales ? 'Total sales' : 'Total tips';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barback Payout'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text('Barbacks: $names', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),

            // Mode selection
            Card(
              child: RadioGroup<BarbackMode>(
                groupValue: _mode,
                onChanged: (value) => _onModeChanged(value!),
                child: const Column(
                  children: [
                    RadioListTile<BarbackMode>(
                      title: Text('Flat Amount'),
                      subtitle: Text('Enter a dollar amount'),
                      value: BarbackMode.flatAmount,
                    ),
                    RadioListTile<BarbackMode>(
                      title: Text('Percentage of Tips'),
                      subtitle: Text('Enter a % of total tips'),
                      value: BarbackMode.percentageOfTips,
                    ),
                    RadioListTile<BarbackMode>(
                      title: Text('Percentage of Sales'),
                      subtitle: Text('Enter a % of total sales'),
                      value: BarbackMode.percentageOfSales,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Value display
            Text(
              'Barback Cut: ${_mode.summary(_value)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Calculated amount: ${formatMoney(_barbackCut)}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Number input
            TextField(
              controller: _valueController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _mode.inputLabel,
                hintText: _mode.inputHint,
                border: const OutlineInputBorder(),
                prefixIcon: Icon(_mode.icon),
                errorText: _invalidInput ? 'Enter a number' : null,
              ),
              onChanged: _onValueChanged,
            ),
            const SizedBox(height: 8),

            // Context info
            Text(
              '$contextLabel: ${formatMoney(contextAmount)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            if (_missingSales) ...[
              const SizedBox(height: 16),
              const WarningCard(
                'No net sales were entered for this shift, so a percentage '
                'of sales works out to \$0.00. Go back and add net sales, or '
                'choose a flat amount or a percentage of tips.',
              ),
            ],
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _continue,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
