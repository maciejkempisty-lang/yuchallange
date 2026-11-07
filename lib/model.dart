import 'package:flutter/foundation.dart' hide Category;

import 'data/day.dart';
import 'data/records.dart';
import 'data/store.dart';

export 'data/records.dart';

/// Today's view of one planned goal.
class Goal {
  const Goal(
    this.def, {
    required this.progress,
    required this.target,
    required this.today,
  });

  final GoalDef def;
  final double progress;
  final double target;
  final String today;

  String get id => def.id;
  String get title => def.title;
  Category get category => def.category;
  bool get isTask => def.isTask;
  bool get done => progress >= target;
  double get fraction => (progress / target).clamp(0.0, 1.0);

  String get stepLabel => isTask ? 'Gotowe' : '+${_fmt(def.step)}$_unitSuffix';

  String get subtitle {
    if (!isTask) {
      return '${_fmt(progress)} / ${_fmt(target)}$_unitSuffix · dzisiaj';
    }
    final deadline = def.deadline!;
    return deadline.compareTo(today) < 0
        ? 'Zadanie · po terminie'
        : 'Zadanie · do ${formatDay(deadline)}';
  }

  String get _unitSuffix => def.unit.isEmpty ? '' : ' ${def.unit}';
}

class LogResult {
  const LogResult(this.gained, {this.completed = false});

  /// Whole sparks the balance gained.
  final int gained;

  /// Whether this entry completed the goal for its day.
  final bool completed;
}

