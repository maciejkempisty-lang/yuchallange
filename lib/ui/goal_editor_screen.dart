import 'package:flutter/material.dart';

import '../data/day.dart';
import '../model.dart';
import '../palette.dart';

const weekdayNames = ['Pon', 'Wt', 'Śr', 'Czw', 'Pt', 'Sob', 'Niedz'];
const _fullWeekdays = [
  'Poniedziałek',
  'Wtorek',
  'Środa',
  'Czwartek',
  'Piątek',
  'Sobota',
  'Niedziela',
];

String categoryLabel(Category c) => switch (c) {
  Category.ruch => 'Ruch',
  Category.nauka => 'Nauka',
  Category.dom => 'Dom',
};

String goalSchedule(GoalDef g) => g.isTask
    ? 'Jednorazowo · do ${formatDay(g.deadline!)}'
    : g.weekdays.length == 7
    ? 'Codziennie'
    : [
        for (var d = 1; d <= 7; d++)
          if (g.weekdays.contains(d)) weekdayNames[d - 1],
      ].join(' · ');

/// A template-first editor; the form stays a regular Flutter screen so the
/// keyboard and large system text never compete with the game viewport.
class GoalEditorScreen extends StatefulWidget {
  const GoalEditorScreen({super.key, required this.state, this.goal});

  final AppState state;
  final GoalDef? goal;

  @override
  State<GoalEditorScreen> createState() => _GoalEditorScreenState();
}

