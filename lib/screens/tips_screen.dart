import 'package:flutter/material.dart';
import '../models/person.dart';
import '../models/shift_totals.dart';
import 'team_screen.dart';

class TipsScreen extends StatefulWidget {
  final List<Person> roster;

  const TipsScreen({super.key, required this.roster});

  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen> {
  final _ccController = TextEditingController();
  final _scController = TextEditingController();
  final _salesController = TextEditingController();

  @override
  void dispose() {
    _ccController.dispose();
    _scController.dispose();
    _salesController.dispose();
    super.dispose();
  }

  double _parseAmount(String value) {
    return double.tryParse(value) ?? 0.0;
  }

  void _continue() {
    final totals = ShiftTotals(
      creditCardTips: _parseAmount(_ccController.text),
      serviceChargeTips: _parseAmount(_scController.text),
      sales: _parseAmount(_salesController.text),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamScreen(
          roster: widget.roster,
          totals: totals,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Shift Totals'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _buildAmountField(
              controller: _ccController,
              label: 'Credit Card Tips',
              icon: Icons.credit_card,
              hint: 'e.g. 450.00',
            ),
            const SizedBox(height: 16),
            _buildAmountField(
              controller: _scController,
              label: 'Service Charge Tips',
              icon: Icons.receipt_long,
              hint: 'e.g. 75.50',
            ),
            const SizedBox(height: 16),
            _buildAmountField(
              controller: _salesController,
              label: 'Net Sales (optional)',
              icon: Icons.storefront,
              hint: 'e.g. 5000.00',
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _continue,
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

  Widget _buildAmountField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        prefixText: '\$ ',
      ),
    );
  }
}