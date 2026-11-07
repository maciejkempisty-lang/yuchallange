import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yu_challenge/data/store.dart';
import 'package:yu_challenge/game/paper_art.dart';
import 'package:yu_challenge/main.dart';
import 'package:yu_challenge/model.dart';

import 'fixtures.dart';

/// Image decoding does not advance under the test's fake clock, so the
/// illustrations are decoded for real once and then served from the cache.
Future<void> loadArt(WidgetTester tester) => tester.runAsync(PaperArt.load);

Future<AppState> freshState() async {
  final store = MemoryStore();
  await seedPrototype(store);
  final state = AppState(store, clock: () => DateTime(2026, 11, 5, 10));
  await state.load();
  return state;
}

Future<void> settle(WidgetTester tester, {int seconds = 5}) async {
  for (var i = 0; i < seconds * 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Decode the actual scene assets outside the widget tests' fake clock.
    final art = await PaperArt.load();
    expect(PaperAsset.values.every(art.has), isTrue);
  });

  testWidgets('large text keeps every goal and building reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await loadArt(tester);
    await tester.pumpWidget(YuApp(state: await freshState()));
    await settle(tester, seconds: 1);
    expect(tester.takeException(), isNull);
    // Sparks fly to this counter, so it must stay on screen.
    expect(find.text('30').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Pora dnia').hitTestable(), findsOneWidget);

    for (
      var swipe = 0;
      swipe < 10 && find.text('Gotowe').hitTestable().evaluate().isEmpty;
      swipe++
    ) {
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -180),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Gotowe').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Gotowe'));
    await settle(tester, seconds: 2);
    expect(find.text('34'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Zwiń ↓'));
    await tester.tap(find.text('Zwiń ↓'));
    await settle(tester, seconds: 1);
    expect(find.text('Rozwiń ↑').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Rozwiń ↑'));
    await settle(tester, seconds: 1);

    await tester.tap(find.text('Buduj'));
    await settle(tester, seconds: 1);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Most'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Most').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '20'));
    await tester.tap(find.widgetWithText(FilledButton, '20'));
    await settle(tester, seconds: 6);
    expect(find.text('14'), findsOneWidget);
    expect(
      find.text('Biblioteka otwarta. Tu trafią pamiątki z nauki.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('logging, traces and building run without errors', (
    tester,
  ) async {
    // The test font is about twice as wide as a real one; a wider view keeps
    // rows from wrapping so the layout matches a phone.
    tester.view.physicalSize = const Size(2100, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await loadArt(tester);
    await tester.pumpWidget(YuApp(state: await freshState()));
    await settle(tester, seconds: 1);
    expect(find.text('30'), findsOneWidget);

    // Four pushup sets complete the goal: 4 sparks and a trace.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('+50'));
      await settle(tester, seconds: 2);
    }
    expect(find.text('34'), findsOneWidget);
    expect(
      find.text('Twój trening zostawił ślad przy domu Yu.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Gotowe'));
    await settle(tester, seconds: 2);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('8 / 12'), findsOneWidget);

    await tester.tap(find.text('Buduj'));
    await settle(tester, seconds: 1);
    await tester.tap(find.widgetWithText(FilledButton, '20'));
    await settle(tester, seconds: 6);
    expect(find.text('18'), findsOneWidget);
    expect(
      find.text('Biblioteka otwarta. Tu trafią pamiątki z nauki.'),
      findsOneWidget,
    );

    // With the library standing, finishing Spanish leaves its trace there.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('+5 min'));
      await settle(tester, seconds: 2);
    }
    expect(find.text('22'), findsOneWidget);
    expect(find.text('Twoja nauka ożywia bibliotekę.'), findsOneWidget);
    expect(find.text('12 / 12'), findsOneWidget);
  });
}
