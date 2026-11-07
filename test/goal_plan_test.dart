import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yu_challenge/data/sqlite_store.dart';
import 'package:yu_challenge/data/store.dart';
import 'package:yu_challenge/model.dart';

void main() {
  var now = DateTime(2026, 11, 5, 10); // Thursday
  setUp(() => now = DateTime(2026, 11, 5, 10));

  Future<AppState> open([Store? store]) async {
    final state = AppState(store ?? MemoryStore(), clock: () => now);
    await state.load();
    return state;
  }

  String add(
    AppState s, {
    String title = 'Spacer',
    Set<int> days = const {1, 2, 3, 4, 5, 6, 7},
  }) {
    s.saveGoal(
      title: title,
      category: Category.ruch,
      target: 20,
      step: 5,
      unit: 'min',
      weekdays: days,
    );
    return s.activeGoals.last.id;
  }

  test('fresh install starts empty; weekdays control actual logging', () async {
    final s = await open();
    expect(s.managedGoals, isEmpty);
    final id = add(s, days: {1, 3, 5});
    expect(s.goals, isEmpty);
    expect(s.log(id).gained, 0);
    now = DateTime(2026, 11, 6, 4);
    s.refreshDay();
    expect(s.goals.single.id, id);
    expect(s.log(id).gained, 3);
    now = DateTime(2026, 11, 7, 10);
    s.refreshDay();
    expect(s.goals, isEmpty);
    expect(s.balance, 33);
  });

  test(
    'editing a started plan preserves today and historic keepsakes',
    () async {
      final s = await open();
      final id = add(s);
      for (var i = 0; i < 4; i++) {
        s.log(id);
      }
      expect(s.traces, [Category.ruch]);
      final effective = s.saveGoal(
        id: id,
        title: 'Czytanie',
        category: Category.nauka,
        target: 10,
        step: 2,
        unit: 'stron',
        weekdays: {5},
      );
      expect(effective, '2026-11-06');
      expect(s.goals.single.title, 'Spacer');
      expect(s.goals.single.target, 20);
      expect(s.earnedToday, 12);
      now = DateTime(2026, 11, 6, 10);
      s.refreshDay();
      expect(s.goals.single.title, 'Czytanie');
      expect(s.goals.single.target, 10);
      expect(s.log(id).gained, 2);
      expect(s.goals.single.progress, 2);
      expect(s.traces, [
        Category.ruch,
      ], reason: 'past training must not turn into reading');
    },
  );

  test(
    'editing before a first entry applies now, backfill uses the old step',
    () async {
      final s = await open();
      final id = add(s);
      now = DateTime(2026, 11, 7, 10);
      s.refreshDay();
      expect(
        s.saveGoal(
          id: id,
          title: 'Krótki spacer',
          category: Category.ruch,
          target: 10,
          step: 1,
          weekdays: {6},
        ),
        '2026-11-07',
      );
      expect(s.goals.single.target, 10);
      expect(s.log(id, day: '2026-11-05').gained, 3);
      expect(s.rewardFor('2026-11-05'), 3);
      expect(s.goals.single.progress, 0);
    },
  );

  test(
    'rest preserves earned progress, blocks entries and can be reversed',
    () async {
      final store = MemoryStore();
      final s = await open(store);
      final id = add(s);
      s.log(id);
      s.setRestToday(true);
      expect(s.log(id).gained, 0);
      expect(s.balance, 33);
      expect(s.goals.single.progress, 5);
      await s.flush();
      final loaded = await open(store);
      expect(loaded.isRestDay, isTrue);
      expect(loaded.balance, 33);
      loaded.setRestToday(false);
      expect(loaded.log(id).gained, 3);
      now = DateTime(2026, 11, 6, 4);
      loaded.refreshDay();
      expect(loaded.isRestDay, isFalse);
      expect(loaded.goals.single.progress, 0);
    },
  );

  test('a rest day with no entries stays empty after restart', () async {
    final store = MemoryStore();
    final s = await open(store);
    final id = add(s);
    s.setRestToday(true);
    expect(s.goals, isEmpty);
    expect(s.log(id).gained, 0);
    await s.flush();
    final loaded = await open(store);
    expect(loaded.isRestDay, isTrue);
    expect(loaded.goals, isEmpty);
    expect(loaded.balance, 30);
    loaded.setRestToday(false);
    expect(loaded.goals.single.id, id);
  });

  test(
    'archive frees a slot for tomorrow without changing a frozen plan',
    () async {
      final s = await open();
      final first = add(s, title: 'Pierwszy');
      add(s, title: 'Drugi');
      add(s, title: 'Trzeci');
      expect(s.canAddGoal, isFalse);
      expect(() => add(s), throwsStateError);
      s.log(first);
      s.archiveGoal(first);
      final replacement = add(s, title: 'Nowy');
      expect(s.goals.map((g) => g.id), contains(first));
      expect(s.goals.map((g) => g.id), isNot(contains(replacement)));
      expect(() => s.archiveGoal(first, archived: false), throwsStateError);
      now = DateTime(2026, 11, 6, 10);
      s.refreshDay();
      expect(s.goals.map((g) => g.id), isNot(contains(first)));
      expect(s.goals.map((g) => g.id), contains(replacement));
      expect(s.balance, 31);
    },
  );

  test('a task is completed only once, including backdated entries', () async {
    final s = await open();
    s.saveGoal(
      title: 'Umyć okno',
      category: Category.dom,
      target: 1,
      step: 1,
      deadline: '2026-11-08',
    );
    final id = s.activeGoals.single.id;
    now = DateTime(2026, 11, 6, 10);
    s.refreshDay();
    expect(s.log(id).gained, 12);
    expect(s.log(id, day: '2026-11-05').gained, 0);
    now = DateTime(2026, 11, 7, 10);
    s.refreshDay();
    expect(s.goals, isEmpty);
    expect(s.balance, 42);
  });

  test('invalid definitions cannot enter the store', () async {
    final s = await open();
    for (final n in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => s.saveGoal(
          title: 'Test',
          category: Category.ruch,
          target: n,
          step: 1,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () =>
          s.saveGoal(title: ' ', category: Category.ruch, target: 10, step: 1),
      throwsArgumentError,
    );
    expect(
      () => s.saveGoal(
        title: 'Test',
        category: Category.ruch,
        target: 10,
        step: 11,
      ),
      throwsArgumentError,
    );
    expect(
      () => s.saveGoal(
        title: 'Test',
        category: Category.ruch,
        target: 10,
        step: 1,
        weekdays: {},
      ),
      throwsArgumentError,
    );
    expect(
      () => s.saveGoal(
        title: 'Test',
        category: Category.ruch,
        target: 1,
        step: 1,
        deadline: '2026-11-04',
      ),
      throwsArgumentError,
    );
    expect(s.managedGoals, isEmpty);
  });

  test(
    'SQLite persists schedules, revisions and rest without losing purchases',
    () async {
      sqfliteFfiInit();
      final store = await SqliteStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(store.close);
      final s = await open(store);
      final id = add(s);
      s.log(id);
      s.build(BuildingType.garden);
      s.saveGoal(
        id: id,
        title: 'Spacer w piątki',
        category: Category.ruch,
        target: 40,
        step: 10,
        weekdays: {5},
      );
      s.setRestToday(true);
      await s.flush();
      final loaded = await open(store);
      expect(loaded.isRestDay, isTrue);
      expect(loaded.goals.single.target, 20);
      expect(loaded.built, {BuildingType.garden});
      expect(loaded.balance, 25);
      now = DateTime(2026, 11, 6, 10);
      loaded.refreshDay();
      expect(loaded.goals.single.target, 40);
      expect(loaded.goals.single.def.weekdays, {5});
    },
  );

  test(
    'version 1 migrates in place and preserves the existing island',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('yu-plan-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/legacy.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE goals(id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, target REAL NOT NULL, step REAL NOT NULL, unit TEXT NOT NULL, deadline TEXT, created_day TEXT NOT NULL, sort INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE plan_items(day TEXT NOT NULL, goal_id TEXT NOT NULL, target REAL NOT NULL, PRIMARY KEY(day, goal_id))',
            );
            await db.execute(
              'CREATE TABLE entries(id INTEGER PRIMARY KEY AUTOINCREMENT, goal_id TEXT NOT NULL, day TEXT NOT NULL, amount REAL NOT NULL, at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE purchases(building TEXT PRIMARY KEY, cost INTEGER NOT NULL, at INTEGER NOT NULL)',
            );
            await db.insert('goals', {
              'id': 'old',
              'title': 'Stary cel',
              'category': 'nauka',
              'target': 10,
              'step': 5,
              'unit': 'min',
              'created_day': '2026-11-05',
              'sort': 0,
            });
            await db.insert('plan_items', {
              'day': '2026-11-05',
              'goal_id': 'old',
              'target': 10,
            });
            await db.insert('entries', {
              'goal_id': 'old',
              'day': '2026-11-05',
              'amount': 10,
              'at': now.toUtc().millisecondsSinceEpoch,
            });
            await db.insert('purchases', {
              'building': 'library',
              'cost': 20,
              'at': now.toUtc().millisecondsSinceEpoch,
            });
          },
        ),
      );
      await legacy.close();
      final store = await SqliteStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(store.close);
      final s = await open(store);
      expect(s.balance, 22);
      expect(s.built, {BuildingType.library});
      expect(s.traces, [Category.nauka]);
      expect(s.goals.single.done, isTrue);
      expect(s.activeGoals.single.weekdays, {1, 2, 3, 4, 5, 6, 7});
      s.saveGoal(
        id: 'old',
        title: 'Nowa nazwa',
        category: Category.nauka,
        target: 15,
        step: 5,
        weekdays: {1, 3, 5},
      );
      s.setRestToday(true);
      await s.flush();
      final loaded = await open(store);
      expect(loaded.isRestDay, isTrue);
      expect(loaded.balance, 22);
      expect(loaded.activeGoals.single.title, 'Nowa nazwa');
      expect(loaded.goals.single.title, 'Stary cel');
    },
  );
}
