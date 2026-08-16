import 'package:flutter/material.dart';

import '../main.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      // Seed from the live values so reopening Settings doesn't reset
      // the name or snap the text scale back to its default.
      _nameController.text = AppSettings.of(context).data.userName;
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final textScale = settings.data.textScale;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Your Name', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter your name',
              helperText: 'Used for your line item and the tip log',
            ),
            onSubmitted: settings.setUserName,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name cannot be empty')),
                  );
                  return;
                }
                settings.setUserName(name);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Name saved as "$name"')),
                );
              },
              child: const Text('Save Name'),
            ),
          ),
          const Divider(height: 32),
          Text('Text Size', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Smaller text',
                onPressed: textScale <= SettingsService.minTextScale
                    ? null
                    : () => settings.setTextScale(textScale - 0.1),
              ),
              Expanded(
                child: Slider(
                  value: textScale,
                  min: SettingsService.minTextScale,
                  max: SettingsService.maxTextScale,
                  divisions: 12,
                  label: '${(textScale * 100).round()}%',
                  // Live preview while dragging, one write when the
                  // gesture ends — this used to hit shared preferences
                  // on every frame of the drag.
                  onChanged: (value) =>
                      settings.setTextScale(value, persist: false),
                  onChangeEnd: settings.setTextScale,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Larger text',
                onPressed: textScale >= SettingsService.maxTextScale
                    ? null
                    : () => settings.setTextScale(textScale + 0.1),
              ),
            ],
          ),
          Center(
            child: Text('Preview — ${(textScale * 100).round()}%'),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () =>
                  settings.setTextScale(SettingsService.defaultTextScale),
              child: const Text('Reset to Default'),
            ),
          ),
        ],
      ),
    );
  }
}
