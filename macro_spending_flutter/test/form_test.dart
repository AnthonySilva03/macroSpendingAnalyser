import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macro_spending_analyzer/main.dart';
import 'package:macro_spending_analyzer/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('invalid receipt stays open and does not create a transaction', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: SpendingStore.options,
      ),
    ))!;
    final store = SpendingStore(db);
    await tester.pumpWidget(
      MaterialApp(home: EntryForm(store: store, recurring: false)),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'Market');
    await tester.enterText(find.byType(TextFormField).at(1), 'Food');
    await tester.enterText(find.byType(TextFormField).at(2), 'abc');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a positive amount with up to two decimal places'),
      findsOneWidget,
    );
    expect(await tester.runAsync(store.entries), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
