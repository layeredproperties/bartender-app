import 'package:tip_out/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Settings are loaded from disk on startup, so the tests need an
    // in-memory preference store.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App launches and shows home screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    // Settle the async settings load before asserting.
    await tester.pumpAndSettle();

    expect(find.text('Tip Out'), findsOneWidget);
    expect(find.text('Start Shift'), findsOneWidget);
  });

  testWidgets('saved name is shown on the home screen', (tester) async {
    SharedPreferences.setMockInitialValues({'user_name': 'Michael'});

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Michael'), findsOneWidget);
  });

  testWidgets('renaming in settings updates the home screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Michael');
    await tester.tap(find.text('Save Name'));
    await tester.pumpAndSettle();

    // Back to home: the rename must have propagated out of Settings.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Michael'), findsOneWidget);
  });
}
