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

  /// Where this shift was worked. Optional, and deliberately blank each
  /// time rather than remembering the last one — a bartender working two
  /// bars shouldn't have last night's venue silently attached to
  /// tonight's numbers.
  String? _location;

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
            location: _location,
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
              const SizedBox(height: 16),
              _buildLocationField(context),
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

  /// The location picker, plus a button to add one without leaving the
  /// screen — the same shape as "Add New Person" on the roster.
  Widget _buildLocationField(BuildContext context) {
    final locations = AppSettings.of(context).data.locations;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: locations.contains(_location) ? _location : null,
            decoration: const InputDecoration(
              labelText: 'Where did you work? (optional)',
              prefixIcon: Icon(Icons.place_outlined),
              border: OutlineInputBorder(),
            ),
            hint: Text(
              locations.isEmpty ? 'Add a location' : 'No location',
            ),
            items: [
              const DropdownMenuItem<String?>(
                child: Text('No location'),
              ),
              for (final place in locations)
                DropdownMenuItem<String?>(value: place, child: Text(place)),
            ],
            onChanged: (value) => setState(() => _location = value),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _addLocation,
          icon: const Icon(Icons.add),
          tooltip: 'Add a location',
        ),
      ],
    );
  }

  Future<void> _addLocation() async {
    final settings = AppSettings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _AddLocationDialog(existing: settings.data.locations),
    );
    if (name == null || !mounted) return;
    settings.setLocations([...settings.data.locations, name]);
    setState(() => _location = name);
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

/// Prompts for a new location.
///
/// A widget rather than an inline builder so it owns its
/// [TextEditingController] and disposes it after the route's exit
/// animation — the same reason the add-person dialog is one.
class _AddLocationDialog extends StatefulWidget {
  final List<String> existing;

  const _AddLocationDialog({required this.existing});

  @override
  State<_AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<_AddLocationDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a name');
      return;
    }
    // Case-insensitive, so the log doesn't end up split between
    // "Anchor Bar" and "anchor bar".
    final taken = widget.existing
        .any((e) => e.trim().toLowerCase() == name.toLowerCase());
    if (taken) {
      setState(() => _errorText = '$name is already on the list');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a Location'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. The Anchor Bar',
          border: const OutlineInputBorder(),
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
