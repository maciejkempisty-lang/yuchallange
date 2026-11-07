import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'records.dart';
import 'store.dart';

class SqliteStore implements Store {
  SqliteStore._(this._db);

  final Database _db;

  static Future<SqliteStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await f.getDatabasesPath(), 'yu_challenge.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return SqliteStore._(db);
  }

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE goals(
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          target REAL NOT NULL,
          step REAL NOT NULL,
          unit TEXT NOT NULL,
          deadline TEXT,
          created_day TEXT NOT NULL,
          sort INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE plan_items(
          day TEXT NOT NULL,
          goal_id TEXT NOT NULL,
          target REAL NOT NULL,
          PRIMARY KEY(day, goal_id)
        )''')
      ..execute('''
        CREATE TABLE entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          goal_id TEXT NOT NULL,
          day TEXT NOT NULL,
          amount REAL NOT NULL,
          at INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX entries_day ON entries(day)')
      ..execute('''
        CREATE TABLE purchases(
          building TEXT PRIMARY KEY,
          cost INTEGER NOT NULL,
          at INTEGER NOT NULL
        )''');
    await batch.commit(noResult: true);
    await _upgrade(db, 1, version);
  }

  static Future<void> _upgrade(Database db, int oldVersion, int version) async {
    if (oldVersion >= 2) return;
    final batch = db.batch()
      ..execute(
        'ALTER TABLE goals ADD COLUMN weekdays INTEGER NOT NULL DEFAULT 127',
      )
      ..execute(
        'ALTER TABLE goals ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
      )
      ..execute('''
        CREATE TABLE goal_revisions(
          id TEXT NOT NULL,
          effective_day TEXT NOT NULL,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          target REAL NOT NULL,
          step REAL NOT NULL,
          unit TEXT NOT NULL,
          deadline TEXT,
          created_day TEXT NOT NULL,
          sort INTEGER NOT NULL,
          weekdays INTEGER NOT NULL,
          archived INTEGER NOT NULL,
          PRIMARY KEY(id, effective_day)
        )''')
      ..execute('CREATE TABLE rest_days(day TEXT PRIMARY KEY)');
    await batch.commit(noResult: true);
  }

  @override
  Future<StoredData> load() async => StoredData(
    goals: (await _db.query(
      'goals',
      orderBy: 'sort',
    )).map(GoalDef.fromMap).toList(),
    plan: (await _db.query('plan_items')).map(PlanItem.fromMap).toList(),
    entries: (await _db.query(
      'entries',
      orderBy: 'id',
    )).map(Entry.fromMap).toList(),
    purchases: (await _db.query(
      'purchases',
      orderBy: 'at',
    )).map(Purchase.fromMap).toList(),
    revisions: (await _db.query(
      'goal_revisions',
      orderBy: 'effective_day',
    )).map(GoalRevision.fromMap).toList(),
    restDays: {
      for (final row in await _db.query('rest_days')) row['day']! as String,
    },
  );

  @override
  Future<void> addGoals(List<GoalDef> goals) async {
    final batch = _db.batch();
    for (final g in goals) {
      batch.insert('goals', g.toMap());
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> addPlan(List<PlanItem> items) async {
    final batch = _db.batch();
    for (final item in items) {
      batch.insert(
        'plan_items',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> addEntry(Entry entry) => _db.insert('entries', entry.toMap());

  @override
  Future<void> addPurchase(Purchase purchase) =>
      _db.insert('purchases', purchase.toMap());

  @override
  Future<void> saveRevision(GoalRevision revision) => _db.insert(
    'goal_revisions',
    revision.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> setRestDay(String day, bool rest) async {
    if (rest) {
      await _db.insert('rest_days', {
        'day': day,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.delete('rest_days', where: 'day = ?', whereArgs: [day]);
    }
  }

  Future<void> close() => _db.close();
}
