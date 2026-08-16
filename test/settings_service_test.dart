import 'package:tip_out/models/person.dart';
import 'package:tip_out/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ensureUniqueNames', () {
    test('leaves an already-unique roster untouched', () {
      const roster = [
        Person(name: 'You', role: Role.bartender, isUser: true),
        Person(name: 'Alice', role: Role.bartender),
        Person(name: 'Bob', role: Role.barback),
      ];

      final result = SettingsService.ensureUniqueNames(roster);

      expect(result.map((p) => p.name), ['You', 'Alice', 'Bob']);
    });

    test('suffixes duplicates saved before the rule existed', () {
      const roster = [
        Person(name: 'You', role: Role.bartender, isUser: true),
        Person(name: 'Mike', role: Role.bartender),
        Person(name: 'Mike', role: Role.bartender),
        Person(name: 'Mike', role: Role.barback),
      ];

      final result = SettingsService.ensureUniqueNames(roster);

      expect(result.map((p) => p.name), ['You', 'Mike', 'Mike (2)', 'Mike (3)']);
    });

    test('matches case-insensitively', () {
      const roster = [
        Person(name: 'You', role: Role.bartender, isUser: true),
        Person(name: 'Mike', role: Role.bartender),
        Person(name: 'mike', role: Role.bartender),
      ];

      final result = SettingsService.ensureUniqueNames(roster);

      expect(result.map((p) => p.name), ['You', 'Mike', 'mike (2)']);
    });

    test('the user keeps their name; the teammate is renamed', () {
      const roster = [
        Person(name: 'Mike', role: Role.bartender),
        Person(name: 'Mike', role: Role.bartender, isUser: true),
      ];

      final result = SettingsService.ensureUniqueNames(roster);

      expect(result[1].name, 'Mike');
      expect(result[1].isUser, isTrue);
      expect(result[0].name, 'Mike (2)');
    });

    test('preserves role and selection', () {
      const roster = [
        Person(name: 'Mike', role: Role.bartender, isSelected: true),
        Person(name: 'Mike', role: Role.barback, isSelected: true),
      ];

      final result = SettingsService.ensureUniqueNames(roster);

      expect(result[1].name, 'Mike (2)');
      expect(result[1].role, Role.barback);
      expect(result[1].isSelected, isTrue);
    });
  });

  group('loadAll', () {
    test('returns defaults on first launch', () async {
      final stored = await SettingsService.loadAll();

      expect(stored.userName, SettingsService.defaultUserName);
      expect(stored.textScale, SettingsService.defaultTextScale);
      expect(stored.roster.where((p) => p.isUser).length, 1);
    });

    test('reads back what was saved', () async {
      await SettingsService.saveUserName('Michael');
      await SettingsService.saveTextScale(1.4);
      await SettingsService.saveRoster(const [
        Person(name: 'Michael', role: Role.bartender, isUser: true),
        Person(name: 'Dana', role: Role.barback),
      ]);

      final stored = await SettingsService.loadAll();

      expect(stored.userName, 'Michael');
      expect(stored.textScale, 1.4);
      expect(stored.roster.map((p) => p.name), ['Michael', 'Dana']);
    });

    test('clamps an out-of-range text scale', () async {
      await SettingsService.saveTextScale(99);
      expect((await SettingsService.loadAll()).textScale,
          SettingsService.maxTextScale);
    });

    test('falls back to a starter roster when the saved one is corrupt',
        () async {
      SharedPreferences.setMockInitialValues({'roster': 'not json'});

      final stored = await SettingsService.loadAll();

      expect(stored.roster, isNotEmpty);
      expect(stored.roster.where((p) => p.isUser).length, 1);
    });

    test('de-duplicates a roster saved before the uniqueness rule',
        () async {
      SharedPreferences.setMockInitialValues({
        'user_name': 'Michael',
        'roster': '[{"name":"Michael","role":"bartender","isSelected":true,'
            '"isUser":true},'
            '{"name":"Mike","role":"bartender","isSelected":false,'
            '"isUser":false},'
            '{"name":"Mike","role":"bartender","isSelected":false,'
            '"isUser":false}]',
      });

      final stored = await SettingsService.loadAll();

      expect(stored.roster.map((p) => p.name).toSet().length,
          stored.roster.length);
    });
  });
}
