import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/person.dart';

/// The stored preferences, loaded in one pass at startup.
class StoredSettings {
  final String userName;
  final double textScale;
  final List<Person> roster;

  const StoredSettings({
    required this.userName,
    required this.textScale,
    required this.roster,
  });
}

/// Persists the user's preferences and roster between launches.
class SettingsService {
  static const _kUserName = 'user_name';
  static const _kTextScale = 'text_scale';
  static const _kRoster = 'roster';

  static const String defaultUserName = 'You';
  static const double defaultTextScale = 1.0;
  static const double minTextScale = 0.8;
  static const double maxTextScale = 2.0;

  /// Read every stored setting from a single [SharedPreferences]
  /// instance, rather than three sequential `getInstance()` round-trips
  /// on the startup path.
  static Future<StoredSettings> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final userName = _readUserName(prefs);
    return StoredSettings(
      userName: userName,
      textScale: _readTextScale(prefs),
      roster: _readRoster(prefs, userName),
    );
  }

  static Future<String> loadUserName() async =>
      _readUserName(await SharedPreferences.getInstance());

  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserName, name.trim());
  }

  static Future<double> loadTextScale() async =>
      _readTextScale(await SharedPreferences.getInstance());

  static Future<void> saveTextScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _kTextScale,
      scale.clamp(minTextScale, maxTextScale),
    );
  }

  /// Load the saved roster, or a starter roster on first launch.
  static Future<List<Person>> loadRoster(String userName) async =>
      _readRoster(await SharedPreferences.getInstance(), userName);

  static Future<void> saveRoster(List<Person> roster) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(roster.map((p) => p.toJson()).toList());
    await prefs.setString(_kRoster, encoded);
  }

  static String _readUserName(SharedPreferences prefs) {
    final name = prefs.getString(_kUserName)?.trim();
    return (name == null || name.isEmpty) ? defaultUserName : name;
  }

  static double _readTextScale(SharedPreferences prefs) {
    final scale = prefs.getDouble(_kTextScale) ?? defaultTextScale;
    return scale.clamp(minTextScale, maxTextScale);
  }

  static List<Person> _readRoster(SharedPreferences prefs, String userName) {
    final raw = prefs.getString(_kRoster);
    if (raw == null || raw.isEmpty) return _defaultRoster(userName);

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final people = decoded
          .map((e) => Person.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (people.isEmpty) return _defaultRoster(userName);
      // Keep the user's entry in sync with the saved name.
      final synced = people
          .map((p) => p.isUser ? p.copyWith(name: userName) : p)
          .toList();
      return ensureUniqueNames(synced);
    } catch (_) {
      // A corrupt roster shouldn't brick the app.
      return _defaultRoster(userName);
    }
  }

  /// Give every person a distinct name, suffixing repeats as "Mike (2)".
  ///
  /// The tip-out is keyed by name end to end — two people called Mike
  /// would collapse into one line item and silently misallocate money —
  /// so the roster screens now reject duplicates. This migrates rosters
  /// saved before that rule existed. The user's own entry is never
  /// renamed; it wins the original name.
  static List<Person> ensureUniqueNames(List<Person> roster) {
    final taken = <String>{};
    // Reserve the user's name first so a duplicate elsewhere is the one
    // that gets suffixed.
    for (final person in roster.where((p) => p.isUser)) {
      taken.add(person.name.toLowerCase());
    }

    return roster.map((person) {
      if (person.isUser) return person;
      var name = person.name;
      var suffix = 2;
      while (!taken.add(name.toLowerCase())) {
        name = '${person.name} ($suffix)';
        suffix++;
      }
      return name == person.name ? person : person.copyWith(name: name);
    }).toList();
  }

  static List<Person> _defaultRoster(String userName) => [
        Person(
          name: userName,
          role: Role.bartender,
          isSelected: true,
          isUser: true,
        ),
        const Person(name: 'Alice Johnson', role: Role.bartender),
        const Person(name: 'Bob Davis', role: Role.bartender),
        const Person(name: 'Charlie Miller', role: Role.barback),
      ];
}
