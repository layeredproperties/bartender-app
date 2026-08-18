import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tip_out/main.dart';
import 'package:tip_out/models/person.dart';
import 'package:tip_out/models/shift_draft.dart';
import 'package:tip_out/models/shift_totals.dart';
import 'package:tip_out/screens/barback_screen.dart';
import 'package:tip_out/screens/home_screen.dart';
import 'package:tip_out/screens/hours_screen.dart';
import 'package:tip_out/screens/results_screen.dart';
import 'package:tip_out/screens/team_screen.dart';
import 'package:tip_out/screens/tips_screen.dart';
import 'package:tip_out/services/tip_calculator.dart';

/// Captures the App Store screenshot set.
///
/// Each screen is rendered directly with prepared data rather than
/// tapped through from the home screen: the numbers on show are then
/// chosen rather than incidental, and a screenshot run can't fail
/// because a widget moved a few pixels.
///
/// Run with:
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshots_test.dart \
///     -d SIMULATOR_ID
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A believable Friday night rather than round numbers.
  const totals = ShiftTotals(
    creditCardTips: 1240.50,
    serviceChargeTips: 186.25,
    sales: 5400.00,
  );

  const roster = [
    Person(name: 'Michael', role: Role.bartender, isSelected: true, isUser: true),
    Person(name: 'Alice Johnson', role: Role.bartender, isSelected: true),
    Person(name: 'Bob Davis', role: Role.bartender, isSelected: true),
    Person(name: 'Charlie Miller', role: Role.barback, isSelected: true),
  ];

  const draft = ShiftDraft(
    totals: totals,
    userName: 'Michael',
    selectedPeople: roster,
    barbackCut: 162.00, // 3% of sales
    barbackMode: BarbackMode.percentageOfSales,
  );

  /// Wrap a screen in the real app shell so the theme, text scaling and
  /// AppSettings lookups all behave exactly as they do in the app.
  Widget shell(Widget screen) {
    return AppSettings(
      data: const AppSettingsData(
        userName: 'Michael',
        textScale: 1.0,
        roster: roster,
      ),
      setUserName: (_) {},
      setTextScale: (_, {bool persist = true}) {},
      setRoster: (_) {},
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: screen,
      ),
    );
  }

  Future<void> capture(WidgetTester tester, String name, Widget screen) async {
    await tester.pumpWidget(shell(screen));
    await tester.pumpAndSettle();
    // Let the first frame land before grabbing the surface.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Michael',
      'text_scale': 1.0,
    });
  });

  testWidgets('01 home', (tester) async {
    await capture(tester, '01_home', const HomeScreen());
  });

  testWidgets('02 shift totals', (tester) async {
    await tester.pumpWidget(shell(const TipsScreen(roster: roster)));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '1240.50');
    await tester.enterText(fields.at(1), '186.25');
    await tester.enterText(fields.at(2), '5400.00');
    // Dismiss the keyboard so it doesn't cover the Continue button.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02_shift_totals');
  });

  testWidgets('03 team', (tester) async {
    await capture(
      tester,
      '03_team',
      const TeamScreen(
        roster: roster,
        draft: ShiftDraft(totals: totals, userName: 'Michael'),
      ),
    );
  });

  testWidgets('04 barback', (tester) async {
    await tester.pumpWidget(shell(const BarbackScreen(
      draft: ShiftDraft(
        totals: totals,
        userName: 'Michael',
        selectedPeople: roster,
      ),
    )));
    await tester.pumpAndSettle();
    // An empty form shows "$0.00", which sells nothing. Pick a mode and
    // enter a rate so the screenshot shows the feature doing its job.
    await tester.tap(find.text('Percentage of Sales'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04_barback');
  });

  testWidgets('05 split method', (tester) async {
    await capture(tester, '05_split_method', const HoursScreen(draft: draft));
  });

  testWidgets('06 results', (tester) async {
    await capture(tester, '06_results', const ResultsScreen(draft: draft));
  });
}
