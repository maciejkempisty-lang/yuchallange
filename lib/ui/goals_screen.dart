import 'package:flutter/material.dart';

import '../data/day.dart';
import '../model.dart';
import '../palette.dart';
import 'goal_editor_screen.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key, required this.state});
  final AppState state;

  Future<void> _edit(BuildContext context, [GoalDef? goal]) async {
    final day = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => GoalEditorScreen(state: state, goal: goal),
      ),
    );
    if (day != null && context.mounted) _notice(context, day);
  }

  void _notice(BuildContext context, String day) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          day == state.today
              ? 'Plan zapisany.'
              : 'Zmiana zapisana. Obowiązuje od ${formatDay(day)}.',
        ),
      ),
    );
  }

  void _archive(BuildContext context, GoalDef goal) {
    try {
      final day = state.archiveGoal(goal.id, archived: !goal.archived);
      _notice(context, day);
    } on StateError catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Pal.sheet,
    appBar: AppBar(
      backgroundColor: Pal.sheet,
      title: const Text('Moje cele', style: TextStyle(fontFamily: 'Fraunces')),
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              '${state.activeGoals.length} z ${AppState.maxRewardedGoals} aktywnych celów',
              style: const TextStyle(
                fontSize: 24,
                fontFamily: 'Fraunces',
                color: Pal.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.isPlanFrozen
                  ? 'Dzisiejszy plan już ruszył. Edycja, dodawanie i odkładanie celów zadziałają od ${formatDay(state.goalChangeDay)}.'
                  : 'Wybierz mały plan, do którego chcesz wracać. Na początek wystarczy jeden cel.',
              style: const TextStyle(fontSize: 15, color: Pal.textDim),
            ),
            const SizedBox(height: 20),
            for (final goal in state.activeGoals) _tile(context, goal),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.canAddGoal ? () => _edit(context) : null,
              icon: const Icon(Icons.add),
              label: const Text('Dodaj cel'),
              style: FilledButton.styleFrom(
                backgroundColor: Pal.accent,
                foregroundColor: Pal.onAccent,
                padding: const EdgeInsets.all(16),
              ),
            ),
            if (!state.canAddGoal)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Masz już 3 cele. Możesz edytować jeden albo odłożyć go do archiwum, zachowując wpisy i pamiątki.',
                  style: TextStyle(color: Pal.textDim),
                ),
              ),
            if (state.managedGoals.any((g) => g.archived)) ...[
              const SizedBox(height: 28),
              const Text(
                'Archiwum',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 22,
                  color: Pal.text,
                ),
              ),
              const SizedBox(height: 8),
              for (final goal in state.managedGoals.where((g) => g.archived))
                _tile(context, goal),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _tile(BuildContext context, GoalDef goal) {
    final effective = state.goalEffectiveDay(goal.id);
    return Card(
      elevation: 0,
      color: Pal.card,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        title: Text(
          goal.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${categoryLabel(goal.category)} · ${goalSchedule(goal)}'
          '${effective.compareTo(state.today) > 0 ? '\nOd ${formatDay(effective)}' : ''}',
        ),
        onTap: goal.archived ? null : () => _edit(context, goal),
        trailing: PopupMenuButton<String>(
          tooltip: 'Opcje celu: ${goal.title}',
          onSelected: (value) =>
              value == 'edit' ? _edit(context, goal) : _archive(context, goal),
          itemBuilder: (_) => [
            if (!goal.archived)
              const PopupMenuItem(value: 'edit', child: Text('Edytuj')),
            PopupMenuItem(
              value: 'archive',
              child: Text(goal.archived ? 'Przywróć' : 'Odłóż do archiwum'),
            ),
          ],
        ),
      ),
    );
  }
}
