import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:macro_spending_analyzer/models.dart';
import 'package:macro_spending_analyzer/store.dart';

void main() {
  sqfliteFfiInit();
  late SpendingStore store;
  setUp(() async {
    store = SpendingStore(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: SpendingStore.options,
      ),
    );
  });
  tearDown(() async => store.db.close());

  Future<void> addMonthlySalary(DateTime start) => store.add(
    business: 'Employer',
    category: 'Salary',
    cents: 10000,
    date: start,
    kind: EntryKind.income,
    recurring: true,
  );

  test('starts empty and preserves backdated receipts', () async {
    expect(await store.entries(), isEmpty);
    await store.add(
      business: 'Market',
      category: 'Food',
      cents: 1234,
      date: DateTime(2023, 2, 1),
      kind: EntryKind.expense,
      recurring: false,
    );
    expect((await store.entries()).single.cents, 1234);
    expect((await store.entries()).single.date, DateTime(2023, 2, 1));
  });

  test(
    'monthly posting is idempotent and stopping preserves history',
    () async {
      await addMonthlySalary(DateTime(2024, 1, 31));
      await store.materialize(DateTime(2024, 3, 31));
      await store.materialize(DateTime(2024, 3, 31));
      expect((await store.entries()).length, 3);
      await store.stopRule((await store.rules()).single.id);
      await store.materialize(DateTime(2024, 6, 30));
      expect((await store.entries()).length, 3);
      expect(await store.rules(), isEmpty);
    },
  );

  test('future start date posts nothing until it is due', () async {
    await addMonthlySalary(DateTime(2024, 5, 10));
    await store.materialize(DateTime(2024, 5, 9));
    expect(await store.entries(), isEmpty);
    await store.materialize(DateTime(2024, 5, 10));
    expect((await store.entries()).single.date, DateTime(2024, 5, 10));
  });

  test('update edits an entry in place', () async {
    await store.add(
      business: 'Markt',
      category: 'Food',
      cents: 100,
      date: DateTime(2024, 1, 1),
      kind: EntryKind.expense,
      recurring: false,
    );
    final id = (await store.entries()).single.id;
    await store.update(
      id,
      business: ' Market ',
      category: 'Groceries',
      cents: 250,
      date: DateTime(2024, 1, 2),
      kind: EntryKind.income,
    );
    final entry = (await store.entries()).single;
    expect(entry.business, 'Market');
    expect(entry.category, 'Groceries');
    expect(entry.cents, 250);
    expect(entry.date, DateTime(2024, 1, 2));
    expect(entry.kind, EntryKind.income);
    expect(
      () => store.update(
        id,
        business: 'Market',
        category: 'Food',
        cents: 0,
        date: DateTime(2024, 1, 2),
        kind: EntryKind.expense,
      ),
      throwsArgumentError,
    );
  });

  test('update keeps the due date of monthly entries', () async {
    await addMonthlySalary(DateTime(2024, 1, 15));
    await store.materialize(DateTime(2024, 1, 31));
    final entry = (await store.entries()).single;
    expect(entry.ruleId, isNotNull);
    await store.update(
      entry.id,
      business: 'Employer',
      category: 'Salary',
      cents: 12000,
      date: DateTime(2024, 1, 20),
      kind: EntryKind.income,
    );
    await store.materialize(DateTime(2024, 1, 31));
    final entries = await store.entries();
    expect(entries.single.date, DateTime(2024, 1, 15));
    expect(entries.single.cents, 12000);
  });

  test('deleted monthly entries stay deleted and can be restored', () async {
    await addMonthlySalary(DateTime(2024, 1, 1));
    await store.materialize(DateTime(2024, 2, 1));
    final deleted = (await store.entries()).first;
    await store.delete(deleted.id);
    await store.materialize(DateTime(2024, 2, 1));
    expect(
      (await store.entries()).map((e) => e.id),
      isNot(contains(deleted.id)),
    );
    expect((await store.entries()).length, 1);
    await store.restore(deleted.id);
    expect((await store.entries()).length, 2);
  });

  test('upgrades a version 1 database without losing data', () async {
    final dir = await Directory.systemTemp.createTemp('spending_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = path.join(dir.path, 'v1.db');
    final v1 = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => SpendingStore.createBaseSchema(db),
      ),
    );
    await v1.insert('entries', {
      'business': 'Market',
      'category': 'Food',
      'cents': 500,
      'date': '2024-01-01',
      'kind': 'expense',
    });
    await v1.close();

    final upgraded = SpendingStore(
      await databaseFactoryFfi.openDatabase(
        file,
        options: SpendingStore.options,
      ),
    );
    addTearDown(upgraded.db.close);
    expect(await upgraded.db.getVersion(), SpendingStore.version);
    final entry = (await upgraded.entries()).single;
    expect(entry.business, 'Market');
    await upgraded.delete(entry.id);
    expect(await upgraded.entries(), isEmpty);
  });
}
