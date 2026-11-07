import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yu_challenge/data/day.dart';
import 'package:yu_challenge/data/sqlite_store.dart';
import 'package:yu_challenge/data/store.dart';
import 'package:yu_challenge/model.dart';

import 'fixtures.dart';

void main() {
  // Thursday; the seeded task is due on Sunday 2026-11-08.
  var now = DateTime(2026, 11, 5, 10);

  Future<AppState> open([Store? store]) async {
    final db = store ?? MemoryStore();
    if ((await db.load()).goals.isEmpty) await seedPrototype(db);
    final state = AppState(db, clock: () => now);
    await state.load();
    return state;
  }

  setUp(() => now = DateTime(2026, 11, 5, 10));

  test('the daily pool is shared by the planned goals and capped', () async {
    final s = await open();
    expect(s.balance, 30);
    for (var i = 0; i < 4; i++) {
      expect(s.log('pompki').gained, 1);
    }
    expect(s.log('pompki').gained, 0, reason: 'goal already done');
    expect(s.earnedToday, 4);
    s.log('biurko');
    for (var i = 0; i < 3; i++) {
      s.log('hiszpanski');
    }
    expect(s.earnedToday, 12);
    expect(s.balance, 42);
  });

  test('a new plan day starts at 4:00, not at midnight', () async {
    final s = await open();
    now = DateTime(2026, 11, 5, 23, 30);
    s.log('pompki');
    now = DateTime(2026, 11, 6, 2);
    expect(s.refreshDay(), isFalse);
    s.log('pompki');
    expect(
      s.goals.first.progress,
      100,
      reason: '2:00 still counts for Thursday',
    );

    now = DateTime(2026, 11, 6, 4, 30);
    expect(s.refreshDay(), isTrue);
    expect(s.today, '2026-11-06');
    expect(s.goals.first.progress, 0);
    expect(s.earnedToday, 0);
    expect(s.balance, 32, reason: 'yesterday\'s sparks stay earned');
  });

  test('a finished task is rewarded once and leaves later plans', () async {
    final s = await open();
    expect(s.log('biurko').gained, 4);
    expect(s.log('biurko').gained, 0);

    now = DateTime(2026, 11, 6, 10);
    s.refreshDay();
    expect(s.goals.map((g) => g.id), ['pompki', 'hiszpanski']);
    expect(s.log('pompki').gained, 1, reason: 'two goals: 6 sparks each');
    expect(s.log('pompki').gained, 2);
    expect(s.balance, 37);
  });

  test(
    'entries can be added up to 48 hours back, into that day\'s pool',
    () async {
      final s = await open();
      now = DateTime(2026, 11, 7, 10);
      s.refreshDay();
      expect(s.canLogFor('2026-11-05'), isTrue);
      expect(s.canLogFor('2026-11-04'), isFalse);
      expect(s.canLogFor('2026-11-08'), isFalse);

      expect(s.log('pompki', day: '2026-11-05').gained, 1);
      expect(s.rewardFor('2026-11-05'), 1);
      expect(s.earnedToday, 0);
    },
  );

  test('the plan freezes with the targets of that day', () async {
    final s = await open();
    s.log('pompki');
    expect(s.planFor(s.today).map((p) => p.goalId), [
      'pompki',
      'hiszpanski',
      'biurko',
    ]);
    // Completing the task does not change today's already frozen plan.
    s.log('biurko');
    expect(s.planFor(s.today), hasLength(3));
  });

  test('state survives a restart through SQLite', () async {
    sqfliteFfiInit();
    final store = await SqliteStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(store.close);

    final first = await open(store);
    for (var i = 0; i < 4; i++) {
      first.log('pompki');
    }
    first.log('biurko');
    first.build(BuildingType.garden);
    await first.flush();

    final second = await open(store);
    expect(second.balance, first.balance);
    expect(second.balance, 30 + 8 - 8);
    expect(second.built, {BuildingType.garden});
    expect(second.traces, [Category.ruch, Category.dom]);
    expect(second.goals.first.progress, 200);
    expect(second.goals, hasLength(3), reason: 'seeded only once');
  });

  test('Polish plural for goal counts', () {
    expect(goalsLabel(1), '1 cel');
    expect(goalsLabel(3), '3 cele');
    expect(goalsLabel(5), '5 celów');
    expect(goalsLabel(12), '12 celów');
    expect(goalsLabel(22), '22 cele');
  });

  test('day keys use the 4:00 boundary', () {
    expect(logicalDay(DateTime(2026, 11, 6, 3, 59)), '2026-11-05');
    expect(logicalDay(DateTime(2026, 11, 6, 4)), '2026-11-06');
    expect(weekdayGenitive('2026-11-08'), 'niedzieli');
  });
}
