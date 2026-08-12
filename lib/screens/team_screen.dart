// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import '../main.dart';
import '../models/person.dart';
import '../models/shift_totals.dart';
import 'barback_screen.dart';
import 'hours_screen.dart';
import 'results_screen.dart';

class TeamScreen extends StatefulWidget {
  final List<Person> roster;
  final ShiftTotals totals;

  const TeamScreen({super.key, required this.roster, required this.totals});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  bool isSolo = false;

  void _toggle(Person person) {
    if (person.isUser) return; // Can't uncheck the user
    setState(() {
      if (isSolo) {
        isSolo = false; // Uncheck solo if they pick someone
      }
      person.isSelected = !person.isSelected;
    });
  }

  void _toggleSolo() {
    setState(() {
      isSolo = !isSolo;
      if (isSolo) {
        // Uncheck everyone except the user if solo is selected
        for (var p in widget.roster) {
          if (!p.isUser) {
            p.isSelected = false;
          }
        }
      }
    });
  }

  void _showAddPersonDialog() {
    final nameController = TextEditingController();
    Role selectedRole = Role.bartender;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Person'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Role>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: Role.values.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(role.name.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedRole = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      setState(() {
                        widget.roster.add(
                          Person(name: name, role: selectedRole),
                        );
                      });
                      // Sync back to the app-wide roster so the addition
                      // survives past this shift (widget.roster is a
                      // separate list from AppSettings' copy).
                      AppSettings.of(this.context).setRoster(widget.roster);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeletePersonDialog(Person person) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Person'),
          content: Text('Remove ${person.name} from the roster?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  widget.roster.remove(person);
                });
                // Sync back to the app-wide roster so the deletion
                // survives past this shift (widget.roster is a
                // separate list from AppSettings' copy).
                AppSettings.of(this.context).setRoster(widget.roster);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _continue() {
    final userName = widget.roster
        .where((p) => p.isUser)
        .map((p) => p.name)
        .firstOrNull ??
        'You';

    if (isSolo) {
      // Solo shift - go straight to results
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            totals: widget.totals,
            selectedPeople: [],
            isSolo: true,
            userName: userName,
          ),
        ),
      );
    } else {
      final selected = widget.roster.where((p) => p.isSelected).toList();
      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one person')),
        );
        return;
      }

      // Check if any barbacks are selected
      final hasBarback = selected.any((p) => p.role == Role.barback);
      if (hasBarback) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BarbackScreen(
              roster: widget.roster,
              totals: widget.totals,
              selectedPeople: selected,
              userName: userName,
            ),
          ),
        );
      } else {
        // No barbacks - go to hours screen to ask about split method
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HoursScreen(
              roster: widget.roster,
              totals: widget.totals,
              selectedPeople: selected,
              barbackCut: 0.0,
              userName: userName,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Who worked with you?'),
      ),
      body: ListView(
        children: [
          // Solo shift row
          ListTile(
            tileColor: isSolo ? Colors.blue.withValues(alpha: 0.1) : null,
            onTap: _toggleSolo,
            leading: Checkbox(
              value: isSolo,
              onChanged: (_) => _toggleSolo(),
            ),
            title: const Text('Solo shift'),
            subtitle: const Text('No one else worked'),
          ),
          const Divider(),
          // Roster rows
          ...widget.roster.map((person) {
            return ListTile(
              tileColor: person.isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
              onTap: () => _toggle(person),
              leading: Checkbox(
                value: person.isSelected,
                onChanged: (_) => _toggle(person),
              ),
              title: Text(person.name),
              subtitle: Text(person.role.name.toUpperCase()),
              trailing: person.isUser
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _showDeletePersonDialog(person),
                      tooltip: 'Delete ${person.name}',
                    ),
            );
          }),
          // Add New Person button
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add New Person'),
            onTap: _showAddPersonDialog,
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _continue,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18),
          ),
          child: const Text('Continue'),
        ),
      ),
    );
  }
}