class _GoalEditorScreenState extends State<GoalEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _target = TextEditingController(
    text: _number(widget.goal?.target ?? 10),
  );
  late final _step = TextEditingController(
    text: _number(widget.goal?.step ?? 1),
  );
  late final _unit = TextEditingController(text: widget.goal?.unit ?? '');
  late Category _category = widget.goal?.category ?? Category.ruch;
  late bool _task = widget.goal?.isTask ?? false;
  late Set<int> _days = {
    ...(widget.goal?.weekdays ?? {1, 2, 3, 4, 5, 6, 7}),
  };
  late String _deadline =
      widget.goal?.deadline ?? addDays(widget.state.goalChangeDay, 7);
  late bool _choosing = widget.goal == null;
  String? _daysError;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _step.dispose();
    _unit.dispose();
    super.dispose();
  }

  static String _number(double n) =>
      n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  double? _read(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _template(
    String name,
    Category category,
    double target,
    double step,
    String unit,
    Set<int> days, {
    bool task = false,
  }) {
    setState(() {
      _title.text = name;
      _category = category;
      _target.text = _number(target);
      _step.text = _number(step);
      _unit.text = unit;
      _days = {...days};
      _task = task;
      _choosing = false;
    });
  }

  Future<void> _chooseDate() async {
    widget.state.refreshDay();
    final first = parseDay(widget.state.goalChangeDay);
    final current = parseDay(_deadline);
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: DateTime(first.year + 10, 12, 31),
      helpText: 'Termin zadania',
      cancelText: 'Anuluj',
      confirmText: 'Wybierz',
    );
    if (date != null && mounted) setState(() => _deadline = dayKey(date));
  }

  void _save() {
    final valid = _form.currentState!.validate();
    setState(
      () => _daysError = !_task && _days.isEmpty
          ? 'Wybierz przynajmniej jeden dzień.'
          : null,
    );
    if (!valid || _daysError != null) return;
    try {
      final day = widget.state.saveGoal(
        id: widget.goal?.id,
        title: _title.text,
        category: _category,
        target: _task ? 1 : _read(_target)!,
        step: _task ? 1 : _read(_step)!,
        unit: _unit.text,
        weekdays: _days,
        deadline: _task ? _deadline : null,
      );
      Navigator.pop(context, day);
    } on ArgumentError catch (e) {
      _error('${e.message}');
    } on StateError catch (e) {
      _error(e.message);
    }
  }

  void _error(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: Pal.card,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Pal.text,
      ),
    ),
  );

  Widget _templateTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => Card(
    color: Pal.card,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(icon, color: Pal.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Pal.sheet,
    appBar: AppBar(
      backgroundColor: Pal.sheet,
      title: Text(
        widget.goal != null
            ? 'Edytuj cel'
            : widget.state.activeGoals.isEmpty
            ? 'Twój pierwszy cel'
            : 'Nowy cel',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'Fraunces'),
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: _choosing ? _templates() : _fields(context),
      ),
    ),
  );

  Widget _templates() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Jeden mały krok wystarczy.',
        style: TextStyle(fontFamily: 'Fraunces', fontSize: 27, color: Pal.text),
      ),
      const SizedBox(height: 8),
      const Text(
        'Wybierz pomysł i dopasuj go do siebie. Dni wolne też są częścią planu.',
        style: TextStyle(color: Pal.textDim, fontSize: 16),
      ),
      const SizedBox(height: 24),
      _templateTile(
        Icons.fitness_center,
        'Trening 3× w tygodniu',
        'Pon, śr, pt · 30 min',
        () => _template('Trening', Category.ruch, 30, 10, 'min', {1, 3, 5}),
      ),
      _templateTile(
        Icons.directions_walk,
        'Codzienny spacer',
        '20 min · krok po 5 min',
        () => _template('Spacer', Category.ruch, 20, 5, 'min', {
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        }),
      ),
      _templateTile(
        Icons.menu_book_outlined,
        'Czytanie',
        '10 stron · krok po 5 stron',
        () => _template('Czytanie', Category.nauka, 10, 5, 'stron', {
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        }),
      ),
      _templateTile(
        Icons.check_circle_outline,
        'Jedna rzecz do zrobienia',
        'Własny termin · odhaczasz raz',
        () => _template('', Category.dom, 1, 1, '', {
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        }, task: true),
      ),
      _templateTile(
        Icons.edit_outlined,
        'Twój pomysł',
        'Ustaw własną nazwę i plan',
        () => _template('', Category.ruch, 10, 1, '', {1, 2, 3, 4, 5, 6, 7}),
      ),
    ],
  );

  Widget _fields(BuildContext context) => Form(
    key: _form,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state.isPlanFrozen)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Pal.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Dzisiejszy plan już ruszył. Zmiany będą działały od ${formatDay(widget.state.goalChangeDay)}. Dzisiejsze wpisy i iskry zostają.',
            ),
          ),
        TextFormField(
          controller: _title,
          decoration: _decoration('Nazwa celu', hint: 'Co chcesz zrobić?'),
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Nadaj celowi nazwę.' : null,
        ),
        _heading('Jak realizujesz cel?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Powtarzalny'),
              selected: !_task,
              onSelected: widget.goal == null
                  ? (_) => setState(() => _task = false)
                  : null,
            ),
            ChoiceChip(
              label: const Text('Jednorazowy'),
              selected: _task,
              onSelected: widget.goal == null
                  ? (_) => setState(() => _task = true)
                  : null,
            ),
          ],
        ),
        if (widget.goal != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Typ jest stały. Jeśli potrzebujesz innego, dodaj nowy cel.',
              style: TextStyle(color: Pal.textDim),
            ),
          ),
        _heading('Kategoria'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in Category.values)
              ChoiceChip(
                label: Text(categoryLabel(c)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        if (_task) ...[
          _heading('Do kiedy?'),
          OutlinedButton.icon(
            onPressed: _chooseDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Termin: ${formatDay(_deadline)}'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Zadanie pojawia się do momentu ukończenia. Odhaczasz je raz przyciskiem „Gotowe”.',
            style: TextStyle(color: Pal.textDim),
          ),
        ] else ...[
          _heading('Ile w zaplanowany dzień?'),
          TextFormField(
            controller: _target,
            decoration: _decoration('Wartość docelowa', hint: 'np. 20'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: (_) => _validateNumber(_target),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _unit,
            decoration: _decoration(
              'Jednostka',
              hint: 'opcjonalnie: min, stron, km',
            ),
            maxLength: 12,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _step,
            decoration: _decoration('Wielkość kroku', hint: 'np. 5'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            validator: (_) {
              final error = _validateNumber(_step);
              if (error != null) return error;
              if (_read(_target) != null && _read(_step)! > _read(_target)!) {
                return 'Krok nie może być większy od celu.';
              }
              return null;
            },
          ),
          _heading('W które dni?'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                Tooltip(
                  message: _fullWeekdays[d - 1],
                  child: FilterChip(
                    label: Text(weekdayNames[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _days.add(d);
                      } else {
                        _days.remove(d);
                      }
                      _daysError = null;
                    }),
                  ),
                ),
            ],
          ),
          if (_daysError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _daysError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Pozostałe dni są wolne od tego celu. Możesz też oznaczyć odpoczynek na ekranie wyspy.',
            style: TextStyle(color: Pal.textDim),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Text('Zapisz cel'),
          style: FilledButton.styleFrom(
            backgroundColor: Pal.accent,
            foregroundColor: Pal.onAccent,
            padding: const EdgeInsets.all(17),
          ),
        ),
        if (widget.goal == null)
          TextButton(
            onPressed: () => setState(() => _choosing = true),
            child: const Text('Wybierz inny pomysł'),
          ),
      ],
    ),
  );

  String? _validateNumber(TextEditingController controller) {
    final value = _read(controller);
    if (value == null || !value.isFinite || value < 0.01 || value > 1000000) {
      return 'Podaj liczbę od 0,01 do 1 000 000.';
    }
    if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(controller.text.trim())) {
      return 'Użyj najwyżej dwóch cyfr po przecinku.';
    }
    return null;
  }
}
