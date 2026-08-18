import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tip_out/main.dart';

/// Roster edits must survive backing out of a screen.
///
/// The roster used to be handed from Home to Tips to Team as a
/// constructor argument. Tips froze that list for its whole lifetime, so
/// stepping back and continuing again rebuilt the team screen from a
/// stale snapshot: people added were gone and deleted ones returned. The
/// next edit then wrote that stale list to disk, so the loss stuck.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> startShift(WidgetTester tester) async {
    // The default 800x600 test surface scrolls "Add New Person" out of
    // reach once the roster grows; give the roster room to render.
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
  }

  Future<void> addPerson(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.text('Add New Person'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add New Person'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, name);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  testWidgets('a person added survives going back and continuing again',
      (tester) async {
    await startShift(tester);
    await addPerson(tester, 'Dana');
    expect(find.text('Dana'), findsOneWidget);

    // Back to the tips screen, then forward again — the exact path that
    // used to resurrect the starter roster.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Dana'), findsOneWidget,
        reason: 'the added bartender must still be on the roster');
  });

  testWidgets('a deleted person stays deleted after going back',
      (tester) async {
    await startShift(tester);
    expect(find.text('Alice Johnson'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Alice Johnson'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Alice Johnson'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Alice Johnson'), findsNothing,
        reason: 'a deleted teammate must not come back');
  });

  testWidgets('edits made across two visits both survive', (tester) async {
    await startShift(tester);
    await addPerson(tester, 'Dana');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The second edit used to write the stale list back over the first.
    await addPerson(tester, 'Sam');

    expect(find.text('Dana'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });
}
