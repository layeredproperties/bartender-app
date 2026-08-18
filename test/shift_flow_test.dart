import 'package:tip_out/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end walks through the shift flow, covering the screen-level
/// bugs found in review.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  _locationFlow();

  /// Start a shift and land on the tips screen.
  Future<void> startShift(WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Shift'));
    await tester.pumpAndSettle();
  }

  Future<void> enterTips(WidgetTester tester, String amount) async {
    await tester.enterText(find.byType(TextFormField).first, amount);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  group('tips entry', () {
    testWidgets('accepts an amount typed with a comma and a dollar sign',
        (tester) async {
      // `double.tryParse('1,200.50')` is null, and the old `?? 0.0` ran
      // the whole shift against a $0.00 pool without saying anything.
      await startShift(tester);
      await enterTips(tester, r'$1,200.50');

      expect(find.text('Who worked with you?'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();

      expect(find.text('Results'), findsOneWidget);
      expect(find.text(r'$1200.50'), findsWidgets);
    });

    testWidgets('rejects text that is not an amount', (tester) async {
      await startShift(tester);
      await enterTips(tester, 'twelve hundred');

      expect(find.text('Enter an amount like 450.00'), findsOneWidget);
      expect(find.text('Who worked with you?'), findsNothing);
    });

    testWidgets('will not start a shift with no tips at all', (tester) async {
      await startShift(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter the credit card or service charge tips first'),
        findsOneWidget,
      );
      expect(find.text('Who worked with you?'), findsNothing);
    });
  });

  group('roster', () {
    testWidgets('refuses to add a name already on the roster', (tester) async {
      // Two people with the same name collapse into one line item and
      // one of them silently loses their share of the tips.
      await startShift(tester);
      await enterTips(tester, '450.00');

      await tester.tap(find.text('Add New Person'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Alice Johnson');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
        find.text('Alice Johnson is already on the roster'),
        findsOneWidget,
      );
      // Still on the dialog — nothing was added.
      expect(find.text('Add New Person'), findsWidgets);
    });

    testWidgets('duplicate check ignores case and surrounding space',
        (tester) async {
      await startShift(tester);
      await enterTips(tester, '450.00');

      await tester.tap(find.text('Add New Person'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '  alice johnson ');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
        find.text('alice johnson is already on the roster'),
        findsOneWidget,
      );
    });

    testWidgets('adds a person whose name is free', (tester) async {
      await startShift(tester);
      await enterTips(tester, '450.00');

      await tester.tap(find.text('Add New Person'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Dana');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Dana'), findsOneWidget);
    });

    testWidgets('an empty name is rejected without closing the dialog',
        (tester) async {
      await startShift(tester);
      await enterTips(tester, '450.00');

      await tester.tap(find.text('Add New Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name'), findsOneWidget);
    });
  });

  group('hours', () {
    testWidgets('blank hours on an hourly split are rejected', (tester) async {
      await startShift(tester);
      await enterTips(tester, '450.00');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hourly Split'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter hours greater than 0'), findsOneWidget);
    });

    testWidgets('hours typed with a comma decimal are accepted',
        (tester) async {
      await startShift(tester);
      await enterTips(tester, '450.00');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hourly Split'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '8,5');
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();

      expect(find.text('Results'), findsOneWidget);
    });
  });
}

/// The location picked on the tips screen has to survive the whole
/// Tips -> Team -> Hours -> Results chain and label the shift.
void _locationFlow() {
  group('location', () {
    testWidgets('can be added inline and labels the results', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Shift'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '450.00');
      await tester.pumpAndSettle();

      // No saved locations yet, so add one without leaving the screen.
      await tester.tap(find.byTooltip('Add a location'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'The Anchor Bar');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('The Anchor Bar'), findsWidgets);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calculate'));
      await tester.pumpAndSettle();

      // The results header carries date + venue.
      expect(find.textContaining('The Anchor Bar'), findsWidgets);
    });

    testWidgets('is optional — skipping it still works', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Shift'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '450.00');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Who worked with you?'), findsOneWidget);
    });

    testWidgets('rejects a duplicate location name', (tester) async {
      SharedPreferences.setMockInitialValues({
        'locations': ['The Anchor Bar'],
      });
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start Shift'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add a location'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'the anchor bar');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('the anchor bar is already on the list'), findsOneWidget);
    });
  });
}
