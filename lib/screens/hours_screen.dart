import 'package:flutter/material.dart';
import '../models/person.dart';
import '../models/shift_totals.dart';
import 'results_screen.dart';

class HoursScreen extends StatefulWidget {
  final List<Person> roster;
  final ShiftTotals totals;
  final List<Person> selectedPeople;
  final double barbackCut;
  final String userName;

  const HoursScreen({
    super.key,
    required this.roster,
    required this.totals,
    required this.selectedPeople,
    required this.barbackCut,
    this.userName = 'You',
  });

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends State<HoursScreen> {
  bool _equalSplit = true;
  final Map<String, TextEditingController> _hourControllers = {};

  @override
  void initState() {
    super.initState();
    // Initialize hour controllers for all selected bartenders
    for (final person in widget.selectedPeople) {
      if (person.role == Role.bartender) {
        _hourControllers[person.name] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _hourControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _parseHours(String value) {
    return double.tryParse(value.trim()) ?? 0.0;
  }

  Map<String, double> _collectHours() => {
        for (final person in widget.selectedPeople)
          if (person.role == Role.bartender)
            person.name: _parseHours(_hourControllers[person.name]?.text ?? ''),
      };

  void _continue() {
    Map<String, double>? hours;

    if (!_equalSplit) {
      hours = _collectHours();

      // Without this guard, blank or zero hours would pay everyone
      // $0.00 and dump the entire pool on the remainder person.
      final invalid = hours.entries
          .where((e) => !e.value.isFinite || e.value <= 0)
          .map((e) => e.key)
          .toList();
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
          totals: widget.totals,
          selectedPeople: widget.selectedPeople,
          isSolo: false,
          barbackCut: widget.barbackCut,
          equalSplit: _equalSplit,
          hours: hours,
          userName: widget.userName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bartenders = widget.selectedPeople
        .where((p) => p.role == Role.bartender)
        .toList();

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
            // Equal split option
            RadioGroup<bool>(
              groupValue: _equalSplit,
              onChanged: (value) {
                setState(() {
                  _equalSplit = value ?? true;
                });
              },
              child: const Column(
                children: [
                  Card(
                    child: ListTile(
                      leading: Radio<bool>(value: true),
                      title: Text('Equal Split'),
                      subtitle: Text('Everyone gets the same amount'),
                    ),
                  ),
                  // Hourly split option
                  Card(
                    child: ListTile(
                      leading: Radio<bool>(value: false),
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
              ...bartenders.map((person) {
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
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Calculate'),
            ),
          ],
        ),
      ),
    );
  }
}