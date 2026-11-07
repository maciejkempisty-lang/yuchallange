import 'records.dart';

class StoredData {
  const StoredData({
    required this.goals,
    required this.plan,
    required this.entries,
    required this.purchases,
    this.revisions = const [],
    this.restDays = const {},
  });

  final List<GoalDef> goals;
  final List<PlanItem> plan;
  final List<Entry> entries;
  final List<Purchase> purchases;
  final List<GoalRevision> revisions;
  final Set<String> restDays;
}

/// Entries and purchases are append-only. Definitions have dated revisions,
/// so editing a goal cannot rewrite the plan or rewards of an earlier day.
abstract interface class Store {
  Future<StoredData> load();
  Future<void> addGoals(List<GoalDef> goals);
  Future<void> addPlan(List<PlanItem> items);
  Future<void> addEntry(Entry entry);
  Future<void> addPurchase(Purchase purchase);
  Future<void> saveRevision(GoalRevision revision);
  Future<void> setRestDay(String day, bool rest);
}

/// Used on web and in tests; forgets everything on restart.
class MemoryStore implements Store {
  final _goals = <GoalDef>[];
  final _plan = <PlanItem>[];
  final _entries = <Entry>[];
  final _purchases = <Purchase>[];
  final _revisions = <GoalRevision>[];
  final _restDays = <String>{};

  @override
  Future<StoredData> load() async => StoredData(
    goals: [..._goals],
    plan: [..._plan],
    entries: [..._entries],
    purchases: [..._purchases],
    revisions: [..._revisions],
    restDays: {..._restDays},
  );

  @override
  Future<void> addGoals(List<GoalDef> goals) async => _goals.addAll(goals);

  @override
  Future<void> addPlan(List<PlanItem> items) async => _plan.addAll(items);

  @override
  Future<void> addEntry(Entry entry) async => _entries.add(entry);

  @override
  Future<void> addPurchase(Purchase purchase) async => _purchases.add(purchase);

  @override
  Future<void> saveRevision(GoalRevision revision) async {
    _revisions.removeWhere(
      (r) =>
          r.goal.id == revision.goal.id &&
          r.effectiveDay == revision.effectiveDay,
    );
    _revisions.add(revision);
  }

  @override
  Future<void> setRestDay(String day, bool rest) async {
    if (rest) {
      _restDays.add(day);
    } else {
      _restDays.remove(day);
    }
  }
}
