import 'package:flutter/material.dart';

import 'models/person.dart';
import 'screens/home_screen.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

/// App-wide settings shared with every screen via [AppSettings].
///
/// Holding the roster here (rather than in `HomeScreen`) is what keeps
/// a rename in Settings propagating to the roster entry used by the
/// calculator.
class AppSettingsData {
  final String userName;
  final double textScale;
  final List<Person> roster;

  const AppSettingsData({
    required this.userName,
    required this.textScale,
    required this.roster,
  });
}

class AppSettings extends InheritedWidget {
  final AppSettingsData data;
  final ValueChanged<String> setUserName;
  final ValueChanged<double> setTextScale;
  final ValueChanged<List<Person>> setRoster;

  const AppSettings({
    super.key,
    required this.data,
    required this.setUserName,
    required this.setTextScale,
    required this.setRoster,
    required super.child,
  });

  static AppSettings of(BuildContext context) {
    final settings = context.dependOnInheritedWidgetOfExactType<AppSettings>();
    assert(settings != null, 'No AppSettings found in context');
    return settings!;
  }

  @override
  bool updateShouldNotify(AppSettings oldWidget) =>
      data.userName != oldWidget.data.userName ||
      data.textScale != oldWidget.data.textScale ||
      !identical(data.roster, oldWidget.data.roster);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double _textScale = SettingsService.defaultTextScale;
  String _userName = SettingsService.defaultUserName;
  List<Person> _roster = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userName = await SettingsService.loadUserName();
    final textScale = await SettingsService.loadTextScale();
    final roster = await SettingsService.loadRoster(userName);
    if (!mounted) return;
    setState(() {
      _userName = userName;
      _textScale = textScale;
      _roster = roster;
      _loaded = true;
    });
  }

  void _setTextScale(double scale) {
    final clamped = scale.clamp(
      SettingsService.minTextScale,
      SettingsService.maxTextScale,
    );
    setState(() => _textScale = clamped);
    SettingsService.saveTextScale(clamped);
  }

  void _setUserName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _userName = trimmed;
      // Keep the roster's user entry in sync so the calculator's
      // remainder lookup still matches after a rename.
      _roster = _roster
          .map((p) => p.isUser ? p.copyWith(name: trimmed) : p)
          .toList();
    });
    SettingsService.saveUserName(trimmed);
    SettingsService.saveRoster(_roster);
  }

  void _setRoster(List<Person> roster) {
    setState(() => _roster = List<Person>.from(roster));
    SettingsService.saveRoster(_roster);
  }

  @override
  Widget build(BuildContext context) {
    // AppSettings must sit ABOVE MaterialApp: pushed routes are built by
    // the Navigator, so an InheritedWidget placed at `home:` would be
    // invisible to Settings and every other pushed screen.
    return AppSettings(
      data: AppSettingsData(
        userName: _userName,
        textScale: _textScale,
        roster: _roster,
      ),
      setUserName: _setUserName,
      setTextScale: _setTextScale,
      setRoster: _setRoster,
      child: MaterialApp(
        title: 'Bartender Tip-Out',
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
        ),
        // Global font scaling for accessibility
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(_textScale),
            ),
            child: child!,
          );
        },
        home: !_loaded
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : const HomeScreen(),
      ),
    );
  }
}
