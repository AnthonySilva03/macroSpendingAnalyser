import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class SpendingStore {
  SpendingStore(this.db);
  final Database db;

  static const version = 2;

  static OpenDatabaseOptions get options => OpenDatabaseOptions(
    version: version,
    onCreate: createSchema,
    onUpgrade: migrate,
  );

  static Future<SpendingStore> open() async => SpendingStore(
    await databaseFactory.openDatabase(
      path.join(await getDatabasesPath(), 'macro_spending.db'),
      options: options,
    ),
  );

  // New databases build the v1 schema and run every migration, so fresh
  // installs and upgraded installs always end up with the same schema.
  static Future<void> createSchema(Database db, int version) async {
    await createBaseSchema(db);
    await migrate(db, 1, version);
  }

  @visibleForTesting
  static Future<void> createBaseSchema(Database db) async {
    await db.execute('''CREATE TABLE entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      business TEXT NOT NULL, category TEXT NOT NULL,
      cents INTEGER NOT NULL CHECK(cents > 0), date TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('expense','income')),
      rule_id INTEGER, UNIQUE(rule_id, date))''');
    await db.execute('''CREATE TABLE rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      business TEXT NOT NULL, category TEXT NOT NULL,
      cents INTEGER NOT NULL CHECK(cents > 0), start TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('expense','income')),
      active INTEGER NOT NULL DEFAULT 1)''');
    await db.execute('CREATE INDEX entries_date ON entries(date)');
  }

  static Future<void> migrate(Database db, int from, int to) async {
    // v2: soft delete, so deleted monthly entries are not re-posted by
    // materialize (the UNIQUE(rule_id, date) row must stay in place).
    if (from < 2) {
      await db.execute(
        'ALTER TABLE entries ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> materialize(DateTime now) => db.transaction((txn) async {
    for (final row in await txn.query('rules', where: 'active = 1')) {
      final rule = MonthlyRule.fromRow(row);
      for (final date in monthlyDates(rule.start, now)) {
        await txn.insert('entries', {
          'business': rule.business,
          'category': rule.category,
          'cents': rule.cents,
          'date': dateKey(date),
          'kind': rule.kind.name,
          'rule_id': rule.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  });

  Future<List<LedgerEntry>> entries() async => (await db.query(
    'entries',
    where: 'deleted = 0',
    orderBy: 'date DESC, id DESC',
  )).map(LedgerEntry.fromRow).toList();

  Future<List<MonthlyRule>> rules() async => (await db.query(
    'rules',
    where: 'active = 1',
    orderBy: 'id DESC',
  )).map(MonthlyRule.fromRow).toList();

  static void _validate(String business, String category, int cents) {
    if (business.trim().isEmpty || category.trim().isEmpty || cents <= 0) {
      throw ArgumentError('Enter a business, category, and positive amount.');
    }
  }

  Future<void> add({
    required String business,
    required String category,
    required int cents,
    required DateTime date,
    required EntryKind kind,
    required bool recurring,
  }) async {
    _validate(business, category, cents);
    await db.insert(recurring ? 'rules' : 'entries', {
      'business': business.trim(),
      'category': category.trim(),
      'cents': cents,
      recurring ? 'start' : 'date': dateKey(date),
      'kind': kind.name,
    });
  }

  /// Updates an entry. The date of a monthly-rule entry is kept, because
  /// moving it would let materialize post the original date again.
  Future<void> update(
    int id, {
    required String business,
    required String category,
    required int cents,
    required DateTime date,
    required EntryKind kind,
  }) async {
    _validate(business, category, cents);
    await db.rawUpdate(
      '''UPDATE entries SET business = ?, category = ?, cents = ?, kind = ?,
         date = CASE WHEN rule_id IS NULL THEN ? ELSE date END
         WHERE id = ?''',
      [business.trim(), category.trim(), cents, kind.name, dateKey(date), id],
    );
  }

  Future<void> delete(int id) => _setDeleted(id, true);

  Future<void> restore(int id) => _setDeleted(id, false);

  Future<void> _setDeleted(int id, bool deleted) async {
    await db.update(
      'entries',
      {'deleted': deleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> stopRule(int id) async {
    await db.update('rules', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }
}
