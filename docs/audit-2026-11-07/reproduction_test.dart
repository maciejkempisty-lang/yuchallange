// Audit probes: these assert desired behaviour and intentionally expose the
// unfixed findings of 2026-11-07. They are outside test/ and do not replace the
// normal regression suite. Run with TZ=Europe/Warsaw and flutter test <path>.
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yu_challenge/data/day.dart';
import 'package:yu_challenge/data/store.dart';
import 'package:yu_challenge/game/island_game.dart';
import 'package:yu_challenge/game/paper_art.dart';
import 'package:yu_challenge/model.dart' hide Category;
import 'package:yu_challenge/model.dart' as model;

class RejectEntryStore extends MemoryStore {
  @override
  Future<void> addEntry(Entry entry) async => throw StateError('simulated disk failure');
}

class RejectPlanStore extends MemoryStore {
  @override
  Future<void> addPlan(List<PlanItem> plan) async => throw StateError('simulated plan write failure');
}

Future<AppState> open(Store store, {DateTime Function()? clock}) async {
  final state = AppState(store, clock: clock ?? () => DateTime(2026, 11, 7, 10));
  await state.load();
  return state;
}

String add(AppState state, {double target = 20, double step = 5, String? deadline}) {
  state.saveGoal(title: 'Audit goal', category: model.Category.ruch, target: target, step: step, deadline: deadline);
  return state.activeGoals.last.id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PaperArt.load);

  test('A1 entry failure must not silently lose awarded progress', () async {
    final store = RejectEntryStore();
    final state = await open(store);
    final id = add(state);
    await state.flush();
    state.log(id);
    await state.flush(); // currently reports success despite failure
    final reopened = await open(store);
    print('A1 before_restart=${state.balance} after_restart=${reopened.balance} flush_completed=true');
    expect(reopened.balance, state.balance);
  });

  test('A1 plan failure must not persist an unfunded purchase', () async {
    final store = RejectPlanStore();
    final state = await open(store);
    final id = add(state, target: 20, step: 20);
    state.log(id);
    state.build(BuildingType.bridge);
    await state.flush();
    final reopened = await open(store);
    print('A1 partial_write before_restart=${state.balance} after_restart=${reopened.balance} bridge_saved=${reopened.built.contains(BuildingType.bridge)}');
    expect(reopened.balance, greaterThanOrEqualTo(0));
  });

  test('A2 ten steps of 0.1 must complete a target of 1', () async {
    final state = await open(MemoryStore());
    final id = add(state, target: 1, step: 0.1);
    for (var i = 0; i < 10; i++) { state.log(id); }
    print('A2 progress=${state.goals.single.progress} subtitle=${state.goals.single.subtitle} done=${state.goals.single.done} traces=${state.traces.length} earned=${state.earnedToday}');
    expect(state.goals.single.done, isTrue);
    expect(state.traces, hasLength(1));
  });

  test('A3 spring clock change must still use the local 4 AM boundary', () {
    final at = DateTime(2026, 3, 29, 4, 30);
    expect(at.timeZoneOffset, const Duration(hours: 2), reason: 'Run with TZ=Europe/Warsaw');
    print('A3 spring at=$at offset=${at.timeZoneOffset} day=${logicalDay(at)}');
    expect(logicalDay(at), '2026-03-29');
  });

  test('A3 autumn clock change must still use the local 4 AM boundary', () {
    final at = DateTime(2026, 10, 25, 3, 30);
    expect(at.timeZoneOffset, const Duration(hours: 1), reason: 'Run with TZ=Europe/Warsaw');
    print('A3 autumn at=$at offset=${at.timeZoneOffset} day=${logicalDay(at)}');
    expect(logicalDay(at), '2026-10-24');
  });

  test('A4 completed one-off tasks should free active goal slots', () async {
    var now = DateTime(2026, 11, 7, 10);
    final state = await open(MemoryStore(), clock: () => now);
    final ids = [for (var i = 0; i < 3; i++) add(state, deadline: '2026-11-08')];
    for (final id in ids) { state.log(id); }
    now = DateTime(2026, 11, 8, 10);
    state.refreshDay();
    print('A4 visible_today=${state.goals.length} active=${state.activeGoals.length} can_add=${state.canAddGoal}');
    expect(state.canAddGoal, isTrue);
  });

  testWidgets('A5 unlocked lighthouse should fit in the normal phone frame', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await open(MemoryStore());
    final id = add(state, target: 1, step: 1);
    state.log(id);
    state.build(BuildingType.bridge);
    final game = IslandGame(state: state)..setViewport(top: 132, bottom: 400);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameWidget(game: game))));
    for (var i = 0; i < 40; i++) { await tester.pump(const Duration(milliseconds: 50)); }
    expect(game.isLoaded, isTrue);
    final centerX = game.root.position.x + game.islet.position.x * game.root.scale.x;
    final rightX = centerX + game.islet.size.x / 2 * game.root.scale.x;
    print('A5 viewport=${game.size.x} lighthouse_center=$centerX lighthouse_right=$rightX fog=${game.islet.fog}');
    expect(rightX, lessThanOrEqualTo(game.size.x));
  });
}
