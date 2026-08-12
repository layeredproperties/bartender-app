import 'package:flutter/material.dart';
import '../models/person.dart';
import '../models/shift_totals.dart';
import '../services/tip_calculator.dart';
import 'hours_screen.dart';

class BarbackScreen extends StatefulWidget {
  final List<Person> roster;
  final ShiftTotals totals;
  final List<Person> selectedPeople;
  final String userName;

  const BarbackScreen({
    super.key,
    required this.roster,
    required this.totals,
    required this.selectedPeople,
    this.userName = 'You',
  });

  @override
  State<BarbackScreen> createState() => _BarbackScreenState();
}

class _BarbackScreenState extends State<BarbackScreen> {
  BarbackMode _mode = BarbackMode.flatAmount;
  double _value = 0.0;
  final TextEditingController _valueController = TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  double get _barbackCut {
    return TipCalculator.calculateBarbackCut(
      totals: widget.totals,
      mode: _mode,
      value: _value,
    );
  }

  String get _valueLabel {
    switch (_mode) {
      case BarbackMode.flatAmount:
        return '\$${_value.toStringAsFixed(2)}';
      case BarbackMode.percentageOfTips:
        return '${_value.toStringAsFixed(1)}% of tips';
      case BarbackMode.percentageOfSales:
        return '${_value.toStringAsFixed(1)}% of sales';
    }
  }

  String get _inputLabel {
    switch (_mode) {
      case BarbackMode.flatAmount:
        return 'Amount (\$)';
      case BarbackMode.percentageOfTips:
        return 'Percentage of Tips (%)';
      case BarbackMode.percentageOfSales:
        return 'Percentage of Sales (%)';
    }
  }

  String get _inputHint {
    switch (_mode) {
      case BarbackMode.flatAmount:
        return '0.00';
      case BarbackMode.percentageOfTips:
        return 'e.g. 20';
      case BarbackMode.percentageOfSales:
        return 'e.g. 5';
    }
  }

  void _onModeChanged(BarbackMode value) {
    setState(() {
      _mode = value;
      _value = 0.0;
      _valueController.clear();
    });
  }

  void _onValueChanged(String text) {
    final parsed = double.tryParse(text);
    setState(() {
      _value = parsed ?? 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final barbacks = widget.selectedPeople
        .where((p) => p.role == Role.barback)
        .toList();

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
            Text(
              'Barbacks: ${barbacks.map((b) => b.name).join(', ')}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),

            // Mode selection
            Card(
              child: RadioGroup<BarbackMode>(
                groupValue: _mode,
                onChanged: (value) {
                  _onModeChanged(value!);
                },
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
              'Barback Cut: $_valueLabel',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Calculated amount: \$${_barbackCut.toStringAsFixed(2)}',
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
                labelText: _inputLabel,
                hintText: _inputHint,
                border: const OutlineInputBorder(),
                prefixIcon: _mode == BarbackMode.flatAmount
                    ? const Icon(Icons.attach_money)
                    : const Icon(Icons.percent),
              ),
              onChanged: _onValueChanged,
            ),
            const SizedBox(height: 8),

            // Context info
            if (_mode == BarbackMode.percentageOfTips)
              Text(
                'Total tips: \$${widget.totals.totalTips.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              )
            else if (_mode == BarbackMode.percentageOfSales)
              Text(
                'Total sales: \$${widget.totals.sales.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              )
            else
              Text(
                'Total tips: \$${widget.totals.totalTips.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HoursScreen(
                      roster: widget.roster,
                      totals: widget.totals,
                      selectedPeople: widget.selectedPeople,
                      barbackCut: _barbackCut,
                      userName: widget.userName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}