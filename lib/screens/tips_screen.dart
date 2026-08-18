import 'package:flutter/material.dart';

import '../main.dart';
import '../models/money.dart';
import '../models/shift_draft.dart';
import '../models/shift_totals.dart';
import 'team_screen.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen({super.key});

  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen> {
  final _formKey = GlobalKey<FormState>();
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

  /// Reject anything [parseAmount] can't read instead of silently
  /// treating it as $0.00 — a mistyped total used to run the whole shift
  /// against an empty pool with no warning.
  String? _validateAmount(String? value) =>
      parseAmount(value ?? '') == null ? 'Enter an amount like 450.00' : null;

  void _continue() {
    if (!_formKey.currentState!.validate()) return;

    final totals = ShiftTotals(
      creditCardTips: parseAmount(_ccController.text)!,
      serviceChargeTips: parseAmount(_scController.text)!,
      sales: parseAmount(_salesController.text)!,
    );

    if (totals.totalTips <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the credit card or service charge tips first'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamScreen(
          draft: ShiftDraft(
            totals: totals,
            userName: AppSettings.of(context).data.userName,
          ),
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                child: const Text('Continue'),
              ),
            ],
          ),
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
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: _validateAmount,
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
