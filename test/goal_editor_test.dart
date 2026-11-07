import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yu_challenge/data/store.dart';
import 'package:yu_challenge/game/paper_art.dart';
import 'package:yu_challenge/main.dart';
import 'package:yu_challenge/model.dart';
import 'package:yu_challenge/ui/goal_editor_screen.dart';

Future<void> tick(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tick(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PaperArt.load);

  Future<AppState> state() async {
    final s = AppState(MemoryStore(), clock: () => DateTime(2026, 11, 5, 10));
    await s.load();
    return s;
  }

  void phone(WidgetTester tester, {double textScale = 1}) {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('first goal, logging and reversible rest work from the island', (
    tester,
  ) async {
    phone(tester);
    final s = await state();
    await tester.pumpWidget(YuApp(state: s));
    await tick(tester);
    await tap(tester, find.text('Wybierz pierwszy cel'));
    await tap(tester, find.text('Codzienny spacer'));
    await tap(tester, find.text('Zapisz cel'));
    expect(s.activeGoals, hasLength(1));
    expect(find.text('Spacer'), findsOneWidget);
    await tap(tester, find.text('+5 min'));
    expect(s.balance, 33);
    await tap(tester, find.text('Dziś odpoczywam'));
    expect(s.isRestDay, isTrue);
    expect(find.text('+5 min'), findsNothing);
    await tap(tester, find.text('Wracam do planu'));
    expect(s.goals.single.progress, 5);
    expect(s.balance, 33);
    expect(find.text('+5 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text editor validates days and preserves template schedule',
    (tester) async {
      phone(tester, textScale: 2);
      final s = await state();
      await tester.pumpWidget(MaterialApp(home: GoalEditorScreen(state: s)));
      await tap(tester, find.text('Trening 3× w tygodniu'));
      for (final day in ['Pon', 'Śr', 'Pt']) {
        await tap(tester, find.widgetWithText(FilterChip, day));
      }
      await tap(tester, find.text('Zapisz cel'));
      expect(find.text('Wybierz przynajmniej jeden dzień.'), findsOneWidget);
      expect(s.managedGoals, isEmpty);
      await tap(tester, find.widgetWithText(FilterChip, 'Czw'));
      await tap(tester, find.text('Zapisz cel'));
      expect(s.activeGoals.single.weekdays, {4});
      expect(s.goals.single.target, 30);
      expect(s.goals.single.def.step, 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing and archiving a started goal keeps today usable', (
    tester,
  ) async {
    phone(tester);
    final s = await state();
    s.saveGoal(
      title: 'Spacer',
      category: Category.ruch,
      target: 20,
      step: 5,
      unit: 'min',
    );
    s.log(s.activeGoals.single.id);
    await tester.pumpWidget(YuApp(state: s));
    await tick(tester);
    await tap(tester, find.text('Moje cele'));
    await tap(tester, find.text('Spacer'));
    await tester.enterText(find.byType(TextFormField).at(0), 'Spacer w parku');
    await tester.enterText(find.byType(TextFormField).at(1), '40');
    await tester.enterText(find.byType(TextFormField).at(3), '10');
    await tap(tester, find.text('Zapisz cel'));
    expect(s.activeGoals.single.title, 'Spacer w parku');
    expect(s.activeGoals.single.target, 40);
    expect(s.goals.single.title, 'Spacer');
    expect(s.goals.single.progress, 5);
    await tap(tester, find.byTooltip('Opcje celu: Spacer w parku'));
    await tap(tester, find.text('Odłóż do archiwum'));
    await tap(tester, find.byTooltip('Wstecz'));
    expect(find.text('Spacer'), findsOneWidget);
    expect(find.text('Wybierz pierwszy cel'), findsNothing);
    await tap(tester, find.text('+5 min'));
    expect(s.goals.single.progress, 10);
    expect(s.balance, 36);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one-off task uses the Polish date picker and a single checkbox',
    (tester) async {
      phone(tester);
      final s = await state();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('pl')],
          locale: const Locale('pl'),
          home: GoalEditorScreen(state: s),
        ),
      );
      await tap(tester, find.text('Jedna rzecz do zrobienia'));
      await tester.enterText(
        find.byType(TextFormField).first,
        'Posadzić kwiat',
      );
      await tap(tester, find.text('Termin: 12.11.2026'));
      expect(find.text('Termin zadania'), findsOneWidget);
      await tap(tester, find.text('Wybierz'));
      await tap(tester, find.text('Zapisz cel'));
      expect(s.goals.single.isTask, isTrue);
      expect(s.goals.single.def.deadline, '2026-11-12');
      expect(s.goals.single.stepLabel, 'Gotowe');
      expect(tester.takeException(), isNull);
    },
  );
}
