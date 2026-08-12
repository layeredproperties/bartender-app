import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/person.dart';

/// Persists the user's preferences and roster between launches.
class SettingsService {
  static const _kUserName = 'user_name';
  static const _kTextScale = 'text_scale';
  static const _kRoster = 'roster';

  static const String defaultUserName = 'You';
  static const double defaultTextScale = 1.0;
  static const double minTextScale = 0.8;
  static const double maxTextScale = 2.0;

  static Future<String> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kUserName)?.trim();
    return (name == null || name.isEmpty) ? defaultUserName : name;
  }

  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserName, name.trim());
  }

  static Future<double> loadTextScale() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble(_kTextScale) ?? defaultTextScale;
    return scale.clamp(minTextScale, maxTextScale);
  }

  static Future<void> saveTextScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _kTextScale,
      scale.clamp(minTextScale, maxTextScale),
    );
  }

  /// Load the saved roster, or a starter roster on first launch.
  static Future<List<Person>> loadRoster(String userName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRoster);

    if (raw == null || raw.isEmpty) {
      return _defaultRoster(userName);
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final people = decoded
          .map((e) => Person.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (people.isEmpty) return _defaultRoster(userName);
      // Keep the user's entry in sync with the saved name.
      return people
          .map((p) => p.isUser ? p.copyWith(name: userName) : p)
          .toList();
    } catch (_) {
      // A corrupt roster shouldn't brick the app.
      return _defaultRoster(userName);
    }
  }

  static Future<void> saveRoster(List<Person> roster) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(roster.map((p) => p.toJson()).toList());
    await prefs.setString(_kRoster, encoded);
  }

  static List<Person> _defaultRoster(String userName) => [
        Person(
          name: userName,
          role: Role.bartender,
          isSelected: true,
          isUser: true,
        ),
        Person(name: 'Alice Johnson', role: Role.bartender),
        Person(name: 'Bob Davis', role: Role.bartender),
        Person(name: 'Charlie Miller', role: Role.barback),
      ];
}
