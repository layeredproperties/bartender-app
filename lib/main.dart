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

  /// The bars this user works. Empty until they add one.
  final List<String> locations;

  const AppSettingsData({
    required this.userName,
    required this.textScale,
    required this.roster,
    this.locations = const [],
  });
}

class AppSettings extends InheritedWidget {
  final AppSettingsData data;
  final ValueChanged<String> setUserName;
  final ValueChanged<List<Person>> setRoster;
  final ValueChanged<List<String>> setLocations;

  /// Update the live text scale. Pass `persist: false` while a gesture
  /// is in flight — the slider fires this on every frame, and writing to
  /// shared preferences at 60 Hz means a platform-channel round trip per
  /// frame for a value the user hasn't settled on yet.
  final void Function(double scale, {bool persist}) setTextScale;

  const AppSettings({
    super.key,
    required this.data,
    required this.setUserName,
    required this.setTextScale,
    required this.setRoster,
    required this.setLocations,
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
      !identical(data.roster, oldWidget.data.roster) ||
      !identical(data.locations, oldWidget.data.locations);
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
  List<String> _locations = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // One preferences instance, one pass — the old version awaited three
    // separate loads in series before the first frame could render.
    final stored = await SettingsService.loadAll();
    if (!mounted) return;
    setState(() {
      _userName = stored.userName;
      _textScale = stored.textScale;
      _roster = stored.roster;
      _locations = stored.locations;
      _loaded = true;
    });
  }

  void _setTextScale(double scale, {bool persist = true}) {
    final clamped = scale.clamp(
      SettingsService.minTextScale,
      SettingsService.maxTextScale,
    );
    if (clamped != _textScale) {
      setState(() => _textScale = clamped);
    }
    if (persist) SettingsService.saveTextScale(clamped);
  }

  void _setUserName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _userName = trimmed;
      // Keep the roster's user entry in sync so the calculator's
      // remainder lookup still matches after a rename, and re-run the
      // uniqueness pass in case the new name collides with a teammate.
      _roster = SettingsService.ensureUniqueNames(
        _roster.map((p) => p.isUser ? p.copyWith(name: trimmed) : p).toList(),
      );
    });
    SettingsService.saveUserName(trimmed);
    SettingsService.saveRoster(_roster);
  }

  void _setLocations(List<String> locations) {
    setState(() => _locations = List<String>.from(locations));
    SettingsService.saveLocations(_locations);
  }

  void _setRoster(List<Person> roster) {
    setState(() => _roster = List<Person>.from(roster));
    SettingsService.saveRoster(_roster);
  }

  /// Shared button sizing, so the six call sites that each repeated
  /// `padding: symmetric(vertical: 16)` + `fontSize: 18` don't have to.
  static const ButtonStyle _primaryButtonStyle = ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 16)),
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 18)),
  );

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
        locations: _locations,
      ),
      setUserName: _setUserName,
      setTextScale: _setTextScale,
      setRoster: _setRoster,
      setLocations: _setLocations,
      child: MaterialApp(
        title: 'Tip Out',
        // The debug ribbon would otherwise sit in the corner of every
        // App Store screenshot.
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          elevatedButtonTheme:
              const ElevatedButtonThemeData(style: _primaryButtonStyle),
          outlinedButtonTheme:
              const OutlinedButtonThemeData(style: _primaryButtonStyle),
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
