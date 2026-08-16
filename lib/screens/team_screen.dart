import 'package:flutter/material.dart';

import '../main.dart';
import '../models/person.dart';
import '../models/shift_draft.dart';
import 'barback_screen.dart';
import 'hours_screen.dart';
import 'results_screen.dart';

class TeamScreen extends StatefulWidget {
  final List<Person> roster;
  final ShiftDraft draft;

  const TeamScreen({super.key, required this.roster, required this.draft});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  /// A local copy: [Person] is immutable and the screen swaps entries
  /// with `copyWith` rather than reaching into the shared roster and
  /// flipping fields on objects other screens are also holding.
  late List<Person> _roster = List<Person>.from(widget.roster);
  bool _isSolo = false;

  void _publishRoster() => AppSettings.of(context).setRoster(_roster);

  void _replace(Person person, Person updated) {
    final index = _roster.indexOf(person);
    if (index != -1) _roster[index] = updated;
  }

  void _toggle(Person person) {
    if (person.isUser) return; // Can't uncheck the user
    setState(() {
      if (_isSolo) {
        _isSolo = false; // Uncheck solo if they pick someone
      }
      _replace(person, person.copyWith(isSelected: !person.isSelected));
    });
  }

  void _toggleSolo() {
    setState(() {
      _isSolo = !_isSolo;
      if (_isSolo) {
        // Uncheck everyone except the user if solo is selected
        _roster = _roster
            .map((p) => p.isUser ? p : p.copyWith(isSelected: false))
            .toList();
      }
    });
  }

  /// True when [name] is already on the roster (ignoring case), which is
  /// not allowed: the whole tip-out is keyed by name, so two people
  /// called Mike collapse into a single line item and one of them
  /// silently loses their share.
  bool _nameTaken(String name, {Person? except}) {
    final candidate = name.trim().toLowerCase();
    return _roster.any(
      (p) => p != except && p.name.trim().toLowerCase() == candidate,
    );
  }

  Future<void> _showAddPersonDialog() async {
    final person = await showDialog<Person>(
      context: context,
      builder: (dialogContext) => _AddPersonDialog(isNameTaken: _nameTaken),
    );

    if (person == null || !mounted) return;
    setState(() => _roster = [..._roster, person]);
    // Sync back to the app-wide roster so the addition survives past
    // this shift.
    _publishRoster();
  }

  Future<void> _showDeletePersonDialog(Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Person'),
        content: Text('Remove ${person.name} from the roster?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _roster = _roster.where((p) => p != person).toList());
    _publishRoster();
  }

  void _continue() {
    if (_isSolo) {
      // Solo shift - go straight to results
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            draft: widget.draft.copyWith(isSolo: true, selectedPeople: const []),
          ),
        ),
      );
      return;
    }

    final selected = _roster.where((p) => p.isSelected).toList();
    if (selected.isEmpty) {
      _warn('Please select at least one person');
      return;
    }

    final draft = widget.draft.copyWith(selectedPeople: selected);
    if (draft.bartenders.isEmpty) {
      // Every pool is split among bartenders, so a barback-only shift
      // has nobody to distribute to and would report $0.00 across the
      // board without saying why.
      _warn('Select at least one bartender — barbacks are paid out of the '
          'bartenders\' share');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => draft.barbacks.isNotEmpty
            // Barbacks selected: ask what they're owed first.
            ? BarbackScreen(draft: draft)
            : HoursScreen(draft: draft),
      ),
    );
  }

  void _warn(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final highlight =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Who worked with you?'),
      ),
      body: ListView(
        children: [
          // Solo shift row
          ListTile(
            tileColor: _isSolo ? highlight : null,
            onTap: _toggleSolo,
            leading: Checkbox(
              value: _isSolo,
              onChanged: (_) => _toggleSolo(),
            ),
            title: const Text('Solo shift'),
            subtitle: const Text('No one else worked'),
          ),
          const Divider(),
          // Roster rows
          ..._roster.map((person) {
            return ListTile(
              tileColor: person.isSelected ? highlight : null,
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
          child: const Text('Continue'),
        ),
      ),
    );
  }
}

/// The "Add New Person" dialog.
///
/// A widget rather than an inline `StatefulBuilder` so it owns its
/// [TextEditingController]: the controller has to outlive the route's
/// exit animation, which a `dispose()` next to the `await showDialog`
/// call does not, and it must actually be disposed, which the original
/// inline version never did.
class _AddPersonDialog extends StatefulWidget {
  /// Reports whether a name is already on the roster.
  final bool Function(String name) isNameTaken;

  const _AddPersonDialog({required this.isNameTaken});

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _nameController = TextEditingController();
  Role _role = Role.bartender;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Enter a name');
      return;
    }
    if (widget.isNameTaken(name)) {
      setState(() => _errorText = '$name is already on the roster');
      return;
    }
    Navigator.pop(context, Person(name: name, role: _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Person'),
      // Scrollable so the fields still fit at the largest text size the
      // Settings screen offers.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              decoration: InputDecoration(
                labelText: 'Name',
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Role>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: Role.values
                  .map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.name.toUpperCase()),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              },
            ),
          ],
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
