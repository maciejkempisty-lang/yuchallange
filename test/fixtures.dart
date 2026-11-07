import 'package:yu_challenge/data/store.dart';
import 'package:yu_challenge/model.dart';

/// The three goals from the original prototype, for migration/regression tests.
Future<void> seedPrototype(Store store) => store.addGoals(const [
  GoalDef(
    id: 'pompki',
    title: 'Pompki',
    category: Category.ruch,
    target: 200,
    step: 50,
    createdDay: '2026-11-05',
    sort: 0,
  ),
  GoalDef(
    id: 'hiszpanski',
    title: 'Hiszpański',
    category: Category.nauka,
    target: 15,
    step: 5,
    unit: 'min',
    createdDay: '2026-11-05',
    sort: 1,
  ),
  GoalDef(
    id: 'biurko',
    title: 'Porządek na biurku',
    category: Category.dom,
    target: 1,
    step: 1,
    deadline: '2026-11-08',
    createdDay: '2026-11-05',
    sort: 2,
  ),
]);
