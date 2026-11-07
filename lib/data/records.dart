enum Category { ruch, nauka, dom }

enum BuildingType {
  garden(
    'Ogród',
    8,
    'Grządki i płot przy ścieżce.',
    'Ogród gotowy. Mira ma pomysł na pierwsze grządki.',
  ),
  library(
    'Biblioteka',
    20,
    'Tu trafiają pamiątki z nauki.',
    'Biblioteka otwarta. Tu trafią pamiątki z nauki.',
  ),
  workshop(
    'Warsztat',
    26,
    'Narzędzia i mały plac ćwiczeń.',
    'Warsztat gotowy. Obok stanął plac ćwiczeń.',
  ),
  bridge(
    'Most',
    40,
    'Prowadzi na mglistą wysepkę.',
    'Most stoi! We mgle widać starą latarnię.',
  );

  const BuildingType(this.label, this.cost, this.description, this.doneMessage);

  final String label;
  final int cost;
  final String description;
  final String doneMessage;
}

/// A goal definition. Repeats on [weekdays] unless it has a [deadline].
class GoalDef {
  const GoalDef({
    required this.id,
    required this.title,
    required this.category,
    required this.target,
    required this.step,
    required this.createdDay,
    required this.sort,
    this.unit = '',
    this.deadline,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.archived = false,
  });

  factory GoalDef.fromMap(Map<String, Object?> m) => GoalDef(
    id: m['id']! as String,
    title: m['title']! as String,
    category: Category.values.byName(m['category']! as String),
    target: (m['target']! as num).toDouble(),
    step: (m['step']! as num).toDouble(),
    unit: m['unit']! as String,
    deadline: m['deadline'] as String?,
    createdDay: m['created_day']! as String,
    sort: m['sort']! as int,
    weekdays: {
      for (var d = 1; d <= 7; d++)
        if (((m['weekdays'] as int? ?? 127) & (1 << (d - 1))) != 0) d,
    },
    archived: m['archived'] == 1,
  );

  final String id;
  final String title;
  final Category category;
  final double target;
  final double step;
  final String unit;

  /// Day key of the deadline for one-off tasks.
  final String? deadline;
  final String createdDay;
  final int sort;
  final Set<int> weekdays;
  final bool archived;

  bool get isTask => deadline != null;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'category': category.name,
    'target': target,
    'step': step,
    'unit': unit,
    'deadline': deadline,
    'created_day': createdDay,
    'sort': sort,
    'weekdays': weekdays.fold<int>(0, (mask, day) => mask | (1 << (day - 1))),
    'archived': archived ? 1 : 0,
  };

  GoalDef withArchived(bool value) => GoalDef(
    id: id,
    title: title,
    category: category,
    target: target,
    step: step,
    createdDay: createdDay,
    sort: sort,
    unit: unit,
    deadline: deadline,
    weekdays: weekdays,
    archived: value,
  );
}

/// Edits apply from a plan day onwards; older definitions remain available
/// for history and backdated entries. One revision per goal and effective day.
class GoalRevision {
  const GoalRevision(this.goal, this.effectiveDay);

  factory GoalRevision.fromMap(Map<String, Object?> map) =>
      GoalRevision(GoalDef.fromMap(map), map['effective_day']! as String);

  final GoalDef goal;
  final String effectiveDay;

  Map<String, Object?> toMap() => {
    ...goal.toMap(),
    'effective_day': effectiveDay,
  };
}

/// One rewarded goal in a day's plan, frozen at the day's first entry
/// together with the target that applied that day.
class PlanItem {
  const PlanItem({
    required this.day,
    required this.goalId,
    required this.target,
  });

  factory PlanItem.fromMap(Map<String, Object?> m) => PlanItem(
    day: m['day']! as String,
    goalId: m['goal_id']! as String,
    target: (m['target']! as num).toDouble(),
  );

  final String day;
  final String goalId;
  final double target;

  Map<String, Object?> toMap() => {
    'day': day,
    'goal_id': goalId,
    'target': target,
  };
}

class Entry {
  const Entry({
    required this.goalId,
    required this.day,
    required this.amount,
    required this.at,
  });

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
    goalId: m['goal_id']! as String,
    day: m['day']! as String,
    amount: (m['amount']! as num).toDouble(),
    at: DateTime.fromMillisecondsSinceEpoch(m['at']! as int, isUtc: true),
  );

  final String goalId;

  /// The plan day this entry counts for, which may be earlier than [at].
  final String day;
  final double amount;
  final DateTime at;

  Map<String, Object?> toMap() => {
    'goal_id': goalId,
    'day': day,
    'amount': amount,
    'at': at.millisecondsSinceEpoch,
  };
}

class Purchase {
  const Purchase({
    required this.building,
    required this.cost,
    required this.at,
  });

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
    building: BuildingType.values.byName(m['building']! as String),
    cost: m['cost']! as int,
    at: DateTime.fromMillisecondsSinceEpoch(m['at']! as int, isUtc: true),
  );

  final BuildingType building;
  final int cost;
  final DateTime at;

  Map<String, Object?> toMap() => {
    'building': building.name,
    'cost': cost,
    'at': at.millisecondsSinceEpoch,
  };
}
