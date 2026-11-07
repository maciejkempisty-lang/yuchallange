import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../game/island_game.dart';
import '../model.dart';
import '../palette.dart';
import 'build_sheet.dart';
import 'goal_editor_screen.dart';
import 'goals_screen.dart';
import 'spark_flight.dart';

IconData categoryIcon(Category c) => switch (c) {
  Category.ruch => Icons.fitness_center,
  Category.nauka => Icons.menu_book_outlined,
  Category.dom => Icons.home_outlined,
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _chromeMaxScale = 1.4;
  static const _times = [
    (0.0, Icons.wb_sunny_outlined),
    (0.5, Icons.wb_twilight),
    (1.0, Icons.nightlight_outlined),
  ];

  late final state = widget.state;
  late final game = IslandGame(state: state)..onBuilt = _onBuilt;
  Timer? _dayTimer;

  final _stackKey = GlobalKey();
  final _counterKey = GlobalKey();
  final _buttonKeys = <String, GlobalKey>{};
  final _flights = <Flight>[];
  final _rnd = math.Random();
  int _nextFlight = 0;

  /// Sparks already in the balance but still flying toward the counter.
  int _pending = 0;
  bool _expanded = true;
  String _message = switch (DateTime.now().hour) {
    >= 5 && < 12 => 'Dzień dobry! Yu czeka na Twój pierwszy krok.',
    >= 12 && < 18 => 'Cześć! Yu czeka na Twój kolejny krok.',
    _ => 'Dobry wieczór! Yu czeka przy domu.',
  };
  late int _timeIndex = switch (nightFromClock(DateTime.now())) {
    < 0.25 => 0,
    < 0.75 => 1,
    _ => 2,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Covers an app left open across the day boundary.
    _dayTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkDay());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _checkDay();
  }

  void _checkDay() {
    if (!state.refreshDay()) return;
    setState(() {
      _flights.clear();
      _pending = 0;
      _expanded = true;
    });
    _say('Nowy dzień. Plan odnowiony, osada czeka.');
  }

  // --- Actions ---------------------------------------------------------------

  Future<void> _firstGoal() async {
    final day = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => GoalEditorScreen(state: state)),
    );
    if (day != null && mounted) {
      setState(() => _expanded = true);
      _say('Twój plan jest gotowy. Każdy mały krok zostawi tu ślad.');
    }
  }

  Future<void> _manageGoals() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => GoalsScreen(state: state)));
    if (mounted) _checkDay();
  }

  void _rest(bool rest) {
    state.setRestToday(rest);
    _say(
      rest
          ? 'Dziś spokojniej. Yu pilnuje Twojej osady.'
          : 'Wracamy do planu, w Twoim tempie.',
    );
  }

  void _log(Goal g) {
    final from = _centerOf(_buttonKeys[g.id]!);
    final result = state.log(g.id);
    HapticFeedback.lightImpact();
    if (from != null) _launchSparks(from, result.gained);
    if (result.completed) {
      HapticFeedback.mediumImpact();
      if (game.isLoaded) game.addTrace(g.category);
      _say(_traceMessage(g.category));
    }
  }

  void _launchSparks(Offset from, int gained) {
    final to = _centerOf(_counterKey);
    if (to == null || MediaQuery.disableAnimationsOf(context)) return;
    setState(() {
      _pending += gained;
      for (var i = 0; i < math.max(1, gained); i++) {
        _flights.add(
          Flight(
            id: _nextFlight++,
            from: from,
            to: to,
            delay: Duration(milliseconds: i * 120),
            counts: i < gained,
            bend: _rnd.nextDouble() * 2 - 1,
          ),
        );
      }
    });
  }

  void _arrive(Flight f) {
    setState(() {
      _flights.remove(f);
      if (f.counts) _pending--;
    });
    if (f.counts) HapticFeedback.selectionClick();
  }

  Future<void> _openBuild() async {
    final type = await showBuildSheet(context, state);
    if (type == null || !mounted) return;
    await game.loaded;
    if (!mounted) return;
    state.build(type);
    HapticFeedback.mediumImpact();
    setState(() => _expanded = false);
    _say('Yu zabiera się do pracy…');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) game.build(type);
  }

  void _onBuilt(BuildingType type) {
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    _say(type.doneMessage);
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _expanded = true);
    });
  }

  void _cycleTime() {
    setState(() => _timeIndex = (_timeIndex + 1) % _times.length);
    game.setTimeOfDay(_times[_timeIndex].$1);
  }

  void _say(String message) => setState(() => _message = message);

  String _traceMessage(Category c) => switch (c) {
    Category.ruch when state.built.contains(BuildingType.workshop) =>
      'Plac ćwiczeń przy warsztacie ma nowy sprzęt.',
    Category.ruch => 'Twój trening zostawił ślad przy domu Yu.',
    Category.nauka when state.built.contains(BuildingType.library) =>
      'Twoja nauka ożywia bibliotekę.',
    Category.nauka => 'Na progu Yu pojawiły się książki.',
    Category.dom => 'Przy drzwiach zakwitł kwiat. Twój domowy cel gotowy!',
  };

  Offset? _centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached) return null;
    return stack.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  // --- Layout ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final extraTextHeight = math.max(0.0, textScaler.scale(17) - 17);
    final preferredSheetH =
        (_expanded
            ? 400.0 + extraTextHeight * 8
            : 112.0 + extraTextHeight * 2) +
        pad.bottom;
    final sheetH = math.min(
      preferredSheetH,
      MediaQuery.sizeOf(context).height * 0.65,
    );
    // The header and the build button are chrome over the scene: they grow
    // only up to [_chromeMaxScale], so the counter never leaves the screen.
    final chromeScale = textScaler
        .clamp(maxScaleFactor: _chromeMaxScale)
        .scale(1);
    game.setViewport(top: pad.top + 132 * chromeScale, bottom: sheetH);

    return Scaffold(
      backgroundColor: Pal.sea,
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Stack(
          key: _stackKey,
          children: [
            Positioned.fill(child: GameWidget(game: game)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: pad.top + 180,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Pal.sheet.withValues(alpha: 0.96),
                        Pal.sheet.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: pad.top + 12,
              left: 20,
              right: 20,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: _chromeMaxScale,
                child: _header(),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              right: 20,
              bottom: sheetH + 14,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: _chromeMaxScale,
                child: _buildButton(),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: sheetH,
              child: _sheet(pad.bottom),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  children: [
                    for (final f in _flights)
                      SparkFlight(
                        key: ValueKey(f.id),
                        flight: f,
                        onArrive: () => _arrive(f),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final shown = state.balance - _pending;
    const pillColor = Pal.sheet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'YuChallenge',
                      maxLines: 1,
                      style: TextStyle(
                        color: Pal.text,
                        fontFamily: 'Fraunces',
                        fontSize: 27,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  Text(
                    'Zacisze Yu · Rozdział 1',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Pal.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Pora dnia',
              child: InkResponse(
                onTap: _cycleTime,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: pillColor,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, a) => RotationTransition(
                      turns: Tween(begin: 0.5, end: 1.0).animate(a),
                      child: FadeTransition(opacity: a, child: child),
                    ),
                    child: Icon(
                      _times[_timeIndex].$2,
                      key: ValueKey(_timeIndex),
                      color: Pal.goldInk,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 18, 11),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    key: _counterKey,
                    color: Pal.goldInk,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                        '$shown',
                        style: const TextStyle(
                          color: Pal.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      )
                      .animate(key: ValueKey(shown))
                      .scaleXY(
                        begin: 1.4,
                        end: 1,
                        duration: 380.ms,
                        curve: Curves.easeOutBack,
                      )
                      .tint(color: Pal.spark, begin: 0.9, end: 0),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, -0.3),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(_message),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.sheet.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/paper/yu.png',
                  width: 32,
                  height: 35,
                  cacheWidth: 96,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _message,
                    style: const TextStyle(color: Pal.text, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButton() {
    Widget button = FilledButton.icon(
      onPressed: _openBuild,
      style: FilledButton.styleFrom(
        backgroundColor: Pal.accent,
        foregroundColor: Pal.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: const Icon(Icons.construction),
      label: const Text(
        'Buduj',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
    if (BuildingType.values.any(state.canBuild)) {
      button = button
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(end: 1.06, duration: 900.ms, curve: Curves.easeInOut);
    }
    return button;
  }

  Widget _sheet(double bottomPad) {
    return GestureDetector(
      onTap: _expanded ? null : () => setState(() => _expanded = true),
      child: Container(
        decoration: const BoxDecoration(
          color: Pal.sheet,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Color(0x202C4137),
              blurRadius: 28,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(22, 10, 22, 10 + bottomPad),
        child: SingleChildScrollView(
          key: ValueKey(_expanded),
          primary: false,
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Pal.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() > 150) {
                    setState(() => _expanded = velocity < 0);
                  }
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.isRestDay
                            ? 'Dziś · odpoczynek'
                            : state.activeGoals.isEmpty && state.goals.isEmpty
                            ? 'Pierwszy krok'
                            : state.goals.isEmpty
                            ? 'Dziś · wolne'
                            : 'Dziś · ${goalsLabel(state.goals.length)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Pal.text,
                          fontFamily: 'Fraunces',
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      style: TextButton.styleFrom(foregroundColor: Pal.textDim),
                      child: Text(_expanded ? 'Zwiń ↓' : 'Rozwiń ↑'),
                    ),
                  ],
                ),
              ),
              if (!state.isRestDay && state.goals.isNotEmpty) ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Iskry z dzisiejszego planu',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Pal.textDim, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${state.earnedToday} / ${AppState.dailyPool.toInt()}',
                      style: const TextStyle(color: Pal.text, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Bar(
                  value: state.earnedToday / AppState.dailyPool,
                  color: Pal.spark,
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 6),
                if (state.isRestDay)
                  _planMessage(
                    'Odpoczynek też jest częścią planu.',
                    'Twoje wpisy, iskry i osada zostają. Możesz wrócić do planu jeszcze dziś.',
                    action: TextButton.icon(
                      onPressed: () => _rest(false),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text('Wracam do planu'),
                    ),
                  )
                else if (state.activeGoals.isEmpty && state.goals.isEmpty)
                  _planMessage(
                    'Zacznij od jednego celu.',
                    'Wybierz coś małego, co chcesz zrobić dla siebie. Twój świat będzie rósł razem z Tobą.',
                    action: FilledButton.icon(
                      onPressed: _firstGoal,
                      style: FilledButton.styleFrom(
                        backgroundColor: Pal.accent,
                        foregroundColor: Pal.onAccent,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Wybierz pierwszy cel'),
                    ),
                  )
                else if (state.goals.isEmpty)
                  _planMessage(
                    'Dziś masz wolne.',
                    'Cele wrócą w wybrane dni. Możesz zajrzeć do planu poniżej.',
                  )
                else
                  for (final g in state.goals) ...[
                    const Divider(color: Pal.divider, height: 1),
                    _GoalRow(
                      goal: g,
                      buttonKey: _buttonKeys.putIfAbsent(g.id, GlobalKey.new),
                      onLog: () => _log(g),
                    ),
                  ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _manageGoals,
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Moje cele'),
                    ),
                    if (!state.isRestDay &&
                        (state.activeGoals.isNotEmpty ||
                            state.goals.isNotEmpty))
                      TextButton.icon(
                        onPressed: () => _rest(true),
                        icon: const Icon(Icons.spa_outlined, size: 18),
                        label: const Text('Dziś odpoczywam'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _planMessage(String title, String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 23,
            color: Pal.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(color: Pal.textDim, fontSize: 15)),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    ),
  );
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.goal,
    required this.buttonKey,
    required this.onLog,
  });

  final Goal goal;
  final GlobalKey buttonKey;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          goal.title,
          style: const TextStyle(
            color: Pal.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          goal.subtitle,
          style: const TextStyle(color: Pal.textDim, fontSize: 14),
        ),
        if (!goal.isTask) ...[
          const SizedBox(height: 8),
          _Bar(value: goal.fraction, color: Pal.accent),
        ],
      ],
    );
    final action = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, a) => ScaleTransition(
        scale: a,
        child: FadeTransition(opacity: a, child: child),
      ),
      child: goal.done
          ? const Padding(
              key: ValueKey('done'),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Text(
                'Gotowe ✓',
                style: TextStyle(color: Pal.accent, fontSize: 15),
              ),
            )
          : _PressButton(
              key: buttonKey,
              label: goal.stepLabel,
              primary: !goal.isTask,
              onTap: onLog,
            ),
    );
    final stackAction =
        MediaQuery.textScalerOf(context).scale(17) > 23 ||
        goal.stepLabel.length > 12;
    final row = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Pal.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(categoryIcon(goal.category), color: Pal.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: details),
        if (!stackAction) ...[const SizedBox(width: 14), action],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: stackAction
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            )
          : row,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Container(
        height: 5,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Pal.divider,
          borderRadius: BorderRadius.circular(3),
        ),
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Squishes on press so logging feels physical.
class _PressButton extends StatefulWidget {
  const _PressButton({
    super.key,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 84,
            maxWidth: 240,
            minHeight: 54,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.primary ? Pal.accent : Pal.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.primary ? Pal.onAccent : Pal.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
