import 'package:flutter/material.dart';

import '../models/money.dart';
import '../models/person.dart';
import '../models/shift_draft.dart';
import 'results_screen.dart';

class HoursScreen extends StatefulWidget {
  final ShiftDraft draft;

  const HoursScreen({super.key, required this.draft});

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends State<HoursScreen> {
  bool _equalSplit = true;
  late final List<Person> _bartenders = widget.draft.bartenders;
  late final Map<String, TextEditingController> _hourControllers = {
    for (final person in _bartenders) person.name: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in _hourControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _continue() {
    Map<String, double>? hours;

    if (!_equalSplit) {
      // Without this guard, blank or zero hours would pay everyone
      // $0.00 and dump the entire pool on the remainder person.
      final invalid = <String>[];
      hours = {};
      for (final person in _bartenders) {
        final parsed = parseAmount(_hourControllers[person.name]!.text);
        if (parsed == null || !parsed.isFinite || parsed <= 0) {
          invalid.add(person.name);
        } else {
          hours[person.name] = parsed;
        }
      }

      if (invalid.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter hours greater than 0 for: ${invalid.join(', ')}',
            ),
          ),
        );
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          draft: widget.draft.copyWith(
            equalSplit: _equalSplit,
            hours: hours,
            clearHours: _equalSplit,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split Method'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _equalSplit,
              onChanged: (value) => setState(() => _equalSplit = value ?? true),
              // RadioListTile rather than a ListTile wrapped around a
              // Radio, so the whole row is the tap target — and so this
              // screen behaves like the barback screen's mode picker.
              child: const Column(
                children: [
                  Card(
                    child: RadioListTile<bool>(
                      value: true,
                      title: Text('Equal Split'),
                      subtitle: Text('Everyone gets the same amount'),
                    ),
                  ),
                  Card(
                    child: RadioListTile<bool>(
                      value: false,
                      title: Text('Hourly Split'),
                      subtitle: Text('Split based on hours worked'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (!_equalSplit) ...[
              const Text(
                'Enter hours worked for each bartender:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ..._bartenders.map((person) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _hourControllers[person.name],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: person.name,
                      hintText: 'e.g. 8.5',
                      prefixIcon: const Icon(Icons.schedule),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _continue,
              child: const Text('Calculate'),
            ),
          ],
        ),
      ),
    );
  }
}