String _fmt(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

int _whole(double v) => (v + 1e-6).floor();

/// Holds the stored rows and derives everything else from them. Writes go to
/// the [Store] in order, in the background, so the UI never waits on disk.
class AppState extends ChangeNotifier {
  AppState(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const double dailyPool = 12;
  static const maxRewardedGoals = 3;
  static const double startingSparks = 30;
  static const backfillWindow = Duration(hours: 48);

  final Store _store;
  final DateTime Function() _clock;
  Future<void> _writes = Future.value();

  final _goals = <GoalDef>[];
  final _plans = <String, List<PlanItem>>{};
  final _entries = <Entry>[];
  final _purchases = <Purchase>[];
  final _revisions = <GoalRevision>[];
  final _restDays = <String>{};

  /// The current plan day; advances only through [refreshDay].
  late String today;

  Future<void> load() async {
    final data = await _store.load();
    _goals.addAll(data.goals);
    for (final item in data.plan) {
      (_plans[item.day] ??= []).add(item);
    }
    _entries.addAll(data.entries);
    _purchases.addAll(data.purchases);
    _revisions.addAll(data.revisions);
    _restDays.addAll(data.restDays);
    today = logicalDay(_clock());
  }

  /// Completes once every write queued so far has reached the store.
  Future<void> flush() => _writes;

  /// Returns true when a new plan day has started since the last check.
  bool refreshDay() {
    final day = logicalDay(_clock());
    if (day == today) return false;
    today = day;
    notifyListeners();
    return true;
  }

  // --- Derived state ---------------------------------------------------------

  GoalDef _goalAt(String id, String day) {
    var goal = _goals.firstWhere((g) => g.id == id);
    var effective = goal.createdDay;
    for (final r in _revisions) {
      if (r.goal.id == id &&
          r.effectiveDay.compareTo(day) <= 0 &&
          r.effectiveDay.compareTo(effective) >= 0) {
        goal = r.goal;
        effective = r.effectiveDay;
      }
    }
    return goal;
  }

  GoalDef goalForEditing(String id) => _goalAt(id, '9999-12-31');

  List<GoalDef> get managedGoals => [
    for (final g in _goals) goalForEditing(g.id),
  ];

  List<GoalDef> get activeGoals =>
      managedGoals.where((g) => !g.archived).toList();
  bool get canAddGoal => activeGoals.length < maxRewardedGoals;
  bool get isRestDay => _restDays.contains(today);
  bool get isPlanFrozen => _plans.containsKey(today);
  String get goalChangeDay => isPlanFrozen ? addDays(today, 1) : today;

  String goalEffectiveDay(String id) {
    var day = _goals.firstWhere((g) => g.id == id).createdDay;
    for (final r in _revisions.where((r) => r.goal.id == id)) {
      if (r.effectiveDay.compareTo(day) > 0) day = r.effectiveDay;
    }
    return day;
  }

  double _amount(String goalId, bool Function(String day) when) => _entries
      .where((e) => e.goalId == goalId && when(e.day))
      .fold(0.0, (sum, e) => sum + e.amount);

  /// The frozen plan of [day], or the plan it would get from today's goals.
  List<PlanItem> planFor(String day) {
    if (_plans.containsKey(day)) return List.unmodifiable(_plans[day]!);
    if (_restDays.contains(day)) return [];
    return [
          for (final base in _goals)
            if (base.createdDay.compareTo(day) <= 0) _goalAt(base.id, day),
        ]
        .where(
          (g) =>
              !g.archived &&
              (g.isTask || g.weekdays.contains(parseDay(day).weekday)) &&
              !(g.isTask &&
                  _amount(g.id, (d) => d.compareTo(day) < 0) >= g.target),
        )
        .take(maxRewardedGoals)
        .map((g) => PlanItem(day: day, goalId: g.id, target: g.target))
        .toList();
  }

  double _fraction(PlanItem item) =>
      (_amount(item.goalId, (d) => d == item.day) / item.target).clamp(
        0.0,
        1.0,
      );

  /// Only frozen plans earn: a day without entries has nothing to reward.
  double rewardFor(String day) {
    final plan = _plans[day];
    if (plan == null || plan.isEmpty) return 0;
    return plan.fold(
      0.0,
      (s, item) => s + dailyPool / plan.length * _fraction(item),
    );
  }

  double get sparks =>
      startingSparks +
      _plans.keys.fold(0.0, (s, day) => s + rewardFor(day)) -
      _purchases.fold(0, (s, p) => s + p.cost);

  int get balance => _whole(sparks);
  int get earnedToday => _whole(rewardFor(today));

  List<Goal> get goals => [
    for (final item in planFor(today))
      Goal(
        _goalAt(item.goalId, today),
        progress: _amount(item.goalId, (d) => d == today),
        target: item.target,
        today: today,
      ),
  ];

  Set<BuildingType> get built => {for (final p in _purchases) p.building};

  /// One keepsake per goal completed on a day, oldest first.
  List<Category> get traces => [
    for (final day in _plans.keys.toList()..sort())
      for (final item in _plans[day]!)
        if (_fraction(item) >= 1) _goalAt(item.goalId, day).category,
  ];

  // --- Actions ---------------------------------------------------------------

  /// Entries may be added up to [backfillWindow] back; they count toward the
  /// pool of the day they belong to.
  bool canLogFor(String day) =>
      day.compareTo(today) <= 0 &&
      day.compareTo(logicalDay(_clock().subtract(backfillWindow))) >= 0;

  LogResult log(String goalId, {String? day}) {
    refreshDay();
    final d = day ?? today;
    if (!canLogFor(d) || _restDays.contains(d)) return const LogResult(0);
    final item = planFor(d).where((i) => i.goalId == goalId).firstOrNull;
    if (item == null) return const LogResult(0);
    final g = _goalAt(goalId, d);
    if (g.isTask && _amount(goalId, (_) => true) >= item.target) {
      return const LogResult(0);
    }
    final before = _amount(goalId, (x) => x == d);
    if (before >= item.target) return const LogResult(0);

    // The plan freezes at the day's first entry; later edits to goals no
    // longer change which goals share this day's pool.
    if (!_plans.containsKey(d)) {
      final plan = planFor(d);
      _plans[d] = plan;
      _write(() => _store.addPlan(plan));
    }
    final balanceBefore = balance;
    final entry = Entry(
      goalId: goalId,
      day: d,
      amount: g.isTask ? item.target - before : g.step,
      at: _clock().toUtc(),
    );
    _entries.add(entry);
    _write(() => _store.addEntry(entry));
    notifyListeners();
    return LogResult(
      balance - balanceBefore,
      completed: before + entry.amount >= item.target,
    );
  }

  bool canBuild(BuildingType t) => !built.contains(t) && balance >= t.cost;

  /// Changes to a started plan take effect tomorrow. The original definition
  /// and dated revisions also keep unlogged past days correct for backfill.
  String saveGoal({
    String? id,
    required String title,
    required Category category,
    required double target,
    required double step,
    String unit = '',
    Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
    String? deadline,
  }) {
    refreshDay();
    if (title.trim().isEmpty || title.trim().length > 60) {
      throw ArgumentError('Nazwa powinna mieć od 1 do 60 znaków.');
    }
    if (!target.isFinite ||
        !step.isFinite ||
        target < 0.01 ||
        step < 0.01 ||
        target > 1000000 ||
        step > target) {
      throw ArgumentError('Podaj dodatni cel i krok nie większy od celu.');
    }
    if (unit.trim().length > 12) {
      throw ArgumentError('Jednostka jest za długa.');
    }
    if (deadline == null &&
        (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7))) {
      throw ArgumentError('Wybierz przynajmniej jeden dzień tygodnia.');
    }
    final effective = goalChangeDay;
    if (deadline != null &&
        (DateTime.tryParse(deadline) == null ||
            dayKey(parseDay(deadline)) != deadline ||
            deadline.compareTo(effective) < 0)) {
      throw ArgumentError(
        'Termin musi przypadać w dniu rozpoczęcia lub później.',
      );
    }
    final old = id == null ? null : goalForEditing(id);
    if (old != null && old.isTask != (deadline != null)) {
      throw ArgumentError(
        'Aby zmienić typ celu, utwórz nowy cel. Dotychczasowe wpisy zostaną w historii.',
      );
    }
    if ((old == null || old.archived) && !canAddGoal) {
      throw StateError(
        'Możesz mieć do 3 aktywnych celów. Najpierw odłóż jeden do archiwum.',
      );
    }
    final goal = GoalDef(
      id:
          id ??
          'goal-${_clock().toUtc().microsecondsSinceEpoch}-${_goals.length}',
      title: title.trim(),
      category: category,
      target: deadline == null ? target : 1,
      step: deadline == null ? step : 1,
      unit: deadline == null ? unit.trim() : '',
      deadline: deadline,
      weekdays: Set.unmodifiable(weekdays),
      createdDay: old?.createdDay ?? effective,
      sort: old?.sort ?? _goals.length,
    );
    if (old == null) {
      _goals.add(goal);
      _write(() => _store.addGoals([goal]));
    } else {
      _saveRevision(GoalRevision(goal, effective));
    }
    notifyListeners();
    return effective;
  }

  String archiveGoal(String id, {bool archived = true}) {
    refreshDay();
    final goal = goalForEditing(id);
    if (!archived && goal.archived && !canAddGoal) {
      throw StateError('Możesz mieć do 3 aktywnych celów.');
    }
    final effective = goalChangeDay;
    _saveRevision(GoalRevision(goal.withArchived(archived), effective));
    notifyListeners();
    return effective;
  }

  void _saveRevision(GoalRevision revision) {
    _revisions.removeWhere(
      (r) =>
          r.goal.id == revision.goal.id &&
          r.effectiveDay == revision.effectiveDay,
    );
    _revisions.add(revision);
    _write(() => _store.saveRevision(revision));
  }

  void setRestToday(bool rest) {
    refreshDay();
    final day = today;
    if (rest) {
      _restDays.add(day);
    } else {
      _restDays.remove(day);
    }
    _write(() => _store.setRestDay(day, rest));
    notifyListeners();
  }

  void build(BuildingType t) {
    if (!canBuild(t)) return;
    final purchase = Purchase(building: t, cost: t.cost, at: _clock().toUtc());
    _purchases.add(purchase);
    _write(() => _store.addPurchase(purchase));
    notifyListeners();
  }

  void _write(Future<void> Function() op) {
    _writes = _writes.then((_) => op()).catchError((Object e) {
      debugPrint('Zapis nie powiódł się: $e');
    });
  }
}

/// "1 cel", "2 cele", "5 celów".
String goalsLabel(int n) {
  if (n == 1) return '1 cel';
  final tens = n % 100 ~/ 10, ones = n % 10;
  return tens != 1 && ones >= 2 && ones <= 4 ? '$n cele' : '$n celów';
}
