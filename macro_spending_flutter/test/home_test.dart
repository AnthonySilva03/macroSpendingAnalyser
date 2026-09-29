import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_spending_analyzer/main.dart';
import 'package:macro_spending_analyzer/models.dart';
import 'package:macro_spending_analyzer/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late SpendingStore store;

  Future<void> add(
    String business,
    String category,
    int cents, {
    EntryKind kind = EntryKind.expense,
    DateTime? date,
  }) => store.add(
    business: business,
    category: category,
    cents: cents,
    date: date ?? DateTime.now(),
    kind: kind,
    recurring: false,
  );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(openStore: () async => store)),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    // The no-isolate factory completes inside the widget test's fake async zone.
    store = SpendingStore(
      await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: SpendingStore.options,
      ),
    );
  });
  tearDown(() async => store.db.close());

  testWidgets('overview ignores scheduled entries', (tester) async {
    await add('Employer', 'Salary', 10000, kind: EntryKind.income);
    await add('Market', 'Food', 3000);
    await add(
      'Future Co',
      'Rent',
      99999,
      date: DateTime.now().add(const Duration(days: 40)),
    );
    await pumpHome(tester);
    expect(find.text('\$70.00'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Future Co'), findsNothing);
  });

  testWidgets('statistics merge categories that differ only by case', (
    tester,
  ) async {
    await add('Market', 'food', 1000);
    await add('Bakery', 'Food', 2000);
    await pumpHome(tester);
    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Food · \$30.00 · 100%'), findsOneWidget);
    expect(find.textContaining('food ·'), findsNothing);
  });

  testWidgets('swipe deletes an entry and undo restores it', (tester) async {
    await add('Market', 'Food', 1000);
    await pumpHome(tester);
    await tester.drag(find.text('Market'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Market'), findsNothing);
    expect(await store.entries(), isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Market'), findsOneWidget);
  });

  testWidgets('tapping an entry opens it for editing', (tester) async {
    await add('Markt', 'Food', 1000);
    await pumpHome(tester);
    await tester.tap(find.text('Markt'));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'Market');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Market'), findsOneWidget);
    expect((await store.entries()).single.business, 'Market');
  });
}
