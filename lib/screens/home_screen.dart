import 'package:flutter/material.dart';

import '../main.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'tips_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Reading from AppSettings means a rename in Settings is reflected
    // here (and in the roster passed to the calculator) immediately.
    final settings = AppSettings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tip Out'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Import Shift Data',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ImportScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Welcome, ${settings.data.userName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Clear last shift's selections so a new shift starts
                // from a clean slate (the user stays selected). The
                // screens ahead read the roster from AppSettings rather
                // than being handed a copy, so this is all they need.
                settings.setRoster(
                  settings.data.roster
                      .map((p) => p.copyWith(isSelected: p.isUser))
                      .toList(),
                );

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TipsScreen(),
                  ),
                );
              },
              child: const Text('Start Shift'),
            ),
          ],
        ),
      ),
    );
  }
}
